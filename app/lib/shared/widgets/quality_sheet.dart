import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/audio_quality.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../core/theme/kugo_theme.dart';
import 'common.dart';

/// 播放页音质选择底部弹层 — 对齐 EchoMusic QualityPopover：
/// 全部档位常显；已知不可用则禁用；标准恒可点。
Future<void> showQualitySheet(BuildContext context, WidgetRef ref) async {
  if (ref.read(playerControllerProvider).current == null) return;
  // Lazy probe available qualities while the sheet opens.
  ref.read(playerControllerProvider.notifier).ensureCurrentQualities();

  await showKugoBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QualitySheetBody(),
  );
}

class _QualitySheetBody extends ConsumerWidget {
  const _QualitySheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final track = player.current;
    final available = track?.availableQualities ?? const <AppQuality>{};
    final catalogComplete = track?.qualityCatalogComplete ?? false;
    final known = available.isNotEmpty;
    final resolved = player.resolvedQuality;
    final preferred = settings.quality;
    final active = resolved ?? preferred;
    final switching =
        player.isLoading && player.display == PlayerDisplayState.loading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.md,
        KugoSpacing.lg,
        KugoSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: KugoSpacing.md),
              decoration: BoxDecoration(
                color: kugo.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            '音质选择',
            textAlign: TextAlign.center,
            style: kugo.section.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            switching
                ? '正在切换音质…'
                : known
                    ? '灰色档位当前歌曲不可用'
                    : '未知档位将自动向下兼容',
            textAlign: TextAlign.center,
            style: kugo.caption,
          ),
          const SizedBox(height: KugoSpacing.sm),
          for (final q in AppQuality.values)
            _QualityRow(
              quality: q,
              active: !switching && active == q,
              pending: switching && preferred == q,
              disabled: !AudioQualityUtil.hasQuality(
                available,
                q,
                catalogComplete: catalogComplete,
              ),
              onTap: () async {
                if (!AudioQualityUtil.hasQuality(
                  available,
                  q,
                  catalogComplete: catalogComplete,
                )) {
                  return;
                }
                Navigator.of(context).maybePop();
                await controller.applyQuality(q);
              },
            ),
          const SizedBox(height: KugoSpacing.sm),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.quality,
    required this.active,
    required this.pending,
    required this.disabled,
    required this.onTap,
  });

  final AppQuality quality;
  final bool active;
  final bool pending;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final labelStyle = kugo.body.copyWith(
      color: disabled
          ? kugo.textTertiary
          : active
              ? kugo.primary
              : kugo.textPrimary,
    );

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        enabled: !disabled,
        onTap: disabled ? null : onTap,
        leading: QualityBadge(
          label: quality.badge,
          gradient: active && !disabled,
        ),
        title: Text(quality.label, style: labelStyle),
        trailing: pending
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kugo.primary,
                ),
              )
            : active
                ? Icon(
                    Icons.check_rounded,
                    color: kugo.primary,
                    size: 20,
                  )
                : disabled
                    ? Text('不可用', style: kugo.caption)
                    : null,
      ),
    );
  }
}
