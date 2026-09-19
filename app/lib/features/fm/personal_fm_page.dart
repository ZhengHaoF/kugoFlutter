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

enum FmPool { taste, style, explore }

extension FmPoolLabel on FmPool {
  String get label => switch (this) {
        FmPool.taste => '口味',
        FmPool.style => '风格',
        FmPool.explore => '探索',
      };

  String get keyword => switch (this) {
        FmPool.taste => '热门',
        FmPool.style => '民谣 电子',
        FmPool.explore => '独立 冷门',
      };
}

/// 私人 FM：用搜索结果作动态歌池（真源），黑胶式 UI。
class PersonalFmPage extends ConsumerStatefulWidget {
  const PersonalFmPage({super.key});

  @override
  ConsumerState<PersonalFmPage> createState() => _PersonalFmPageState();
}

class _PersonalFmPageState extends ConsumerState<PersonalFmPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  FmPool _pool = FmPool.taste;
  List<Track> _tracks = const [];
  int _index = 0;
  bool _loading = true;
  String _error = '';
  final _disliked = <String>{};

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
      _index = 0;
    });
    List<Track> list = const [];
    try {
      list = await searchRepository.searchSongs(_pool.keyword, pageSize: 20);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _tracks = list;
      _loading = false;
      if (list.isEmpty) _error = 'FM 歌池加载失败，请检查网络';
    });
    if (list.isNotEmpty) {
      _playAt(0);
    }
  }

  void _playAt(int i) {
    if (_tracks.isEmpty) return;
    final idx = i.clamp(0, _tracks.length - 1);
    _index = idx;
    ref.read(playerControllerProvider.notifier).playQueue(
          _tracks,
          startIndex: idx,
        );
  }

  void _next() {
    if (_tracks.isEmpty) return;
    var i = _index + 1;
    if (i >= _tracks.length) i = 0;
    // skip disliked
    var guard = 0;
    while (guard++ < _tracks.length &&
        _disliked.contains(_tracks[i].id)) {
      i = (i + 1) % _tracks.length;
    }
    _playAt(i);
  }

  void _dislike() {
    final track = _tracks.isEmpty ? null : _tracks[_index];
    if (track != null) {
      _disliked.add(track.id);
    }
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final track =
        _tracks.isEmpty ? null : _tracks[_index.clamp(0, _tracks.length - 1)];
    final accent = CoverPalette.accentFromSeed(track?.coverUrl ?? 'fm', kugo.palette);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient:
              CoverPalette.playerBackground(track?.coverUrl ?? 'fm', kugo.palette),
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
                      icon: Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '私人 FM',
                        textAlign: TextAlign.center,
                        style: kugo.section,
                      ),
                    ),
                    IconButton(
                      onPressed: _load,
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
                              final t = track;
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
                          '打开播放页 · ${_index + 1}/${_tracks.length}',
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
        InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
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
              // Large button sits on the accent gradient; the small ones sit on
              // the page surface, which is near-white in light mode.
              color: large ? kugo.onAccent : kugo.textPrimary,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(label!, style: kugo.caption),
        ],
      ],
    );
  }
}
