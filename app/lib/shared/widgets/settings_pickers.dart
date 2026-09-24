import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import 'common.dart';

/// Bottom-sheet pickers shared by the Settings page and the Profile shortcuts.
///
/// Kept in one place so「定时停止」/「音质设置」behave identically no matter
/// which entry the user came from — including the side effect of pushing the
/// sleep timer into the live player.

/// Pick the default audio quality. Persists to settings; takes effect on the
/// next resolve (playing tracks can still switch from the player page).
Future<void> showQualityPicker(BuildContext context, WidgetRef ref) async {
  final kugo = KugoTheme.of(context);
  final controller = ref.read(settingsControllerProvider.notifier);
  final current = ref.read(settingsControllerProvider).quality;
  final selected = await showKugoBottomSheet<AppQuality>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        for (final q in AppQuality.values)
          ListTile(
            title: Text(q.label, style: kugo.body),
            trailing: q == current
                ? Icon(Icons.check_rounded, color: kugo.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, q),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected != null) {
    await controller.setQuality(selected);
  }
}

/// Pick the default music source. It seeds the search page's source filter and
/// the 「我喜欢」page's source filter — both stay switchable per session.
Future<void> showDefaultSourcePicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final kugo = KugoTheme.of(context);
  final controller = ref.read(settingsControllerProvider.notifier);
  final current = ref.read(settingsControllerProvider).defaultSource;
  final platforms = musicSourceRegistry?.platforms.toList() ??
      const [MusicPlatform.kugou];
  final selected = await showKugoBottomSheet<MusicPlatform>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        for (final p in platforms)
          ListTile(
            title: Text(p.label, style: kugo.body),
            trailing: p == current
                ? Icon(Icons.check_rounded, color: kugo.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, p),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected != null) {
    await controller.setDefaultSource(selected);
  }
}

/// Pick the sleep timer. Persists the choice *and* arms the live player.
Future<void> showSleepPicker(BuildContext context, WidgetRef ref) async {
  final kugo = KugoTheme.of(context);
  final controller = ref.read(settingsControllerProvider.notifier);
  final selected = await showKugoBottomSheet<SleepTimerMode>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ListTile(
          title: Text('关闭', style: kugo.body),
          onTap: () => Navigator.pop(sheetContext, SleepTimerMode.off),
        ),
        ListTile(
          title: Text('15 分钟', style: kugo.body),
          onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m15),
        ),
        ListTile(
          title: Text('30 分钟', style: kugo.body),
          onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m30),
        ),
        ListTile(
          title: Text('60 分钟', style: kugo.body),
          onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m60),
        ),
        ListTile(
          title: Text('自定义 45 分钟', style: kugo.body),
          onTap: () => Navigator.pop(sheetContext, SleepTimerMode.custom),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected != null) {
    await controller.setSleep(selected);
    final minutes = ref.read(settingsControllerProvider).sleepMinutes;
    ref.read(playerControllerProvider.notifier).setSleepTimer(minutes);
  }
}

/// Pick what the desktop window close button does (每次询问 / 最小化到托盘 / 退出应用).
Future<void> showCloseBehaviorPicker(BuildContext context, WidgetRef ref) async {
  final kugo = KugoTheme.of(context);
  final controller = ref.read(settingsControllerProvider.notifier);
  final current = ref.read(settingsControllerProvider).closeBehavior;
  final selected = await showKugoBottomSheet<CloseBehavior>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        for (final behavior in CloseBehavior.values)
          ListTile(
            title: Text(behavior.label, style: kugo.body),
            subtitle: Text(behavior.closeHint, style: kugo.caption),
            trailing: behavior == current
                ? Icon(Icons.check_rounded, color: kugo.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, behavior),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected != null) {
    await controller.setCloseBehavior(selected);
  }
}

/// About sheet: version, project scope and the compliance disclaimer.
Future<void> showAboutSheet(BuildContext context) {
  return showKugoBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final kugo = KugoTheme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          12,
          KugoSpacing.lg,
          24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('关于', style: kugo.section)),
            const SizedBox(height: KugoSpacing.md),
            _AboutRow(label: '版本', value: '0.1.0'),
            _AboutRow(label: '形态', value: 'Android · 移动端优先'),
            _AboutRow(label: '定位', value: '酷狗概念版第三方客户端'),
            const SizedBox(height: KugoSpacing.md),
            Text(
              '个人学习 / 研究向项目。数据经公开接口直接获取，不提供音频中转或云端账号托管。'
              '音乐版权归原平台及版权方所有。',
              style: kugo.caption,
            ),
            const SizedBox(height: KugoSpacing.md),
            Text(
              '请遵守当地法律与目标平台服务条款；对外发布请勿使用「酷狗」注册商标作为应用名。',
              style: kugo.caption,
            ),
          ],
        ),
      );
    },
  );
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: kugo.caption),
          ),
          Expanded(
            child: Text(value, style: kugo.body),
          ),
        ],
      ),
    );
  }
}
