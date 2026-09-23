import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/debug/network_log_dialog.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../shared/widgets/settings_pickers.dart';
import 'settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: DesktopContentConstraint(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.lg,
            KugoSpacing.lg,
            40,
          ),
        children: [
          _Section(
            title: '外观',
            children: [
              _ThemeModeTile(
                mode: AppThemeMode.dark,
                icon: Icons.dark_mode_rounded,
                title: '深色',
                subtitle: '概念版默认深色',
                selected: settings.themeMode == AppThemeMode.dark,
                onTap: () => controller.setThemeMode(AppThemeMode.dark),
              ),
              _ThemeModeTile(
                mode: AppThemeMode.light,
                icon: Icons.light_mode_rounded,
                title: '浅色',
                subtitle: '浅色完整适配',
                selected: settings.themeMode == AppThemeMode.light,
                onTap: () => controller.setThemeMode(AppThemeMode.light),
              ),
              _ThemeModeTile(
                mode: AppThemeMode.system,
                icon: Icons.brightness_auto_rounded,
                title: '跟随系统',
                subtitle: '随系统深浅色切换',
                selected: settings.themeMode == AppThemeMode.system,
                onTap: () => controller.setThemeMode(AppThemeMode.system),
              ),
            ],
          ),
          if (isDesktopPlatform)
            _Section(
              title: '窗口',
              children: [
                SwitchListTile(
                  title: Text('关闭到托盘', style: kugo.body),
                  subtitle: Text(
                    '点关闭按钮时隐藏到系统托盘，不退出应用',
                    style: kugo.caption,
                  ),
                  value: settings.closeToTray,
                  onChanged: controller.setCloseToTray,
                ),
              ],
            ),
          _Section(
            title: '播放',
            children: [
              ListTile(
                title: Text('默认音质', style: kugo.body),
                subtitle: Text(
                  '${settings.qualityLabel} · 新歌默认按此解析，播放中可切换',
                  style: kugo.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showQualityPicker(context, ref),
              ),
              ListTile(
                title: Text('定时停止', style: kugo.body),
                subtitle: Text(
                  settings.sleepMinutes == 0
                      ? '关闭'
                      : '${settings.sleepMinutes} 分钟',
                  style: kugo.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showSleepPicker(context, ref),
              ),
            ],
          ),
          _Section(
            title: '歌词与封面',
            children: [
              // 翻译 / 罗马音：播放页 VIP/HQ 旁「歌词显示」入口（lyric_display_sheet）。
              SwitchListTile(
                title: Text('锁屏/蓝牙显示歌词', style: kugo.body),
                subtitle: Text(
                  '系统媒体副标题显示「歌手 · 当前歌词」',
                  style: kugo.caption,
                ),
                value: settings.mediaLyricSubtitle,
                onChanged: controller.setMediaLyricSubtitle,
              ),
              SwitchListTile(
                title: Text('仅 Wi-Fi 加载封面', style: kugo.body),
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
                  style: kugo.body,
                ),
                subtitle: Text(
                  auth.isLogged ? '点击退出' : '游客模式，数据仅存本机',
                  style: kugo.caption,
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
                  color: kugo.textSecondary,
                ),
                title: Text('网络请求日志', style: kugo.body),
                subtitle: Text(
                  '请求/响应/错误 · 测试网络 · 实时探测 · 复制',
                  style: kugo.caption,
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
                  color: kugo.textSecondary,
                ),
                title: Text('清理图片缓存与播放历史', style: kugo.body),
                subtitle: Text(
                  '不影响登录与我喜欢；队列本地副本会一并清空',
                  style: kugo.caption,
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
                title: Text('kugo', style: kugo.body),
                subtitle: Text(
                  '0.1.0 · 学习/研究向第三方客户端\n不提供音频中转或账号托管',
                  style: kugo.caption,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, KugoSpacing.lg, 0, KugoSpacing.sm),
          child: Text(
            title,
            style: kugo.section.copyWith(fontSize: 15),
          ),
        ),
        // Material so the ListTiles inside keep their ink splashes.
        Material(
          color: kugo.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(KugoRadius.card),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Theme row shared with profile's 「主题外观」 sheet — same modes, same copy.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final AppThemeMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? kugo.primary : kugo.textSecondary,
      ),
      title: Text(title, style: kugo.body),
      subtitle: Text(subtitle, style: kugo.caption),
      trailing: selected
          ? Icon(Icons.check_rounded, color: kugo.primary)
          : null,
      onTap: onTap,
    );
  }
}
