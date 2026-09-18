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

    final isLight = KugoThemeBinding.palette.isLight;

    return Material(
      color: KugoColors.surface,
      elevation: isLight ? 1.5 : 8,
      shadowColor: isLight
          ? Colors.black.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.45),
      child: InkWell(
        onTap: () => context.push('/player'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: KugoColors.divider),
                  bottom: BorderSide(color: KugoColors.divider),
                ),
              ),
              child: Padding(
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(track.id),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  KugoTypography.body.copyWith(fontSize: 14),
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
                    ),
                    IconButton(
                      onPressed: player.isLoading
                          ? null
                          : () => ref
                              .read(playerControllerProvider.notifier)
                              .togglePlay(),
                      icon: player.isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KugoColors.primary,
                              ),
                            )
                          : Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: KugoColors.primary,
                              size: 34,
                            ),
                    ),
                    IconButton(
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).next(),
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: KugoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
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
            ),
          ],
        ),
      ),
    );
  }
}
