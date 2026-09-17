import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/player/player_controller.dart';
import 'cover_box.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final track = player.current;
    if (track == null) return const SizedBox.shrink();

    final progress = player.durationMs == 0
        ? 0.0
        : (player.positionMs / player.durationMs).clamp(0.0, 1.0);

    return Material(
      color: KugoColors.surfaceElevated,
      elevation: 8,
      child: InkWell(
        onTap: () => context.push('/player'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Hero(
                    tag: 'player-cover-${track.id}',
                    child: CoverBox(
                      seed: track.coverUrl,
                      size: 44,
                      radius: 10,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KugoTypography.body.copyWith(fontSize: 14),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KugoTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref
                        .read(playerControllerProvider.notifier)
                        .togglePlay(),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(player.isPlaying),
                        color: KugoColors.textPrimary,
                        size: 34,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        ref.read(playerControllerProvider.notifier).next(),
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: KugoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CoverPalette.accentFromSeed(track.coverUrl),
                          CoverPalette.accentFromSeed(track.coverUrl)
                              .withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
