import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/netease_login_controller.dart';
import '../../features/debug/network_log_dialog.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../shared/widgets/settings_pickers.dart';
import '../../shared/widgets/smooth_scroll.dart';
import 'settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final auth = ref.watch(authControllerProvider);
    final netease = ref.watch(neteaseLoginControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: DesktopContentConstraint(
        maxWidth: 800,
        // 桌面滚轮平滑：与发现页 / 我的 / 历史等页同源（SilkyScroll）。
        // 原来是裸 ListView，桌面滚轮会显得「一格一格跳」。
        child: SmoothListView(
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
                ListTile(
                  title: Text('关闭主窗口时', style: kugo.body),
                  subtitle: Text(
                    settings.closeBehavior.closeHint,
                    style: kugo.caption,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showCloseBehaviorPicker(context, ref),
                ),
                if (isWindowsPlatform)
                  SwitchListTile(
                    title: Text('任务栏播放进度', style: kugo.body),
                    subtitle: Text(
                      '在任务栏按钮上显示播放进度（播放绿 / 暂停黄）',
                      style: kugo.caption,
                    ),
                    value: settings.taskbarProgress,
                    onChanged: controller.setTaskbarProgress,
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
            title: '账号管理',
            children: [
              ListTile(
                leading: Icon(
                  Icons.hub_outlined,
                  color: kugo.textSecondary,
                ),
                title: Text('默认音源', style: kugo.body),
                subtitle: Text(
                  '${settings.defaultSourceLabel} · 搜索与「我喜欢」的初始音源',
                  style: kugo.caption,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDefaultSourcePicker(context, ref),
              ),
              // 整源开关：只列已注册的源；最后一个源不可关（至少保留一个）。
              // 停用只影响新内容的入口，已在播/已入队的曲目不受影响。
              for (final p in _enabledPlatformRows(settings))
                SwitchListTile(
                  secondary: Icon(Icons.power_settings_new, color: kugo.textSecondary),
                  title: Text('启用${p.$1.label}音源', style: kugo.body),
                  subtitle: Text(
                    p.$2 ? '关闭后搜索与功能页不再使用该源' : '最后一个音源，至少保留一个',
                    style: kugo.caption,
                  ),
                  value: settings.enabledSources.contains(p.$1),
                  onChanged: p.$2
                      ? (v) => controller.setEnabledSources(
                            v
                                ? {...settings.enabledSources, p.$1}
                                : {...settings.enabledSources}..remove(p.$1),
                          )
                      : null,
                ),
              // 酷狗 / 网易云各一行。两个源的登录态互不影响（可只登其一），
              // 但同一源只保留一个当前账号——再登即顶替，故按钮是「切换账号」。
              _AccountTile(
                icon: Icons.headset_rounded,
                platform: MusicPlatform.kugou.label,
                nickname: auth.isLogged ? (auth.user?.nickname ?? '') : '',
                guestHint: '游客模式，数据仅存本机',
                onLogin: () => context.push('/login'),
                onLogout:
                    auth.isLogged ? () => _logoutKugou(context, ref) : null,
              ),
              _AccountTile(
                icon: Icons.cloud_outlined,
                platform: MusicPlatform.netease.label,
                nickname: netease.isLogged ? netease.account!.nickname : '',
                guestHint: '扫码登录后可同步歌单与播放权限',
                // 已登录时带 relogin，进页直接出新码顶替旧账号。
                onLogin: () => context.push(
                  netease.isLogged
                      ? '/netease-login?relogin=1'
                      : '/netease-login',
                ),
                onLogout: netease.isLogged
                    ? () => _logoutNetease(context, ref)
                    : null,
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

  /// 整源开关的行数据：`(平台, 是否可关闭)`。
  ///
  /// 只列 registry 里已注册的源（没注册的源开关无意义）；enabledSources
  /// 里只剩它自己时禁止关闭——空集合会让 App 没有任何可用音源。
  List<(MusicPlatform, bool)> _enabledPlatformRows(AppSettings settings) {
    final registered = musicSourceRegistry?.platforms.toList() ??
        const [MusicPlatform.kugou];
    return [
      for (final p in registered)
        (p, settings.enabledSources.length > 1 || !settings.enabledSources.contains(p)),
    ];
  }

  /// 退出酷狗账号。会掉云端歌单/「我喜欢」与付费播放权限，先二次确认。
  Future<void> _logoutKugou(BuildContext context, WidgetRef ref) async {
    final name = ref.read(authControllerProvider).user?.nickname ?? '';
    if (!await _confirmLogout(context, MusicPlatform.kugou.label, name)) return;
    await ref.read(authControllerProvider.notifier).logout();
  }

  /// 退出网易云账号：清内存会话 + 本地落盘（[NeteaseAuthStore]）。
  Future<void> _logoutNetease(BuildContext context, WidgetRef ref) async {
    final name =
        ref.read(neteaseLoginControllerProvider).account?.nickname ?? '';
    if (!await _confirmLogout(context, MusicPlatform.netease.label, name)) {
      return;
    }
    await ref.read(neteaseLoginControllerProvider.notifier).logout();
  }
}

/// 退出登录前的二次确认：会掉云端歌单/「我喜欢」与付费播放权限，误点代价高。
Future<bool> _confirmLogout(
  BuildContext context,
  String platform,
  String nickname,
) async {
  final who = nickname.isEmpty ? '' : '「$nickname」';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('退出$platform账号？'),
      content: Text('退出后$who云端的歌单、「我喜欢」与付费播放权限将不可用，本机数据不受影响。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 「账号管理」里的一行：平台名 + 当前状态 + 行内显式按钮。
///
/// 旧版酷狗是「点整行即退出」的隐式交互，容易误触（退出会掉云端数据），
/// 故统一改为显式按钮，并与网易云保持同构。
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.platform,
    required this.nickname,
    required this.guestHint,
    required this.onLogin,
    this.onLogout,
  });

  final IconData icon;
  final String platform;

  /// 非空即已登录，直接显示昵称。
  final String nickname;

  /// 未登录时的状态说明。
  final String guestHint;

  /// 「去登录」；已登录时同一按钮变成「切换账号」。
  final VoidCallback onLogin;

  /// 「退出登录」；未登录为 null（不显示该按钮）。
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final logged = nickname.isNotEmpty;
    final logout = onLogout;
    return ListTile(
      leading: Icon(icon, color: kugo.textSecondary),
      title: Text(platform, style: kugo.body),
      subtitle: Text(
        logged ? '已登录：$nickname' : guestHint,
        style: kugo.caption,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onLogin,
            style: _tileActionStyle,
            child: Text(logged ? '切换账号' : '去登录'),
          ),
          if (logout != null)
            TextButton(
              onPressed: logout,
              style: _tileActionStyle,
              child: const Text('退出登录'),
            ),
        ],
      ),
    );
  }
}

/// 两个按钮要挤进一个 ListTile，收紧内边距与点击热区免得撑破标题。
final ButtonStyle _tileActionStyle = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 32),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
