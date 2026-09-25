import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/playback_source.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../data/repositories/fm_repository.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_token_holder.dart';
import '../likes/likes_controller.dart';
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';

/// How many tracks to keep in hand before asking for more.
const kFmTargetPool = 30;

/// Below this many *unplayed* tracks left we top the pool up in the background.
const kFmRefillThreshold = 6;

/// 单次取数希望拿到的批量。
///
/// 酷狗一次给一整批（≈30 首）自然满足；网易私人 FM 一次只回 1 首，需循环
/// 拼装到本值，否则开场队列只有一首、续流也永远补不开。
const kFmSeedBatch = 10;

/// 单次取数的循环上限：网易一次 1 首时最多再补 9 次，避免接口抖动打爆请求。
const kFmSeedBatchMaxCalls = 10;

/// 一次私人 FM 会话的全部状态。
///
/// 会话期间**播放器队列就是 FM 池**（单一事实来源）：
/// 控制器只往尾部追加，因此播放器游标天然等于「第几首」。
/// 不喜欢的歌当场从队列里摘掉，播放器自动续播永远落不到它头上
/// （这是 `af960f0` 修的那条：过滤必须发生在队列下发之前）。
class FmSession {
  const FmSession({
    this.active = false,
    this.source,
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

  /// 当前会话所属音源。`null` = 尚未选定（按设置里的默认源解析）。
  ///
  /// 切源会**结束当前会话并以新源重开**（见 [FmController.switchSource]）：
  /// 一次会话内的曲目只来自一个源，不混源。
  final MusicPlatform? source;

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
    MusicPlatform? source,
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
      source: source ?? this.source,
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
          'source': s.source?.wireName ?? '',
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

  /// 旧数据没有 `source` 字段：留 `null` 交给设置里的默认源解析，不写死酷狗。
  static MusicPlatform? _readSource(Object? raw) {
    final text = raw?.toString() ?? '';
    return text.isEmpty ? null : MusicPlatform.fromWire(text);
  }

  FmSession? loadSync(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      return FmSession(
        active: true,
        source: _readSource(map['source']),
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
  FmController();

  /// 上一次见到的播放器游标，用来判断「跨过了上一首」。
  int _lastIndex = -1;

  /// 防止「应用待生效轴 → 重下队列 → 游标又变 → 再应用」的自环路。
  bool _applyingPending = false;

  @override
  FmSession build() {
    // 播放器推进时：接近池尾就续流；跨过一首就应用待生效轴。
    ref.listen(playerControllerProvider, _onPlayerChanged);
    // 设置里改动整源开关后：当前会话源被停用时切剩余源重开。
    ref.listen(settingsControllerProvider, _onEnabledSourcesChanged);
    return const FmSession();
  }

  // ------------------------------------------------------------------ 音源分发

  /// 已启用且**该源私人 FM 功能未关**、并具备 [PersonalFmSource] 的音源（注册表顺序）。
  List<MusicPlatform> availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final settings = ref.read(settingsControllerProvider);
    return registry.platforms
        .where((p) =>
            settings.isFeatureEnabled(p, SourceFeature.personalFm) &&
            registry.capability<PersonalFmSource>(p) != null)
        .toList();
  }

  /// 当前（或下次开台）应当使用的音源。
  ///
  /// 已有会话时以会话源为准（队列里的歌都来自它，换显示源会误读）；否则按
  /// 设置里的「默认源」解析，不可用时退首个可用源。
  MusicPlatform? effectiveSource() {
    final available = availableSources();
    if (available.isEmpty) return null;
    final session = state.source;
    if (session != null && available.contains(session)) return session;
    return _resolveSource(available);
  }

  /// 首选项 = 设置里的默认源（停用后 `effectiveDefaultSource` 已自动回落）。
  MusicPlatform? _resolveSource(List<MusicPlatform> available) {
    if (available.isEmpty) return null;
    final preferred =
        ref.read(settingsControllerProvider).effectiveDefaultSource;
    return available.contains(preferred) ? preferred : available.first;
  }

  /// 供 UI 渲染的音源：会话源优先，否则「下次开台」的解析结果。
  MusicPlatform? get displaySource => state.source ?? effectiveSource();

  /// 当前音源是否带「模式 / 曲库」档位轴（[HeartRadioSource] 是酷狗独有语义；
  /// 网易私人 FM 没有这层轴，UI 据此隐藏整块档位控件）。
  bool get hasModeAxis {
    final platform = displaySource;
    if (platform == null) return false;
    return musicSourceRegistry?.capability<HeartRadioSource>(platform) != null;
  }

  /// 两级开关（整源 + 该源的私人 FM 功能）联动：当前会话源不再可用 →
  /// 用剩余源重开（一次会话不混源）；一个都不剩 → 收掉进行中的会话
  /// （已入队曲目仍可播，但不再续流）。
  void _onEnabledSourcesChanged(AppSettings? prev, AppSettings next) {
    if (prev?.enabledSources == next.enabledSources &&
        prev?.disabledFeatures == next.disabledFeatures) {
      return;
    }
    final available = availableSources();
    if (available.isEmpty) {
      if (state.active) _deactivate();
      return;
    }
    if (state.active && !available.contains(state.source)) {
      final target = _resolveSource(available);
      if (target != null) unawaited(start(source: target));
    }
  }

  /// 本轮取数使用的音源；`null` = 没有可用源。
  MusicPlatform? get _sessionSource => state.source;

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
    // 旧数据可能没有源（字段是后加的）：按设置里的默认源补一个。
    state = saved.copyWith(
      source: saved.source ?? _resolveSource(availableSources()),
    );
    _lastIndex = player.currentIndex;
  }

  /// 开一场新的 FM 会话（入口卡片 / 我的页入口调用）。
  ///
  /// [source] 省略时沿用会话已选源（不可用则按默认源解析）。
  Future<void> start({
    FmMode? mode,
    FmSongPool? pool,
    MusicPlatform? source,
  }) async {
    final m = mode ?? state.mode;
    final p = pool ?? state.pool;
    final available = availableSources();
    final sessionSource = state.source;
    final target = source ??
        (sessionSource != null && available.contains(sessionSource)
            ? sessionSource
            : _resolveSource(available));
    if (target == null) {
      state = const FmSession(gatewayError: '没有可用的私人 FM 音源，请到设置里开启');
      return;
    }
    state = FmSession(
      active: true,
      source: target,
      mode: m,
      pool: p,
      pendingMode: m,
      pendingPool: p,
      usedQueries: {...state.usedQueries},
      disliked: {...state.disliked},
      loading: true,
    );
    // 本地登录态是异步恢复的；不等 token 就取歌会永远落到关键词池，
    // 并把 fromServer=false 持久化下去，看起来像「接口打不通」。
    try {
      await ref.read(authControllerProvider.notifier).ensureReady();
    } catch (_) {}
    final tracks = await _seed();
    if (!state.active) return;
    if (tracks.isEmpty) {
      state = state.copyWith(
        loading: false,
        error: state.gatewayError.isNotEmpty
            ? state.gatewayError
            : 'FM 歌池加载失败，请检查网络',
      );
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

  /// 切源：立刻结束当前会话并以新源重开（一次会话不混源）。
  ///
  /// 未起播时只改「下次开台」的源，避免点一下就白跑一次取数。
  Future<void> switchSource(MusicPlatform platform) async {
    if (platform == state.source) return;
    if (!state.active) {
      state = state.copyWith(source: platform);
      return;
    }
    await start(source: platform);
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
    // 上报垃圾桶：语义由源映射（酷狗 action=garbage；网易暂无端点，是空实现）。
    final platform = _sessionSource;
    final fm = platform == null
        ? null
        : musicSourceRegistry?.capability<PersonalFmSource>(platform);
    if (state.fromServer && fm != null) {
      unawaited(fm.reportFmFeedback(track, feedback: FmFeedback.trash));
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
    final likes = ref.read(likesProvider.notifier);
    // 网易曲库写口未接（F4 未实测）：只在本地「我喜欢」生效，
    // 绝不把网易曲目写进酷狗歌单（那会污染曲库）。
    if (_sessionSource == MusicPlatform.kugou) {
      await likes.like(track);
    } else {
      await likes.likeLocal(track);
    }
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
  ///
  /// 取数一律经 `registry.capability<PersonalFmSource>(会话源)`；只有带档位
  /// 语义的源（酷狗，实现 [HeartRadioSource]）在失败时回落本地关键词池 ——
  /// 网易私人 FM 是登录后的个性化流，用公开搜索冒充会误导用户。
  Future<List<Track>> _collect({required bool fresh}) async {
    final registry = musicSourceRegistry;
    final platform = _sessionSource;
    final fm = (registry == null || platform == null)
        ? null
        : registry.capability<PersonalFmSource>(platform);
    if (fm == null) {
      state = state.copyWith(
        fromServer: false,
        gatewayError: '当前音源不支持私人 FM',
      );
      return const [];
    }
    final heart = registry!.capability<HeartRadioSource>(platform!);
    if (fresh && heart != null) {
      // 档位/曲库先同步给源实现，再取第一批（网易没有这层轴）。
      await heart.setHeartMode(mode: state.mode, pool: state.pool);
    }
    // 有本地关键词兜底的源（酷狗）：未登录时直接走兜底池 —— 接口必然拒绝，
    // 不值得发一次注定失败的请求。网易没有兜底，必须请求才知道「需要登录」。
    if (heart != null && !AuthTokenHolder.instance.hasToken) {
      return _collectFromKeywords(fresh: fresh);
    }

    final player = ref.read(playerControllerProvider);
    final unplayed =
        (player.queue.length - player.currentIndex - 1).clamp(0, 1 << 30);
    // remain_songcnt>4 时服务端只回会话元数据、不给歌。开新会话必须传 0，
    // 否则会带着旧队列剩余数（如 25）去要 FM，被误判成「私人FM加载失败」。
    final remain = clampRemainSongcnt(fresh: fresh, unplayed: unplayed);

    var tracks = const <Track>[];
    var failure = '';
    try {
      tracks = await fm.nextFmTracks(remain: remain);
      // 网易 FM 一次只回 1 首：补到目标批量，否则开场队列只有一首。
      // 酷狗一次给一整批，循环不会进入。
      var calls = 1;
      while (tracks.isNotEmpty &&
          tracks.length < kFmSeedBatch &&
          calls < kFmSeedBatchMaxCalls &&
          state.active &&
          state.source == platform) {
        final more = await fm.nextFmTracks(remain: 0);
        if (more.isEmpty) break;
        tracks = [...tracks, ...more];
        calls++;
      }
    } on SourceFailure catch (e) {
      failure = e.message;
    } catch (_) {
      failure = '';
    }

    if (tracks.isNotEmpty) {
      state = state.copyWith(fromServer: true, gatewayError: '');
      return tracks;
    }
    if (heart == null) {
      // 无关键词兜底的源：把失败原因（如「需要登录」）如实报到 UI。
      state = state.copyWith(
        fromServer: false,
        gatewayError: failure.isNotEmpty ? failure : '私人 FM 加载失败，请检查网络',
      );
      return const [];
    }
    state = state.copyWith(fromServer: false, gatewayError: failure);
    return _collectFromKeywords(fresh: fresh);
  }

  /// 关键词兜底池：多关键词检索 + 去重 + 不喜欢过滤 + 关键词轮换。
  Future<List<Track>> _collectFromKeywords({required bool fresh}) async {
    final registry = musicSourceRegistry;
    final platform = _sessionSource;
    if (registry == null || platform == null) return const [];
    // 兜底检索同样走「会话源」的搜索口，不跨源。
    final source = registry.of(platform);
    if (fresh) state = state.copyWith(usedQueries: {});
    final keywords = state.pool.keywordsFor(state.mode);
    final remaining = keywords.where((k) => !state.usedQueries.contains(k)).toList();
    final order = remaining.isEmpty ? keywords.toList() : remaining;
    order.shuffle(Random());

    final out = <Track>[];
    final seen = fresh
        ? <String>{}
        : <String>{
            for (final t in ref.read(playerControllerProvider).queue)
              t.id.isNotEmpty ? t.id : t.hash,
          };
    for (final keyword in order) {
      try {
        final page = await source.searchSongs(keyword, pageSize: 20);
        state = state.copyWith(usedQueries: {...state.usedQueries, keyword});
        for (final t in page.items) {
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
