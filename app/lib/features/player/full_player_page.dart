import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';

class FullPlayerPage extends ConsumerWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;
    if (track == null) {
      return Scaffold(
        backgroundColor: KugoColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    '暂无播放内容\n去搜索或歌单里点一首歌',
                    textAlign: TextAlign.center,
                    style: KugoTypography.caption,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final duration = player.durationMs == 0 ? 1 : player.durationMs;
    final progress = (player.positionMs / duration).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: CoverPalette.playerBackground(track.coverUrl),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 32,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        '正在播放',
                        textAlign: TextAlign.center,
                        style: KugoTypography.section,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showQueueSheet(context, ref),
                      icon: const Icon(Icons.queue_music_rounded),
                    ),
                  ],
                ),
              ),
              // Cover — flexible so short screens never overflow
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(KugoRadius.card + 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 28,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: 'player-cover-${track.id}',
                          child: CoverBox(
                            seed: track.coverUrl,
                            size: double.infinity,
                            radius: KugoRadius.card + 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Meta + progress + controls + lyrics (fixed height, no extra Spacer)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KugoSpacing.xl,
                  KugoSpacing.md,
                  KugoSpacing.xl,
                  KugoSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KugoTypography.playerTitle,
                          ),
                        ),
                        QualityBadge(
                          label: track.isVip ? 'VIP' : track.quality,
                          gradient: track.isVip,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.artist} · ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KugoTypography.caption,
                    ),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (v) =>
                            controller.seekTo((v * duration).round()),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _format(player.positionMs),
                            style: KugoTypography.caption,
                          ),
                          Text(
                            '-${_format(duration - player.positionMs)}',
                            style: KugoTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 72,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: controller.cycleMode,
                            tooltip: _modeLabel(player.mode),
                            icon: Icon(
                              switch (player.mode) {
                                PlayerLoopMode.order =>
                                  Icons.trending_flat_rounded,
                                PlayerLoopMode.listLoop =>
                                  Icons.repeat_rounded,
                                PlayerLoopMode.shuffle =>
                                  Icons.shuffle_rounded,
                                PlayerLoopMode.single =>
                                  Icons.repeat_one_rounded,
                              },
                              color: KugoColors.textSecondary,
                              size: 24,
                            ),
                          ),
                          IconButton(
                            onPressed: controller.previous,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 36,
                              color: KugoColors.textPrimary,
                            ),
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              gradient: KugoColors.accentGradient,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: controller.togglePlay,
                              icon: Icon(
                                player.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: controller.next,
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              size: 36,
                              color: KugoColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              ref.read(likesProvider.notifier).toggle(track);
                            },
                            icon: Icon(
                              ref.watch(likesProvider).any((t) => t.id == track.id)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: ref.watch(likesProvider).any(
                                    (t) => t.id == track.id,
                                  )
                                  ? const Color(0xFFE87A90)
                                  : KugoColors.textSecondary,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 72,
                      child: _LyricPreview(
                        lines: player.lyrics,
                        positionMs: player.positionMs,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _format(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _modeLabel(PlayerLoopMode mode) => switch (mode) {
        PlayerLoopMode.order => '顺序播放',
        PlayerLoopMode.listLoop => '列表循环',
        PlayerLoopMode.shuffle => '随机播放',
        PlayerLoopMode.single => '单曲循环',
      };

  void _showQueueSheet(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KugoColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KugoColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '播放队列 · ${player.queue.length} 首',
                style: KugoTypography.section.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: player.queue.length,
                  itemBuilder: (context, index) {
                    final track = player.queue[index];
                    final isCurrent = index == player.currentIndex;
                    return ListTile(
                      title: Text(
                        track.name,
                        style: KugoTypography.body.copyWith(
                          color: isCurrent
                              ? KugoColors.primary
                              : KugoColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(track.artist, style: KugoTypography.caption),
                      trailing: isCurrent
                          ? const Icon(
                              Icons.equalizer_rounded,
                              color: KugoColors.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () {
                        controller.playQueue(player.queue, startIndex: index);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LyricPreview extends StatelessWidget {
  const _LyricPreview({required this.lines, required this.positionMs});

  final List<LyricLine> lines;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text('暂无歌词', style: KugoTypography.caption),
      );
    }
    var active = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timeMs <= positionMs) active = i;
    }
    final start = (active - 1).clamp(0, lines.length - 1);
    final visible = lines.skip(start).take(3).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < visible.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              visible[i].text,
              textAlign: TextAlign.center,
              style: KugoTypography.body.copyWith(
                color: (start + i) == active
                    ? KugoColors.textPrimary
                    : KugoColors.textTertiary,
                fontWeight: (start + i) == active
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
