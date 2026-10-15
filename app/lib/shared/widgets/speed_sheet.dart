import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/overtone_theme.dart';
import '../../core/theme/overtone_tokens.dart';
import '../../features/player/player_controller.dart';
import 'common.dart';

/// 播放页音质旁的「倍速」入口。
///
/// 倍速非 1.0 时图标高亮并跟当前值角标（同 MV 播放器 `_SpeedButton` 的
/// 语言）；点开 [showSpeedSheet]。
class SpeedChip extends ConsumerWidget {
  const SpeedChip({super.key});

  /// 档位显示：1.0 是「正常」，其余按 `0.5x` / `1.25x` 原样（去尾零）。
  static String label(double speed) =>
      speed == 1.0 ? '正常' : '${_trim(speed)}x';

  static String _trim(double speed) {
    final rounded = (speed * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
    final speed = ref.watch(playerControllerProvider).speed;
    final active = speed != 1.0;

    return Tooltip(
      message: active ? '倍速 · ${label(speed)}' : '倍速',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showSpeedSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_outlined,
                size: 16,
                color: active ? theme.primary : theme.textSecondary,
              ),
              if (active) ...[
                const SizedBox(width: 2),
                Text(
                  label(speed),
                  style: theme.caption.copyWith(
                    fontSize: 10,
                    color: theme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 倍速选择底部弹层 — 与音质 / 歌词显示弹层并列，档位表
/// [kSpeedPresets] 与 MV 播放器一致。
Future<void> showSpeedSheet(BuildContext context, WidgetRef ref) {
  return showOvertoneBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SpeedSheetBody(),
  );
}

class _SpeedSheetBody extends ConsumerWidget {
  const _SpeedSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
    final speed = ref.watch(playerControllerProvider).speed;
    final controller = ref.read(playerControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OvertoneSpacing.lg,
        OvertoneSpacing.md,
        OvertoneSpacing.lg,
        OvertoneSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: OvertoneSpacing.md),
              decoration: BoxDecoration(
                color: theme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            '播放倍速',
            textAlign: TextAlign.center,
            style: theme.section.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '倍速不保留音调；进度、歌词与剩余时间随倍速一致变化',
            textAlign: TextAlign.center,
            style: theme.caption,
          ),
          const SizedBox(height: OvertoneSpacing.sm),
          for (final preset in kSpeedPresets)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                SpeedChip.label(preset),
                style: theme.body.copyWith(
                  color: speed == preset ? theme.primary : theme.textPrimary,
                ),
              ),
              trailing: speed == preset
                  ? Icon(Icons.check_rounded, color: theme.primary, size: 20)
                  : null,
              onTap: () {
                Navigator.of(context).maybePop();
                controller.setSpeed(preset);
              },
            ),
          const SizedBox(height: OvertoneSpacing.sm),
        ],
      ),
    );
  }
}
