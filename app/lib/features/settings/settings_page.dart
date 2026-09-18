import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/debug/network_log_dialog.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/common.dart';
import 'settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          KugoSpacing.lg,
          KugoSpacing.lg,
          40,
        ),
        children: [
          _Section(
            title: '播放',
            children: [
              ListTile(
                title: Text('默认音质', style: KugoTypography.body),
                subtitle: Text(settings.qualityLabel, style: KugoTypography.caption),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickQuality(context, ref),
              ),
              ListTile(
                title: Text('定时停止', style: KugoTypography.body),
                subtitle: Text(
                  settings.sleepMinutes == 0
                      ? '关闭'
                      : '${settings.sleepMinutes} 分钟',
                  style: KugoTypography.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickSleep(context, ref),
              ),
            ],
          ),
          _Section(
            title: '歌词与封面',
            children: [
              SwitchListTile(
                title: Text('显示翻译', style: KugoTypography.body),
                value: settings.lyricTranslation,
                onChanged: controller.setLyricTranslation,
              ),
              SwitchListTile(
                title: Text('仅 Wi-Fi 加载封面', style: KugoTypography.body),
                value: settings.wifiCoverOnly,
                onChanged: controller.setWifiCoverOnly,
              ),
            ],
          ),
          _Section(
            title: '账号',
            children: [
              ListTile(
                title: Text(
                  auth.isLogged ? '已登录：${auth.user?.nickname}' : '未登录',
                  style: KugoTypography.body,
                ),
                subtitle: Text(
                  auth.isLogged ? '点击退出' : '游客模式，数据仅存本机',
                  style: KugoTypography.caption,
                ),
                onTap: () async {
                  if (auth.isLogged) {
                    await ref.read(authControllerProvider.notifier).logout();
                  } else if (context.mounted) {
                    context.push('/login');
                  }
                },
              ),
            ],
          ),
          _Section(
            title: '调试',
            children: [
              ListTile(
                leading: Icon(
                  Icons.bug_report_outlined,
                  color: KugoColors.textSecondary,
                ),
                title: Text('网络请求日志', style: KugoTypography.body),
                subtitle: Text(
                  '请求/响应/错误 · 测试网络 · 实时探测 · 复制',
                  style: KugoTypography.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showNetworkLogDialog(context),
              ),
            ],
          ),
          _Section(
            title: '缓存',
            children: [
              ListTile(
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: KugoColors.textSecondary,
                ),
                title: Text('清理图片缓存与播放历史', style: KugoTypography.body),
                subtitle: Text(
                  '不影响登录与我喜欢；队列本地副本会一并清空',
                  style: KugoTypography.caption,
                ),
                onTap: () async {
                  final msg = await controller.clearImageAndHistoryCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  }
                },
              ),
            ],
          ),
          _Section(
            title: '关于',
            children: [
              ListTile(
                title: Text('kugo', style: KugoTypography.body),
                subtitle: Text(
                  '0.1.0 · 学习/研究向第三方客户端\n不提供音频中转或账号托管',
                  style: KugoTypography.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickQuality(BuildContext context, WidgetRef ref) async {
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
              title: Text(
                switch (q) {
                  AppQuality.standard => '标准',
                  AppQuality.hq => '高品',
                  AppQuality.sq => '无损',
                  AppQuality.hiRes => 'Hi-Res',
                },
                style: KugoTypography.body,
              ),
              trailing: q == current
                  ? Icon(Icons.check_rounded, color: KugoColors.primary)
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

  Future<void> _pickSleep(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(settingsControllerProvider.notifier);
    final selected = await showKugoBottomSheet<SleepTimerMode>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            title: Text('关闭', style: KugoTypography.body),
            onTap: () => Navigator.pop(sheetContext, SleepTimerMode.off),
          ),
          ListTile(
            title: Text('15 分钟', style: KugoTypography.body),
            onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m15),
          ),
          ListTile(
            title: Text('30 分钟', style: KugoTypography.body),
            onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m30),
          ),
          ListTile(
            title: Text('60 分钟', style: KugoTypography.body),
            onTap: () => Navigator.pop(sheetContext, SleepTimerMode.m60),
          ),
          ListTile(
            title: Text('自定义 45 分钟', style: KugoTypography.body),
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
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, KugoSpacing.lg, 0, KugoSpacing.sm),
          child: Text(
            title,
            style: KugoTypography.section.copyWith(fontSize: 15),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: KugoColors.surface,
            borderRadius: BorderRadius.circular(KugoRadius.card),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
