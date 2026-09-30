import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../features/player/player_controller.dart';
import 'common.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// 队列长度超过这个值就不再 shrinkWrap：shrinkWrap 的列表每次布局都要把
/// 全部子项量一遍尺寸（O(n)），几百首时打开/滚动队列会明显掉帧。
const int _kShrinkWrapQueueLimit = 30;

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
                  // shrinkWrap 会让列表放弃视口懒加载模型，每次布局都要把
                  // 整队列量一遍尺寸。短队列保持原样（底部弹窗按内容收缩），
                  // 长队列改用懒加载填满可用高度。
                  shrinkWrap: player.queue.length <= _kShrinkWrapQueueLimit,
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
