import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).refreshProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    ref.watch(settingsControllerProvider.select((s) => s.themeMode));
    final auth = ref.watch(authControllerProvider);
    final likesCount = ref.watch(likesProvider).length;
    final user = auth.user;
    final displayName = auth.isLogged
        ? (user?.nickname ?? '用户')
        : (auth.restored ? '游客' : '…');
    final displaySub = auth.isLogged
        ? (user!.isVip ? '概念会员' : '已登录')
        : '未登录 · 公开内容可用';
    final avatarUrl = user?.avatarUrl ?? '';

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.xl,
        KugoSpacing.lg,
        140,
      ),
      children: [
        Text('我的', style: kugo.greeting),
        const SizedBox(height: KugoSpacing.lg),
        GlassSurface(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(KugoRadius.tile),
                onTap: () {
                  if (!auth.isLogged) {
                    context.push('/login');
                  }
                },
                child: Row(
                  children: [
                    CoverBox(
                      seed: avatarUrl.isNotEmpty ? avatarUrl : 'avatar-guest',
                      size: 64,
                      radius: 999,
                      child: avatarUrl.isNotEmpty
                          ? null
                          : const Icon(
                              Icons.person_rounded,
                              color: Colors.white70,
                              size: 32,
                            ),
                    ),
                    const SizedBox(width: KugoSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName, style: kugo.title),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: auth.isLogged
                                  ? kugo.accentGradient
                                  : null,
                              color: auth.isLogged
                                  ? null
                                  : kugo.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              displaySub,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                // White only reads on the accent gradient; the
                                // guest chip uses the page surface.
                                color: auth.isLogged
                                    ? kugo.onAccent
                                    : kugo.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: kugo.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KugoSpacing.lg),
              Row(
                children: [
                  Expanded(child: _Stat(label: '我喜欢', value: '$likesCount')),
                  const _Divider(),
                  Expanded(child: _Stat(label: '最近播放', value: '56')),
                  const _Divider(),
                  Expanded(child: _Stat(label: '歌单', value: '12')),
                ],
              ),
              if (auth.isLogged) ...[
                const SizedBox(height: KugoSpacing.md),
                TextButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('退出登录'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),
        GlassSurface(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _EntryTile(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFE87A90),
                title: '我喜欢',
                subtitle: '喜欢的歌曲',
                onTap: () => context.push('/likes'),
              ),
              _EntryTile(
                icon: Icons.radio_rounded,
                color: const Color(0xFF5B7CFF),
                title: '私人 FM',
                subtitle: '黑胶电台',
                onTap: () => context.push('/fm'),
              ),
              _EntryTile(
                icon: Icons.history_rounded,
                color: const Color(0xFFE8B86D),
                title: '播放历史',
                subtitle: '播放过的歌曲',
                onTap: () => context.push('/history'),
              ),
              _EntryTile(
                icon: Icons.download_rounded,
                color: const Color(0xFF8B7CF6),
                title: '本地音乐',
                subtitle: '本地音乐文件',
                onTap: () {},
              ),
              _EntryTile(
                icon: Icons.cloud_download_rounded,
                color: const Color(0xFF5BB8A8),
                title: '下载管理',
                subtitle: '下载管理任务',
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: KugoSpacing.lg),
        GlassSurface(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _LinkTile(
                icon: Icons.settings_outlined,
                title: '设置',
                onTap: () => context.push('/settings'),
              ),
              // Theme-colored tiles must not be const — Flutter skips rebuild
              // when the const instance is identical after a theme switch.
              _LinkTile(icon: Icons.timer_outlined, title: '定时停止'),
              _LinkTile(icon: Icons.music_note_rounded, title: '音质设置'),
              _LinkTile(
                icon: Icons.palette_outlined,
                title: '主题外观',
                onTap: () => _showThemeSheet(context),
              ),
              _LinkTile(icon: Icons.info_outline_rounded, title: '关于'),
            ],
          ),
        ),
      ],
    );
  }

  void _showThemeSheet(BuildContext context) {
    showKugoBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final kugo = KugoTheme.of(context);
            final current = ref.watch(settingsControllerProvider).themeMode;
            Widget tile(
              AppThemeMode value,
              IconData icon,
              String title,
              String sub,
            ) {
              final selected = current == value;
              return ListTile(
                leading: Icon(
                  icon,
                  color: selected ? kugo.primary : kugo.textSecondary,
                ),
                title: Text(title, style: kugo.body),
                subtitle: Text(sub, style: kugo.caption),
                trailing: selected
                    ? Icon(Icons.check_rounded, color: kugo.primary)
                    : null,
                onTap: () async {
                  await ref
                      .read(settingsControllerProvider.notifier)
                      .setThemeMode(value);
                  if (sheetContext.mounted) {
                    setSheetState(() {});
                    Navigator.of(sheetContext).pop();
                  }
                },
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Text('主题外观', style: kugo.section),
                const SizedBox(height: 8),
                tile(
                  AppThemeMode.dark,
                  Icons.dark_mode_rounded,
                  '深色',
                  '概念版默认深色',
                ),
                tile(
                  AppThemeMode.light,
                  Icons.light_mode_rounded,
                  '浅色',
                  '浅色完整适配',
                ),
                tile(
                  AppThemeMode.system,
                  Icons.brightness_auto_rounded,
                  '跟随系统',
                  '随系统深浅色切换',
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Column(
      children: [
        Text(label, style: kugo.caption),
        const SizedBox(height: 4),
        Text(value, style: kugo.section.copyWith(fontSize: 20)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: KugoTheme.of(context).divider);
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kugo = KugoTheme.of(context);
    final body = kugo.body.copyWith(color: scheme.onSurface);
    final caption = kugo.caption.copyWith(color: scheme.onSurfaceVariant);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: body),
      subtitle: Text(subtitle, style: caption),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Prefer Material onSurface so titles stay readable even if static
    // Kugo tokens are briefly stale during a theme switch.
    final scheme = Theme.of(context).colorScheme;
    final kugo = KugoTheme.of(context);
    final body = kugo.body.copyWith(color: scheme.onSurface);
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(title, style: body),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
