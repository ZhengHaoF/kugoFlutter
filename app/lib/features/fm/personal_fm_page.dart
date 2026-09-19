import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/cover_box.dart';
import '../../core/theme/kugo_theme.dart';

/// FM "song pools".
///
/// Each pool is a **keyword bundle**, not a single keyword: one search term
/// returns a narrow slice (the three old single terms returned nearly the same
/// top-20 every time, which made the switch feel broken). Terms inside a bundle
/// are always queried together, so the pool is broad but still themed.
enum FmPool { taste, style, explore }

extension FmPoolLabel on FmPool {
  String get label => switch (this) {
        FmPool.taste => '口味',
        FmPool.style => '风格',
        FmPool.explore => '探索',
      };

  /// Keywords merged into this pool's candidate set.
  List<String> get keywords => switch (this) {
        FmPool.taste => const ['热门', '华语流行', '经典'],
        FmPool.style => const ['民谣', '电子', '轻音乐'],
        FmPool.explore => const ['独立', '冷门', '爵士'],
      };

  /// Honest one-liner for the "why this song" line — we do not have a real
  /// recommendation engine, so never claim personalised taste matching.
  String get reasonLabel => switch (this) {
        FmPool.taste => '来自「热门 / 华语流行」',
        FmPool.style => '来自「民谣 / 电子」',
        FmPool.explore => '来自「独立 / 爵士」',
      };
}

/// How many tracks to keep in hand before asking for more.
const _kFmTargetPool = 30;

/// Below this many *unplayed* tracks left we top the pool up in the background.
const _kFmRefillThreshold = 6;

/// 私人 FM 页。
///
/// 数据源说明（重要，别被名字骗了）：这里**不是**酷狗的个性化推荐接口，
/// 而是用搜索结果拼出的动态歌池。签名网关 `/personal/fm` 在本网络下
/// 试不通（详见 `docs/personal-fm-vs-echomusic.md`），所以页面用的是
/// 「多关键词检索 + 本地不喜欢过滤 + 永不重复的续流」这套替代语义。
/// 等真接口打通后再把 `_fetch` 换掉即可，页面其余部分不用动。
class PersonalFmPage extends ConsumerStatefulWidget {
  const PersonalFmPage({super.key, this.repository});

  /// Test seam: override the search source. Production uses the singleton.
  final SearchRepository? repository;

  @override
  ConsumerState<PersonalFmPage> createState() => _PersonalFmPageState();
}

class _PersonalFmPageState extends ConsumerState<PersonalFmPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  SearchRepository get _repo => widget.repository ?? searchRepository;

  FmPool _pool = FmPool.taste;
  List<Track> _tracks = const [];
  bool _loading = true;
  bool _appending = false;
  bool _exhausted = false;
  String _error = '';

  /// Ids the user thumbed-down. Local-only by design (there is no server
  /// feedback endpoint available), but it is honoured across refills and
  /// across pool switches so "不喜欢" actually means something.
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
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  /// Map the player's current track back onto [_tracks].
  ///
  /// The player owns the queue and its own cursor: the user can hit "next" on
  /// the full player page or the mini bar, and the FM page must follow that
  /// rather than keep its own stale position. Returns `null` when the player is
  /// playing something unrelated to this FM pool.
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

  Future<void> _load({bool keepDisliked = true}) async {
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = '';
      _exhausted = false;
      _tracks = const [];
      _anchorIndex = 0;
      _usedQueries.clear();
      if (!keepDisliked) _disliked.clear();
    });

    final list = await _fetch(token);
    if (!mounted || token != _requestToken) return;
    if (list.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'FM 歌池加载失败，请检查网络';
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
    final remaining =
        _pool.keywords.where((k) => !_usedQueries.contains(k)).toList();
    final pool = remaining.isEmpty ? _pool.keywords.toList() : remaining;
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
    return out;
  }

  /// Append more tracks so a finished pool keeps flowing instead of looping
  /// back to song #1.
  Future<void> _append() async {
    if (_appending || _exhausted) return;
    final token = _requestToken;
    setState(() => _appending = true);

    final more = await _fetch(token);
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

  /// Hand the pool to the player.
  ///
  /// [i] indexes [_tracks]; the disliked ones are filtered out of the queue that
  /// actually reaches the player, so the player's own auto-advance can never
  /// land on a track the user rejected. Without this the queue would still
  /// contain them and completion would walk straight into one.
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
  ///
  /// Returns false when the pool ran dry — the caller then asks [_append] for
  /// more rather than wrapping around.
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
    // Top up in the background once we are close to the end, so the stream
    // never visibly stalls at the boundary.
    if (_tracks.length - from <= _kFmRefillThreshold) {
      unawaited(_append());
    }
    if (advanced) return;
    // Pool drained (or everything left is disliked): pull more, then continue.
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
    }
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final track = _displayTrack();
    final index = _resolveIndex() ?? _anchorIndex;
    final accent =
        CoverPalette.accentFromSeed(track?.coverUrl ?? 'fm', kugo.palette);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(
            track?.coverUrl ?? 'fm',
            kugo.palette,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    IconButton(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SegmentedButton<FmPool>(
                  segments: [
                    for (final p in FmPool.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {_pool},
                  onSelectionChanged: (s) {
                    setState(() => _pool = s.first);
                    _load();
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: accent.withValues(alpha: 0.45),
                    selectedForegroundColor: Colors.white,
                    foregroundColor: kugo.textSecondary,
                    backgroundColor: kugo.surface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_tracks.isEmpty)
                Expanded(
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
                Expanded(
                  child: Column(
                    children: [
                      const Spacer(),
                      // Vinyl
                      AnimatedBuilder(
                        animation: _spin,
                        builder: (context, child) {
                          final playing = player.isPlaying;
                          final angle = playing ? _spin.value * 2 * pi : 0.0;
                          return Transform.rotate(
                            angle: angle,
                            child: child,
                          );
                        },
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.85),
                            border: Border.all(
                              color: kugo.divider,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.35),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: ClipOval(
                              child: SizedBox(
                                width: 140,
                                height: 140,
                                child: CoverBox(
                                  seed: track?.coverUrl ?? 'fm',
                                  size: 140,
                                  radius: 999,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: KugoSpacing.xl),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          track?.name ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kugo.playerTitle,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track?.artist ?? '',
                        style: kugo.caption,
                      ),
                      const SizedBox(height: 6),
                      // Honest provenance line — we are a keyword pool, not a
                      // personalised engine, so say where the song came from.
                      Text(
                        _pool.reasonLabel,
                        style: kugo.caption.copyWith(
                          color: kugo.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _CircleAction(
                            icon: Icons.thumb_down_alt_rounded,
                            label: '不喜欢',
                            onTap: _dislike,
                          ),
                          _CircleAction(
                            large: true,
                            icon: player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .togglePlay(),
                            accent: accent,
                          ),
                          _CircleAction(
                            icon: Icons.thumb_up_alt_rounded,
                            label: '红心',
                            onTap: () async {
                              final t = _displayTrack();
                              if (t != null) {
                                await ref
                                    .read(likesProvider.notifier)
                                    .like(t);
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
                        ],
                      ),
                      const SizedBox(height: KugoSpacing.lg),
                      TextButton(
                        onPressed: () => context.push('/player'),
                        child: Text(
                          _appending
                              ? '正在续接歌池…'
                              : '打开播放页 · ${index + 1}/${_tracks.length}',
                          style: kugo.caption,
                        ),
                      ),
                      const SizedBox(height: KugoSpacing.lg),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
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
                  // Large button sits on the accent gradient; the small ones sit
                  // on the page surface, which is near-white in light mode.
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
