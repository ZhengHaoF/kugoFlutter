import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../features/player/player_controller.dart';
import 'common.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// Shows the current playback queue in a bottom sheet or modal.
void showQueueSheet(BuildContext context, WidgetRef ref) {
  final kugo = KugoTheme.of(context);
  final player = ref.read(playerControllerProvider);
  final controller = ref.read(playerControllerProvider.notifier);

  showKugoBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final isDesktop = isDesktopView(sheetContext);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: isDesktop
              ? double.infinity
              : MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: Column(
          mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kugo.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '播放队列 · ${player.queue.length} 首',
              style: kugo.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (player.queue.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text('队列为空', style: kugo.caption),
              )
            else
              Flexible(
                child: SmoothListViewBuilder(
                  shrinkWrap: true,
                  itemCount: player.queue.length,
                  itemBuilder: (context, index) {
                    final track = player.queue[index];
                    final isCurrent = index == player.currentIndex;
                    return ListTile(
                      dense: true,
                      title: Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.body.copyWith(
                          color: isCurrent ? kugo.primary : kugo.textPrimary,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          Flexible(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: kugo.caption,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 队列可跨源混排，标明每首来自哪个音源。
                          SourceBadge(platform: track.platform),
                        ],
                      ),
                      trailing: isCurrent
                          ? Icon(
                              Icons.equalizer_rounded,
                              color: kugo.primary,
                              size: 18,
                            )
                          : null,
                      onTap: () {
                        controller.playAtIndex(index);
                        Navigator.of(sheetContext).pop();
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
