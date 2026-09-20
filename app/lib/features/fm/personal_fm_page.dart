import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/fm_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/auth/auth_token_holder.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/cover_box.dart';
import '../../core/theme/kugo_theme.dart';

/// How many tracks to keep in hand before asking for more.
const _kFmTargetPool = 30;

/// Below this many *unplayed* tracks left we top the pool up in the background.
const _kFmRefillThreshold = 6;

/// 私人 FM 页。
///
/// 数据源有两套，运行时二选一（见 [_useGateway]）：
///
/// 1. **酷狗真实推荐**（`fmRepository` → `POST /v2/personal_recommend`，
///    router `persnfm.service.kugou.com`）。这是唯一能吃到
///    `mode`（红心/小众/速览）+ `song_pool_id`（口味/风格/探索）真参数的路，
///    但**必须登录**（未登录返回 `error_code:200101`）。
///    打开方式：设置 → 私人 FM → 「使用酷狗真实推荐（实验）」。
/// 2. **关键词歌池**（`searchRepository`）。上述接口不可用时的兜底：
///    多关键词检索 + 本地不喜欢过滤 + 永不重复的续流。
///
/// 无论走哪套，页面都会用一行小字标明**当前数据源**，不把兜底伪装成个性化。
class PersonalFmPage extends ConsumerStatefulWidget {
  const PersonalFmPage({super.key, this.repository, this.useGateway});

  /// Test seam: override the search source. Production uses the singleton.
  final SearchRepository? repository;

  /// Force the real gateway FM on/off. `null` follows settings.
  final bool? useGateway;

  @override
  ConsumerState<PersonalFmPage> createState() => _PersonalFmPageState();
}

class _PersonalFmPageState extends ConsumerState<PersonalFmPage>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _bars;

  SearchRepository get _repo => widget.repository ?? searchRepository;

  FmMode _mode = FmMode.heart;
  FmSongPool _pool = FmSongPool.taste;
  List<Track> _tracks = const [];
  bool _loading = true;
  bool _appending = false;
  bool _exhausted = false;
  bool _fromServer = false;
  String _error = '';
  String _gatewayError = '';

  /// Ids the user thumbed-down. Honoured across refills, across pool switches
  /// and — on the gateway path — also reported upstream as `action=garbage`.
  final _disliked = <String>{};

  /// Guards against a slow response from a previous pool/request landing after
  /// a newer one and clobbering the list.
  int _requestToken = 0;

  /// Searches already issued for the current pool, so refills walk forward
  /// through the keyword list instead of re-fetching page 1 forever.
  final _usedQueries = <String>{};

  /// Index of the track in [_tracks] we last handed to the player. Only a hint
  /// for "which one is mine" — the authoritative index is the player's own
  /// `currentIndex` (see [_resolveIndex]).
  int _anchorIndex = 0;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _bars = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    _bars.dispose();
    super.dispose();
  }

  /// Whether the real gateway FM is wanted **and** actually usable.
  bool get _gatewayWanted {
    final override = widget.useGateway;
    final enabled =
        override ?? ref.read(settingsControllerProvider).fmRealRecommend;
    return enabled && AuthTokenHolder.instance.hasToken;
  }

  /// Map the player's current track back onto [_tracks].
  int? _resolveIndex() {
    if (_tracks.isEmpty) return null;
    final current = ref.read(playerControllerProvider).current;
    if (current == null) return null;
    final i = _tracks.indexWhere((t) => t.id == current.id);
    return i < 0 ? null : i;
  }

  /// Which track to render: the player's, falling back to the anchor while the
  /// player is empty (first load / after a pool switch).
  Track? _displayTrack() {
    final player = ref.watch(playerControllerProvider);
    final current = player.current;
    if (current != null && _tracks.any((t) => t.id == current.id)) {
      return current;
    }
    if (_tracks.isEmpty) return null;
    return _tracks[_anchorIndex.clamp(0, _tracks.length - 1)];
  }

  /// Upcoming (not disliked) tracks after the current one — the "next" discs.
  List<Track> _upcoming({int max = 3}) {
    if (_tracks.isEmpty) return const [];
    final from = _resolveIndex() ?? _anchorIndex;
    final out = <Track>[];
    for (var i = from + 1; i < _tracks.length && out.length < max; i++) {
      final key = _tracks[i].id.isNotEmpty ? _tracks[i].id : _tracks[i].hash;
      if (_disliked.contains(key)) continue;
      out.add(_tracks[i]);
    }
    return out;
  }

  Future<void> _load({bool keepDisliked = true}) async {
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = '';
      _gatewayError = '';
      _exhausted = false;
      _fromServer = false;
      _tracks = const [];
      _anchorIndex = 0;
      _usedQueries.clear();
      if (!keepDisliked) _disliked.clear();
    });

    if (_gatewayWanted) {
      final page = await fmRepository.fetch(
        mode: _mode,
        pool: _pool,
        remainSongcnt: 0,
      );
      if (!mounted || token != _requestToken) return;
      if (page.tracks.isNotEmpty) {
        setState(() {
          _tracks = page.tracks;
          _fromServer = true;
          _loading = false;
        });
        _playAt(0);
        return;
      }
      // Gateway refused (not logged in / empty / error) — keep the reason and
      // fall through to the keyword pool so the page never dead-ends.
      _gatewayError = page.error;
    }

    final list = await _fetch(token);
    if (!mounted || token != _requestToken) return;
    if (list.isEmpty) {
      setState(() {
        _loading = false;
        _error = _gatewayError.isNotEmpty ? _gatewayError : 'FM 歌池加载失败，请检查网络';
      });
      return;
    }
    setState(() {
      _tracks = list;
      _loading = false;
    });
    _playAt(0);
  }

  /// Pull a page from one of this pool's keywords, skipping any keyword already
  /// drawn (unless every one has been used, in which case re-draw from the
  /// start so the stream never hard-stops).
  Future<List<Track>> _fetch(int token, {int pageSize = 20}) async {
    final keywords = _pool.keywordsFor(_mode);
    final remaining = keywords.where((k) => !_usedQueries.contains(k)).toList();
    final pool = remaining.isEmpty ? keywords.toList() : remaining;
    pool.shuffle(Random());

    final out = <Track>[];
    final seen = <String>{};
    for (final keyword in pool) {
      if (!mounted || token != _requestToken) return const [];
      try {
        final page = await _repo.searchSongs(
          keyword,
          pageSize: pageSize,
        );
        if (token != _requestToken) return const [];
        _usedQueries.add(keyword);
        for (final t in page) {
          final key = t.id.isNotEmpty ? t.id : t.hash;
          if (key.isEmpty || !seen.add(key)) continue;
          if (_disliked.contains(key)) continue;
          out.add(t);
        }
      } catch (_) {
        // One keyword failing should not sink the whole pool.
        continue;
      }
      if (out.length >= _kFmTargetPool) break;
    }
    // 速览 is the only mode with a local rule: prefer short tracks. If the
    // filter would gut the pool, keep everything rather than show an empty page.
    if (_mode.preferShort && out.length > 8) {
      final short = out.where((t) {
        final d = t.durationMs;
        return d > 0 && d <= 4 * 60 * 1000;
      }).toList();
      if (short.length >= 5) return short;
    }
    return out;
  }

  /// Append more tracks so a finished pool keeps flowing instead of looping
  /// back to song #1.
  Future<void> _append() async {
    if (_appending || _exhausted) return;
    final token = _requestToken;
    setState(() => _appending = true);

    List<Track> more;
    if (_fromServer) {
      final current = _displayTrack();
      final unplayed = _tracks.length - ((_resolveIndex() ?? -1) + 1);
      final page = await fmRepository.fetch(
        mode: _mode,
        pool: _pool,
        hash: current?.hash ?? '',
        songid: current?.id ?? '',
        remainSongcnt: unplayed.clamp(0, 1 << 30),
        action: 'play',
      );
      more = page.tracks;
    } else {
      more = await _fetch(token);
    }

    if (!mounted || token != _requestToken) {
      setState(() => _appending = false);
      return;
    }

    final existing = <String>{
      for (final t in _tracks) t.id.isNotEmpty ? t.id : t.hash,
    };
    final fresh = [
      for (final t in more)
        if (existing.add(t.id.isNotEmpty ? t.id : t.hash)) t,
    ];

    setState(() {
      _appending = false;
      if (fresh.isEmpty) {
        _exhausted = true;
      } else {
        _tracks = [..._tracks, ...fresh];
      }
    });
  }

  /// Hand the pool to the player. Disliked tracks are filtered out of the
  /// queue that actually reaches the player, so the player's own auto-advance
  /// can never land on a track the user rejected.
  void _playAt(int i) {
    if (_tracks.isEmpty) return;
    final idx = i.clamp(0, _tracks.length - 1);
    _anchorIndex = idx;
    final target = _tracks[idx];
    final queue = [
      for (final t in _tracks)
        if (!_disliked.contains(t.id.isNotEmpty ? t.id : t.hash)) t,
    ];
    if (queue.isEmpty) return;
    var start = queue.indexWhere((t) => t.id == target.id);
    if (start < 0) start = 0;
    ref.read(playerControllerProvider.notifier).playQueue(
          queue,
          startIndex: start,
        );
  }

  /// Advance to the next track that is not disliked.
  bool _advanceLocal(int from) {
    if (_tracks.isEmpty) return false;
    var i = from + 1;
    var guard = 0;
    while (i < _tracks.length && guard++ < _tracks.length) {
      final key = _tracks[i].id.isNotEmpty ? _tracks[i].id : _tracks[i].hash;
      if (!_disliked.contains(key)) {
        _playAt(i);
        return true;
      }
      i++;
    }
    return false;
  }

  /// Skip to the next track, extending the pool when we reach the end.
  void _next() {
    if (_tracks.isEmpty) return;
    final from = _resolveIndex() ?? _anchorIndex;
    final advanced = _advanceLocal(from);
    if (_tracks.length - from <= _kFmRefillThreshold) {
      unawaited(_append());
    }
    if (advanced) return;
    unawaited(_appendThenAdvance(from));
  }

  Future<void> _appendThenAdvance(int from) async {
    final before = _tracks.length;
    await _append();
    if (!mounted) return;
    if (_tracks.length > before) {
      _advanceLocal(from);
    }
  }

  void _dislike() {
    final track = _displayTrack();
    if (track != null) {
      final key = track.id.isNotEmpty ? track.id : track.hash;
      _disliked.add(key);
      if (_fromServer) {
        unawaited(fmRepository.reportGarbage(track: track, mode: _mode, pool: _pool));
      }
    }
    _next();
  }

  void _switchMode(FmMode mode) {
    // Deliberately NOT guarded by `_loading`: `_requestToken` exists precisely so
    // a switch during an in-flight request is safe (the stale response is
    // dropped). Guarding here would make rapid taps silently do nothing.
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _load();
  }

  void _switchPool(FmSongPool pool) {
    if (pool == _pool) return;
    setState(() => _pool = pool);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final track = _displayTrack();
    final index = _resolveIndex() ?? _anchorIndex;
    final accent =
        CoverPalette.accentFromSeed(track?.coverUrl ?? 'fm', kugo.palette);
    final upcoming = _upcoming();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(
            track?.coverUrl ?? 'fm',
            kugo.palette,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: KugoSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(kugo),
                _RadioCard(
                  kugo: kugo,
                  accent: accent,
                  mode: _mode,
                  pool: _pool,
                  onMode: _switchMode,
                  onPlay: () => ref
                      .read(playerControllerProvider.notifier)
                      .togglePlay(),
                  isPlaying: player.isPlaying,
                  bars: _bars,
                  trackName: track?.name ?? '',
                  artist: track?.artist ?? '',
                  loading: _loading,
                ),
                const SizedBox(height: KugoSpacing.lg),
                _VinylStage(
                  kugo: kugo,
                  accent: accent,
                  spin: _spin,
                  coverUrl: track?.coverUrl ?? 'fm',
                  playing: player.isPlaying,
                  upcoming: upcoming,
                  onPick: (t) {
                    final i = _tracks.indexWhere((e) => e.id == t.id);
                    if (i >= 0) _playAt(i);
                  },
                  onTapCurrent: () => ref
                      .read(playerControllerProvider.notifier)
                      .togglePlay(),
                ),
                const SizedBox(height: KugoSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KugoSpacing.xxl,
                  ),
                  child: Column(
                    children: [
                      Text(
                        track?.name ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.playerTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track?.artist ?? '',
                        style: kugo.caption,
                      ),
                      const SizedBox(height: KugoSpacing.md),
                      _InfoChips(kugo: kugo, track: track),
                      const SizedBox(height: 4),
                      _SourceBadge(
                        kugo: kugo,
                        fromServer: _fromServer,
                        gatewayError: _gatewayError,
                        pool: _pool,
                        mode: _mode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: KugoSpacing.lg),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(KugoSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_tracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(KugoSpacing.xl),
                    child: AsyncBody(
                      loading: false,
                      hasError: true,
                      isEmpty: false,
                      errorMessage: _error,
                      onRetry: _load,
                      child: const SizedBox.shrink(),
                    ),
                  )
                else
                  _ActionRow(
                    kugo: kugo,
                    accent: accent,
                    isPlaying: player.isPlaying,
                    onDislike: _dislike,
                    onToggle: () => ref
                        .read(playerControllerProvider.notifier)
                        .togglePlay(),
                    onLike: () async {
                      final t = _displayTrack();
                      if (t != null) {
                        await ref.read(likesProvider.notifier).like(t);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已加入我喜欢'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      }
                      _next();
                    },
                  ),
                const SizedBox(height: KugoSpacing.md),
                TextButton(
                  onPressed: () => context.push('/player'),
                  child: Text(
                    _appending
                        ? '正在续接歌池…'
                        : '打开播放页 · ${index + 1}/${_tracks.length}',
                    style: kugo.caption,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(KugoTheme kugo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              '私人 FM',
              textAlign: TextAlign.center,
              style: kugo.section,
            ),
          ),
          // 歌池轴：上游 song_pool_id 的代号（Alpha/Beta/Gamma），
          // 与 EchoMusic 的 radio-strategy-switch 同一位置（右上角）。
          Padding(
            padding: const EdgeInsets.only(right: KugoSpacing.sm),
            child: _CapsuleSwitch<FmSongPool>(
              kugo: kugo,
              values: FmSongPool.values,
              labelOf: (p) => p.label,
              selected: _pool,
              onChanged: _switchPool,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// EchoMusic `radio-card` 的等价物：模式轴 + 电台名 + 频谱 + 播放。
class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.kugo,
    required this.accent,
    required this.mode,
    required this.pool,
    required this.onMode,
    required this.onPlay,
    required this.isPlaying,
    required this.bars,
    required this.trackName,
    required this.artist,
    required this.loading,
  });

  final KugoTheme kugo;
  final Color accent;
  final FmMode mode;
  final FmSongPool pool;
  final ValueChanged<FmMode> onMode;
  final VoidCallback onPlay;
  final bool isPlaying;
  final AnimationController bars;
  final String trackName;
  final String artist;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(KugoSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.42),
              accent.withValues(alpha: 0.20),
              kugo.bg.withValues(alpha: 0.92),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模式轴：红心 / 小众 / 速览。
            _CapsuleSwitch<FmMode>(
              kugo: kugo,
              values: FmMode.values,
              labelOf: (m) => m.label,
              selected: mode,
              onChanged: onMode,
              onLightSurface: true,
            ),
            const SizedBox(height: KugoSpacing.md),
            Text(
              mode.stationTitle,
              style: kugo.greeting.copyWith(
                color: kugo.onCover,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              artist.isEmpty ? '${mode.subtitle} · ${pool.label}' : artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kugo.caption.copyWith(color: kugo.onCoverMuted),
            ),
            const SizedBox(height: KugoSpacing.md),
            Row(
              children: [
                Expanded(child: _Spectrum(bars: bars, active: isPlaying)),
                const SizedBox(width: KugoSpacing.md),
                _CircleIconButton(
                  icon: loading
                      ? Icons.hourglass_empty_rounded
                      : (isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                  size: 52,
                  background: Colors.white.withValues(alpha: 0.18),
                  iconColor: kugo.onAccent,
                  onTap: loading ? null : onPlay,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 唱片区：当前盘 + 最多 3 张侧立的后续盘（可点击直接播放）。
class _VinylStage extends StatelessWidget {
  const _VinylStage({
    required this.kugo,
    required this.accent,
    required this.spin,
    required this.coverUrl,
    required this.playing,
    required this.upcoming,
    required this.onPick,
    required this.onTapCurrent,
  });

  final KugoTheme kugo;
  final Color accent;
  final AnimationController spin;
  final String coverUrl;
  final bool playing;
  final List<Track> upcoming;
  final ValueChanged<Track> onPick;
  final VoidCallback onTapCurrent;

  @override
  Widget build(BuildContext context) {
    const currentSize = 176.0;
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 侧盘从远到近绘制，越近越亮、越大。
          for (var i = upcoming.length - 1; i >= 0; i--)
            _OffsetDisc(
              spin: spin,
              spinning: playing,
              coverUrl: upcoming[i].coverUrl,
              size: currentSize,
              dx: 34 + i * 30,
              scale: 0.80 - i * 0.09,
              opacity: 0.55 - i * 0.13,
              onTap: () => onPick(upcoming[i]),
            ),
          AnimatedBuilder(
            animation: spin,
            builder: (context, child) {
              final angle = playing ? spin.value * 2 * pi : 0.0;
              return Transform.rotate(angle: angle, child: child);
            },
            child: _Vinyl(
              coverUrl: coverUrl,
              size: currentSize,
              accent: accent,
              kugo: kugo,
              onTap: onTapCurrent,
            ),
          ),
        ],
      ),
    );
  }
}

class _OffsetDisc extends StatelessWidget {
  const _OffsetDisc({
    required this.spin,
    required this.spinning,
    required this.coverUrl,
    required this.size,
    required this.dx,
    required this.scale,
    required this.opacity,
    required this.onTap,
  });

  final AnimationController spin;
  final bool spinning;
  final String coverUrl;
  final double size;
  final double dx;
  final double scale;
  final double opacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: AnimatedBuilder(
              animation: spin,
              builder: (context, child) {
                final angle = spinning ? spin.value * 2 * pi : 0.0;
                return Transform.rotate(angle: angle, child: child);
              },
              child: _Vinyl(
                coverUrl: coverUrl,
                size: size,
                accent: Colors.transparent,
                kugo: null,
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自绘黑胶：沟槽 + 封面标签 + 中心孔。
class _Vinyl extends StatelessWidget {
  const _Vinyl({
    required this.coverUrl,
    required this.size,
    required this.accent,
    required this.kugo,
    required this.onTap,
  });

  final String coverUrl;
  final double size;
  final Color accent;
  final KugoTheme? kugo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = kugo ?? KugoTheme.of(context);
    final labelSize = size * 0.60;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFF1A1A1E), Color(0xFF05050A)],
          ),
          border: Border.all(color: theme.divider, width: 2),
          boxShadow: [
            BoxShadow(
              color: accent == Colors.transparent
                  ? Colors.black.withValues(alpha: 0.3)
                  : accent.withValues(alpha: 0.35),
              blurRadius: 34,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GroovePainter(),
                ),
              ),
            ),
            ClipOval(
              child: SizedBox(
                width: labelSize,
                height: labelSize,
                child: CoverBox(
                  seed: coverUrl,
                  size: labelSize,
                  radius: 999,
                ),
              ),
            ),
            Container(
              width: size * 0.06,
              height: size * 0.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.bg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroovePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = size.shortestSide * 0.30; r < size.shortestSide * 0.48; r += 4) {
      paint.color = Colors.white.withValues(alpha: 0.05);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 10 根跳动频谱条（EchoMusic `radio-bars`）。
class _Spectrum extends StatelessWidget {
  const _Spectrum({required this.bars, required this.active});

  final AnimationController bars;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bars,
      builder: (context, _) {
        return SizedBox(
          height: 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 10; i++)
                Container(
                  width: 3,
                  margin: const EdgeInsets.only(right: 3),
                  height: active
                      ? 6 + 18 * (0.5 + 0.5 * sin((bars.value * 2 * pi) + i))
                      : 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 0.75 : 0.30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 信息 chip：时长 / 音质。
class _InfoChips extends StatelessWidget {
  const _InfoChips({required this.kugo, this.track});

  final KugoTheme kugo;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    final items = <String>[
      if (t.durationMs > 0) t.durationLabel,
      if (t.quality.isNotEmpty) t.quality,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: KugoSpacing.sm,
      runSpacing: KugoSpacing.xs,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kugo.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(KugoRadius.chip),
              border: Border.all(color: kugo.divider),
            ),
            child: Text(item, style: kugo.caption),
          ),
      ],
    );
  }
}

/// 数据来源标注 —— 兜底模式必须让人看出来不是个性化推荐。
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.kugo,
    required this.fromServer,
    required this.gatewayError,
    required this.pool,
    required this.mode,
  });

  final KugoTheme kugo;
  final bool fromServer;
  final String gatewayError;
  final FmSongPool pool;
  final FmMode mode;

  @override
  Widget build(BuildContext context) {
    final semantic = pool.semantic.isEmpty ? '' : ' · ${pool.semantic}';
    final text = fromServer
        ? '来源：酷狗私人 FM · ${pool.label}$semantic'
        : (gatewayError.isEmpty
            ? '来源：关键词检索（${pool.reasonLabel}，非个性化）'
            : '来源：关键词检索 · ${pool.reasonLabel}');
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: kugo.caption.copyWith(
        color: kugo.textTertiary,
        fontSize: 11,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.kugo,
    required this.accent,
    required this.isPlaying,
    required this.onDislike,
    required this.onToggle,
    required this.onLike,
  });

  final KugoTheme kugo;
  final Color accent;
  final bool isPlaying;
  final VoidCallback onDislike;
  final VoidCallback onToggle;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleAction(
          icon: Icons.thumb_down_alt_rounded,
          label: '不喜欢',
          onTap: onDislike,
        ),
        _CircleAction(
          large: true,
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: onToggle,
          accent: accent,
        ),
        _CircleAction(
          icon: Icons.thumb_up_alt_rounded,
          label: '红心',
          onTap: onLike,
        ),
      ],
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onTap,
    this.label,
    this.large = false,
    this.accent,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool large;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final size = large ? 72.0 : 52.0;
    final tone = accent ?? kugo.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The label is part of the tap target — tapping the word should work
        // just as well as tapping the circle.
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: large
                      ? LinearGradient(
                          colors: [tone, tone.withValues(alpha: 0.7)],
                        )
                      : null,
                  color: large ? null : kugo.surface.withValues(alpha: 0.75),
                ),
                child: Icon(
                  icon,
                  size: large ? 36 : 24,
                  color: large ? kugo.onAccent : kugo.textPrimary,
                ),
              ),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(label!, style: kugo.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.size,
    required this.background,
    required this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final double size;
  final Color background;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
        ),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }
}

/// 胶囊分段开关：顶部歌池轴 / 电台卡模式轴共用。
class _CapsuleSwitch<T> extends StatelessWidget {
  const _CapsuleSwitch({
    required this.kugo,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.compact = false,
    this.onLightSurface = false,
  });

  final KugoTheme kugo;
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool compact;
  final bool onLightSurface;

  @override
  Widget build(BuildContext context) {
    final background = onLightSurface
        ? Colors.white.withValues(alpha: 0.16)
        : kugo.surface.withValues(alpha: 0.55);
    final foreground =
        onLightSurface ? kugo.onCoverMuted : kugo.textSecondary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: kugo.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 14,
                  vertical: compact ? 5 : 7,
                ),
                decoration: BoxDecoration(
                  color: value == selected
                      ? (onLightSurface
                          ? Colors.white.withValues(alpha: 0.22)
                          : kugo.primary.withValues(alpha: 0.30))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                child: Text(
                  labelOf(value),
                  style: kugo.caption.copyWith(
                    color: value == selected
                        ? (onLightSurface ? kugo.onAccent : kugo.textPrimary)
                        : foreground,
                    fontWeight:
                        value == selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
