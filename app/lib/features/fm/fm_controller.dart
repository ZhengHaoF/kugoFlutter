import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/playback_source.dart';
import '../../core/models/track.dart';
import '../../data/repositories/fm_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../auth/auth_token_holder.dart';
import '../likes/likes_controller.dart';
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';

/// How many tracks to keep in hand before asking for more.
const kFmTargetPool = 30;

/// Below this many *unplayed* tracks left we top the pool up in the background.
const kFmRefillThreshold = 6;

/// 一次私人 FM 会话的全部状态。
///
/// 会话期间**播放器队列就是 FM 池**（单一事实来源）：
/// 控制器只往尾部追加，因此播放器游标天然等于「第几首」。
/// 不喜欢的歌当场从队列里摘掉，播放器自动续播永远落不到它头上
/// （这是 `af960f0` 修的那条：过滤必须发生在队列下发之前）。
class FmSession {
  const FmSession({
    this.active = false,
    this.mode = FmMode.heart,
    this.pool = FmSongPool.taste,
    this.pendingMode = FmMode.heart,
    this.pendingPool = FmSongPool.taste,
    this.disliked = const {},
    this.usedQueries = const {},
    this.fromServer = false,
    this.loading = false,
    this.appending = false,
    this.exhausted = false,
    this.error = '',
    this.gatewayError = '',
  });

  /// 是否存在进行中的 FM 会话（播放页据此显示 FM 控件）。
  final bool active;

  /// 当前生效的电台档位（红心/小众/速览 → 接口 `mode`）。
  final FmMode mode;

  /// 当前生效的歌池（Alpha/Beta/Gamma → 接口 `song_pool_id`）。
  final FmSongPool pool;

  /// 下一首生效的档位/歌池。见 [hasPendingChange]。
  final FmMode pendingMode;
  final FmSongPool pendingPool;

  /// 已不喜欢的曲目 key（本地过滤 + 真接口模式下会上报 `action=garbage`）。
  final Set<String> disliked;

  /// 已抽取过的关键词，续流时向前走而不是反复拉第 1 页。
  final Set<String> usedQueries;

  /// 当前池子是否来自酷狗真实推荐接口。
  final bool fromServer;
  final bool loading;
  final bool appending;
  final bool exhausted;
  final String error;
  final String gatewayError;

  /// 有轴被切过、但还没到下一首生效。
  bool get hasPendingChange => pendingMode != mode || pendingPool != pool;

  FmSession copyWith({
    bool? active,
    FmMode? mode,
    FmSongPool? pool,
    FmMode? pendingMode,
    FmSongPool? pendingPool,
    Set<String>? disliked,
    Set<String>? usedQueries,
    bool? fromServer,
    bool? loading,
    bool? appending,
    bool? exhausted,
    String? error,
    String? gatewayError,
  }) {
    return FmSession(
      active: active ?? this.active,
      mode: mode ?? this.mode,
      pool: pool ?? this.pool,
      pendingMode: pendingMode ?? this.pendingMode,
      pendingPool: pendingPool ?? this.pendingPool,
      disliked: disliked ?? this.disliked,
      usedQueries: usedQueries ?? this.usedQueries,
      fromServer: fromServer ?? this.fromServer,
      loading: loading ?? this.loading,
      appending: appending ?? this.appending,
      exhausted: exhausted ?? this.exhausted,
      error: error ?? this.error,
      gatewayError: gatewayError ?? this.gatewayError,
    );
  }
}

/// FM 会话的 SharedPreferences 持久化。
///
/// **曲目不入库**：它们本来就由 `QueueStore`（Drift）持久化，冷启动时播放器
/// 会先把队列恢复出来，这里只需认领「那个队列就是 FM 流」。为避免误认，
/// 存一个种子曲目 id 做指纹。
class FmSessionStore {
  static const _key = 'fm.session';

  Future<void> save(FmSession s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!s.active) {
        await prefs.remove(_key);
        return;
      }
      await prefs.setString(
        _key,
        jsonEncode({
          'mode': s.mode.name,
          'pool': s.pool.name,
          'pendingMode': s.pendingMode.name,
          'pendingPool': s.pendingPool.name,
          'disliked': s.disliked.toList(),
          'usedQueries': s.usedQueries.toList(),
          'fromServer': s.fromServer,
        }),
      );
    } catch (_) {}
  }

  FmSession? loadSync(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return FmSession(
        active: true,
        mode: FmMode.values.firstWhere((e) => e.name == map['mode'],
            orElse: () => FmMode.heart),
        pool: FmSongPool.values.firstWhere((e) => e.name == map['pool'],
            orElse: () => FmSongPool.taste),
        pendingMode: FmMode.values.firstWhere(
            (e) => e.name == map['pendingMode'],
            orElse: () => FmMode.heart),
        pendingPool: FmSongPool.values.firstWhere(
            (e) => e.name == map['pendingPool'],
            orElse: () => FmSongPool.taste),
        disliked: {...?(map['disliked'] as List?)},
        usedQueries: {...?(map['usedQueries'] as List?)},
        fromServer: map['fromServer'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

final fmSessionStore = FmSessionStore();

/// 私人 FM 会话控制器。
///
/// 与旧 `personal_fm_page.dart` 的关系：那套逻辑原本长在页面里，页面删掉后
/// 搬到这里。播放页只读 [FmSession] 渲染一个入口 + 一个 BottomSheet，
/// 不再拥有任何 FM 状态。
class FmController extends Notifier<FmSession> {
  // ignore: prefer_initializing_formals — 参数名要能对外注入测试替身
  FmController({SearchRepository? search}) : _search = search;

  final SearchRepository? _search;

  SearchRepository get _repo => _search ?? searchRepository;

  /// 上一次见到的播放器游标，用来判断「跨过了上一首」。
  int _lastIndex = -1;

  /// 防止「应用待生效轴 → 重下队列 → 游标又变 → 再应用」的自环路。
  bool _applyingPending = false;

  @override
  FmSession build() {
    // 播放器推进时：接近池尾就续流；跨过一首就应用待生效轴。
    ref.listen(playerControllerProvider, _onPlayerChanged);
    return const FmSession();
  }

  void _onPlayerChanged(PlayerState? prev, PlayerState player) {
    if (!state.active) return;

    // 用户去放别的队列了 → FM 会话结束。
    if (player.queueSource != PlaybackQueueSource.fm) {
      _deactivate();
      return;
    }
    if (player.currentIndex != _lastIndex) {
      _lastIndex = player.currentIndex;
      if (state.hasPendingChange && !_applyingPending) {
        unawaited(_applyPending());
        return;
      }
    }
    // 接近池尾就后台续流，播到边界前把歌补上。
    if (player.currentIndex >= player.queue.length - kFmRefillThreshold) {
      unawaited(_append());
    }
  }

  bool get _gatewayWanted =>
      ref.read(settingsControllerProvider).fmRealRecommend &&
      AuthTokenHolder.instance.hasToken;

  // ---------------------------------------------------------------- 生命周期

  /// 冷启动认领：播放器恢复出来的队列若与 FM 指纹相符，就接回会话。
  Future<void> restore() async {
    final player = ref.read(playerControllerProvider);
    if (player.queue.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = fmSessionStore.loadSync(prefs);
    if (saved == null) return;
    final seed = player.queue.first;
    final fingerprint = prefs.getString('${FmSessionStore._key}.seed');
    if (fingerprint == null || fingerprint != (seed.id.isNotEmpty ? seed.id : seed.hash)) {
      return;
    }
    ref.read(playerControllerProvider.notifier)
        .markQueueSource(PlaybackQueueSource.fm);
    state = saved;
    _lastIndex = player.currentIndex;
  }

  /// 开一场新的 FM 会话（入口卡片 / 我的页入口调用）。
  Future<void> start({FmMode? mode, FmSongPool? pool}) async {
    final m = mode ?? state.mode;
    final p = pool ?? state.pool;
    state = FmSession(
      active: true,
      mode: m,
      pool: p,
      pendingMode: m,
      pendingPool: p,
      usedQueries: {...state.usedQueries},
      disliked: {...state.disliked},
      loading: true,
    );
    final tracks = await _seed();
    if (!state.active) return;
    if (tracks.isEmpty) {
      state = state.copyWith(loading: false, error: 'FM 歌池加载失败，请检查网络');
      return;
    }
    state = state.copyWith(loading: false);
    await ref.read(playerControllerProvider.notifier).playQueue(
          tracks,
          source: PlaybackQueueSource.fm,
        );
    _lastIndex = 0;
    await _persist();
  }

  void _deactivate() {
    if (!state.active) return;
    state = const FmSession();
    unawaited(fmSessionStore.save(state));
  }

  // ------------------------------------------------------------------ 轴切换

  /// 切歌池 / 档位：**下一首生效**，不打断正在听的歌。
  void setPendingPool(FmSongPool pool) {
    if (pool == state.pendingPool) return;
    state = state.copyWith(pendingPool: pool);
    unawaited(_persist());
  }

  void setPendingMode(FmMode mode) {
    if (mode == state.pendingMode) return;
    state = state.copyWith(pendingMode: mode);
    unawaited(_persist());
  }

  /// 立刻按待生效轴重开一场会话。
  Future<void> applyPendingNow() async {
    if (!state.hasPendingChange) return;
    await start(mode: state.pendingMode, pool: state.pendingPool);
  }

  Future<void> _applyPending() async {
    _applyingPending = true;
    try {
      await start(mode: state.pendingMode, pool: state.pendingPool);
    } finally {
      _applyingPending = false;
    }
  }

  // ------------------------------------------------------------------ 播放控制

  /// 下一首。播放器自己会推进；这里只负责「真到池尾时先续上」。
  Future<void> next() => ref.read(playerControllerProvider.notifier).next();

  /// 上一首：仅池内回退，边界禁用（双保险，禁用态见 `PlayerState.canStepBack`）。
  Future<void> previous() =>
      ref.read(playerControllerProvider.notifier).previous();

  void togglePlay() =>
      ref.read(playerControllerProvider.notifier).togglePlay();

  /// 不喜欢：当场从队列摘掉 + 真接口模式下上报 garbage，然后照常推进。
  Future<void> dislike() async {
    final player = ref.read(playerControllerProvider);
    final track = player.current;
    if (track == null) return;
    final key = track.id.isNotEmpty ? track.id : track.hash;

    state = state.copyWith(disliked: {...state.disliked, key});
    if (state.fromServer) {
      unawaited(fmRepository.reportGarbage(
        track: track,
        mode: state.mode,
        pool: state.pool,
      ));
    }

    // 从队列里摘掉当前这首：它后面的那首会顶到 currentIndex，
    // 于是 startIndex 不变就是「跳到下一首」，且播放器永远碰不到它。
    final q = player.queue.where((t) => (t.id.isNotEmpty ? t.id : t.hash) != key).toList();
    if (q.isEmpty) {
      await _append();
      return;
    }
    await ref.read(playerControllerProvider.notifier).playQueue(
          q,
          source: PlaybackQueueSource.fm,
        );
    if (q.length - ref.read(playerControllerProvider).currentIndex <=
        kFmRefillThreshold) {
      unawaited(_append());
    }
    await _persist();
  }

  Future<void> like() async {
    final track = ref.read(playerControllerProvider).current;
    if (track == null) return;
    // 喜欢不打断收听：只是收藏，红心由调用方给反馈。
    await ref.read(likesProvider.notifier).like(track);
  }

  // ------------------------------------------------------------------ 取歌/续流

  Future<List<Track>> _seed() => _collect(fresh: true);

  Future<List<Track>> _append() async {
    if (state.appending || state.exhausted || !state.active) return const [];
    state = state.copyWith(appending: true);
    final more = await _collect(fresh: false);
    final player = ref.read(playerControllerProvider);
    if (!state.active || player.queueSource != PlaybackQueueSource.fm) {
      state = state.copyWith(appending: false);
      return const [];
    }
    if (more.isEmpty) {
      state = state.copyWith(appending: false, exhausted: true);
      return const [];
    }
    state = state.copyWith(appending: false);
    await ref.read(playerControllerProvider.notifier).appendToQueue(more);
    await _persist();
    return more;
  }

  /// 取一批候选曲。
  ///
  /// [fresh] = 重新开池（重置关键词轮盘）；否则是续流（接着往前走）。
  Future<List<Track>> _collect({required bool fresh}) async {
    if (_gatewayWanted) {
      final player = ref.read(playerControllerProvider);
      final current = player.current;
      final unplayed =
          (player.queue.length - player.currentIndex - 1).clamp(0, 1 << 30);
      final page = await fmRepository.fetch(
        mode: state.mode,
        pool: state.pool,
        hash: current?.hash ?? '',
        songid: current?.id ?? '',
        remainSongcnt: unplayed,
        action: fresh ? 'play' : 'play',
      );
      if (page.tracks.isNotEmpty) {
        state = state.copyWith(fromServer: true, gatewayError: '');
        return page.tracks;
      }
      // 网关拒了（未登录/空/报错）：记下原因并落回关键词池，页面不空转。
      state = state.copyWith(fromServer: false, gatewayError: page.error);
    }
    return _collectFromKeywords(fresh: fresh);
  }

  /// 关键词兜底池：多关键词检索 + 去重 + 不喜欢过滤 + 关键词轮换。
  Future<List<Track>> _collectFromKeywords({required bool fresh}) async {
    if (fresh) state = state.copyWith(usedQueries: {});
    final keywords = state.pool.keywordsFor(state.mode);
    final remaining = keywords.where((k) => !state.usedQueries.contains(k)).toList();
    final order = remaining.isEmpty ? keywords.toList() : remaining;
    order.shuffle(Random());

    final out = <Track>[];
    final seen = <String>{for (final t in ref.read(playerControllerProvider).queue) t.id};
    for (final keyword in order) {
      try {
        final page = await _repo.searchSongs(keyword, pageSize: 20);
        state = state.copyWith(usedQueries: {...state.usedQueries, keyword});
        for (final t in page) {
          final key = t.id.isNotEmpty ? t.id : t.hash;
          if (key.isEmpty || !seen.add(key)) continue;
          if (state.disliked.contains(key)) continue;
          out.add(t);
        }
      } catch (_) {
        // 一个关键词失败不该拖垮整池。
        continue;
      }
      if (out.length >= kFmTargetPool) break;
    }
    // 速览是唯一带本地规则的档位：短曲优先。过滤后所剩无几就放弃过滤，
    // 宁愿给普通长度也不给空页面。
    if (state.mode.preferShort && out.length > 8) {
      final short = out
          .where((t) => t.durationMs > 0 && t.durationMs <= 4 * 60 * 1000)
          .toList();
      if (short.length >= 5) return short;
    }
    return out;
  }

  // ------------------------------------------------------------------ 持久化

  Future<void> _persist() async {
    final player = ref.read(playerControllerProvider);
    final current = player.current;
    final seed = current?.id.isNotEmpty == true
        ? current!.id
        : (current?.hash ?? '');
    await fmSessionStore.save(state);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${FmSessionStore._key}.seed', seed);
    } catch (_) {}
  }
}

final fmControllerProvider = NotifierProvider<FmController, FmSession>(
  FmController.new,
);
