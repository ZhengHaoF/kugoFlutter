import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/likes/likes_controller.dart';
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
        const Text('我的', style: KugoTypography.greeting),
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
                          Text(displayName, style: KugoTypography.title),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: auth.isLogged
                                  ? KugoColors.accentGradient
                                  : null,
                              color: auth.isLogged
                                  ? null
                                  : KugoColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              displaySub,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: KugoColors.textSecondary,
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
              const _LinkTile(icon: Icons.timer_outlined, title: '定时停止'),
              const _LinkTile(icon: Icons.music_note_rounded, title: '音质设置'),
              const _LinkTile(icon: Icons.palette_outlined, title: '主题外观'),
              const _LinkTile(icon: Icons.info_outline_rounded, title: '关于'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: KugoTypography.caption),
        const SizedBox(height: 4),
        Text(value, style: KugoTypography.section.copyWith(fontSize: 20)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: KugoColors.divider);
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
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: KugoTypography.body),
      subtitle: Text(subtitle, style: KugoTypography.caption),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: KugoColors.textTertiary,
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
    return ListTile(
      leading: Icon(icon, color: KugoColors.textSecondary),
      title: Text(title, style: KugoTypography.body),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: KugoColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
