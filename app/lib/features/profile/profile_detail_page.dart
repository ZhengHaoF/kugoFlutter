import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/source/music_platform.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/profile/profile_stats.dart';
import '../../features/profile/source_account.dart';
import '../../features/profile/user_profile_detail.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// 个人中心 — 对齐 EchoMusic `Profile.vue` 的**独立内容页**。
///
/// 只承载账号身份：用户卡（等级/关注/粉丝/访客）+ 账号档案 + 会员状态。
/// 乐库（我喜欢 / 歌单 / 设置）留在 `/profile`「我的」，不混进本页。
class ProfileDetailPage extends ConsumerStatefulWidget {
  const ProfileDetailPage({super.key});

  @override
  ConsumerState<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends ConsumerState<ProfileDetailPage> {
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
    final isDesktop = isDesktopView(context);

    // 账号源：与「我的」页共用同一份选择（见 source_account.dart）。
    final accountSources = ref.watch(accountSourcePlatformsProvider);
    final accountPlatform = ref.watch(effectiveAccountSourceProvider);
    final account = ref.watch(sourceAccountProvider(accountPlatform));
    final isKugou = accountPlatform == MusicPlatform.kugou;

    // 等级 / 关注 / 粉丝 / 档案都是酷狗口径（UserProfileDetail），只在酷狗源下取。
    final user = ref.watch(authControllerProvider).user;
    final detail =
        isKugou ? (user?.detail ?? UserProfileDetail.empty) : UserProfileDetail.empty;
    final grade = isKugou ? getGradeProgress(detail.toDetailMap()) : null;

    Widget sourceBar(double horizontalPadding) => SourceFilterBar(
          platforms: accountSources,
          selected: accountPlatform,
          showAll: false,
          horizontalPadding: horizontalPadding,
          onSelect: (p) {
            if (p != null) ref.read(accountSourceProvider.notifier).state = p;
          },
        );

    if (!account.isLogged) {
      return Scaffold(
        backgroundColor: kugo.bg,
        body: SafeArea(
          child: Column(
            children: [
              const _DetailHeader(showLogout: false, onLogout: null),
              sourceBar(KugoSpacing.lg),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 64,
                        color: kugo.textSecondary.withValues(alpha: 0.45),
                      ),
                      const SizedBox(height: KugoSpacing.lg),
                      Text(
                        '请先登录${accountPlatform.label}账号',
                        style: kugo.title.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: KugoSpacing.xl),
                      FilledButton(
                        onPressed: () =>
                            context.push(loginRouteFor(accountPlatform)),
                        child: const Text('立即登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayName =
        account.nickname.isEmpty ? '${accountPlatform.label}用户' : account.nickname;

    return Scaffold(
      backgroundColor: kugo.bg,
      body: SafeArea(
        child: SmoothListView(
          padding: EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.md,
            KugoSpacing.lg,
            isDesktop ? 48 : 32,
          ),
          children: [
            _DetailHeader(
              showLogout: true,
              onLogout: () => logoutSource(ref, accountPlatform),
            ),
            sourceBar(0),
            const SizedBox(height: KugoSpacing.lg),
            _IdentityCard(
              avatarUrl: account.avatarUrl,
              displayName: displayName,
              // 签名 / IP / 等级 / 关注粉丝都是酷狗档案，网易侧留空不出。
              signature: isKugou ? detail.signature.trim() : '',
              ipLocation: isKugou ? detail.ipLocation : '',
              isVip: account.isVip,
              tvipActive: isKugou && detail.tvipActive,
              svipActive: isKugou && detail.svipActive,
              grade: grade,
              follows: isKugou ? detail.follows : null,
              fans: isKugou ? detail.fans : null,
              visitors: isKugou ? detail.visitors : null,
            ),
            if (isKugou) ...[
              const SizedBox(height: KugoSpacing.lg),
              _ArchiveAndMembership(
                userId: account.userId,
                detail: detail,
                isDesktop: isDesktop,
              ),
            ] else ...[
              const SizedBox(height: KugoSpacing.lg),
              _SourceAccountNotice(platform: accountPlatform),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.showLogout, required this.onLogout});

  final bool showLogout;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(KugoSpacing.lg, KugoSpacing.sm, KugoSpacing.sm, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // push 进来可 pop；侧栏 go 直达时回落到「我的」。
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/profile');
              }
            },
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          Text('个人中心', style: kugo.title.copyWith(fontSize: 22)),
          const Spacer(),
          if (showLogout && onLogout != null)
            IconButton(
              onPressed: onLogout,
              tooltip: '退出登录',
              style: IconButton.styleFrom(
                foregroundColor: Colors.redAccent,
                backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Echo `user-card`：头像 / 昵称 / VIP 徽章 / 签名 / IP + 等级·关注·粉丝·访客。
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.avatarUrl,
    required this.displayName,
    required this.signature,
    required this.ipLocation,
    required this.isVip,
    required this.tvipActive,
    required this.svipActive,
    required this.grade,
    required this.follows,
    required this.fans,
    required this.visitors,
  });

  final String avatarUrl;
  final String displayName;
  final String signature;
  final String ipLocation;
  final bool isVip;
  final bool tvipActive;
  final bool svipActive;

  /// 等级进度。null = 该源没有等级口径（网易），此时不出等级/关注/粉丝/访客一行。
  final GradeProgress? grade;
  final int? follows;
  final int? fans;
  final int? visitors;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final g = grade;
    return GlassSurface(
      padding: const EdgeInsets.all(KugoSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kugo.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: CoverBox(
                  seed: avatarUrl.isNotEmpty ? avatarUrl : 'avatar-guest',
                  size: 88,
                  radius: 999,
                  child: avatarUrl.isNotEmpty
                      ? null
                      : const Icon(
                          Icons.person_rounded,
                          color: Colors.white70,
                          size: 40,
                        ),
                ),
              ),
              const SizedBox(width: KugoSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          displayName,
                          style: kugo.title.copyWith(fontSize: 22),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tvipActive)
                          const _VipBadge(label: '畅听', color: Color(0xFF07C160)),
                        if (svipActive)
                          const _VipBadge(label: '概念', color: Color(0xFFF59E0B)),
                        if (!tvipActive && !svipActive && isVip)
                          const _VipBadge(label: '会员', color: Color(0xFFF59E0B)),
                      ],
                    ),
                    if (signature.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        signature,
                        style: kugo.caption.copyWith(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (ipLocation.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _IPLocationTag(text: ipLocation),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (g != null) ...[
            const SizedBox(height: KugoSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: '升级进度',
                    value: g.gradeLabel,
                    onTap: () => _showGradeSheet(context),
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _Stat(
                    label: '关注',
                    value: follows == null ? '—' : '$follows',
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _Stat(
                    label: '粉丝',
                    value: fans == null ? '—' : '$fans',
                  ),
                ),
                const _StatDivider(),
                Expanded(
                  child: _Stat(
                    label: '访客',
                    value: visitors == null ? '—' : '$visitors',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showGradeSheet(BuildContext context) {
    final grade = this.grade;
    if (grade == null) return;
    showKugoBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final kugo = KugoTheme.of(sheetContext);
        final percent = grade.percent;
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
              Center(child: Text('我的等级', style: kugo.section)),
              const SizedBox(height: 4),
              Center(child: Text('每一次聆听，都在积累成长。', style: kugo.caption)),
              const SizedBox(height: KugoSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(KugoSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kugo.primary.withValues(alpha: 0.16),
                      kugo.primary.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kugo.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前等级', style: kugo.caption),
                    const SizedBox(height: 4),
                    Text(grade.gradeLabel, style: kugo.title.copyWith(fontSize: 30)),
                    const SizedBox(height: KugoSpacing.lg),
                    if (grade.available) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '距 Lv.${grade.nextGrade} 还差 ${grade.remaining ?? 0} 经验',
                              style: kugo.caption,
                            ),
                          ),
                          Text(
                            '${grade.current ?? 0} / ${grade.target ?? 0}',
                            style: kugo.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (percent / 100).clamp(0, 1).toDouble(),
                          minHeight: 6,
                          backgroundColor: kugo.divider,
                        ),
                      ),
                    ] else
                      Text('暂未获取到下一等级进度', style: kugo.caption),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VipBadge extends StatelessWidget {
  const _VipBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _IPLocationTag extends StatelessWidget {
  const _IPLocationTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kugo.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kugo.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: kugo.primary,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      child: SizedBox(
        height: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              value,
              style: kugo.section.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: kugo.caption),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: KugoTheme.of(context).divider);
  }
}

/// 账号档案 + 会员状态（宽屏双栏 / 窄屏单列），对齐 Echo `profile-info-grid`。
class _ArchiveAndMembership extends StatelessWidget {
  const _ArchiveAndMembership({
    required this.userId,
    required this.detail,
    required this.isDesktop,
  });

  final String userId;
  final UserProfileDetail detail;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final archive = GlassSurface(
      padding: const EdgeInsets.all(KugoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 18, color: kugo.primary),
              const SizedBox(width: 8),
              Text('账号档案', style: kugo.section.copyWith(fontSize: 16)),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          _ArchiveRow(label: '用户 ID', value: userId.isEmpty ? '—' : userId),
          _ArchiveRow(label: '性别', value: formatGender(detail.gender)),
          _ArchiveRow(
            label: '乐龄',
            value: formatAccountAge(detail.registerTime),
          ),
          _ArchiveRow(
            label: '累计听歌',
            value: formatListeningDuration(
              detail.listenSeconds,
              detail.listenMinutes,
            ),
          ),
          _ArchiveRow(label: '所在地区', value: _locationText(detail)),
        ],
      ),
    );

    final membership = GlassSurface(
      padding: const EdgeInsets.all(KugoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard_outlined, size: 18, color: kugo.primary),
              const SizedBox(width: 8),
              Text('会员状态', style: kugo.section.copyWith(fontSize: 16)),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          _MembershipTile(
            title: '畅听会员',
            active: detail.tvipActive,
            accent: const Color(0xFF07C160),
            icon: Icons.home_outlined,
            expireText: formatVipExpireText(detail.tvipEnd),
            beginText: formatVipDate(detail.tvipBegin),
            endText: formatVipDate(detail.tvipEnd),
          ),
          const SizedBox(height: KugoSpacing.sm),
          _MembershipTile(
            title: '概念会员',
            active: detail.svipActive,
            accent: const Color(0xFFF59E0B),
            icon: Icons.crop_free_rounded,
            expireText: formatVipExpireText(detail.svipEnd),
            beginText: formatVipDate(detail.svipBegin),
            endText: formatVipDate(detail.svipEnd),
          ),
        ],
      ),
    );

    if (!isDesktop) {
      return Column(
        children: [
          archive,
          const SizedBox(height: KugoSpacing.lg),
          membership,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: archive),
        const SizedBox(width: KugoSpacing.lg),
        Expanded(flex: 2, child: membership),
      ],
    );
  }

  static String _locationText(UserProfileDetail detail) {
    final p = detail.province.trim();
    final c = detail.city.trim();
    if (p.isNotEmpty && c.isNotEmpty) return '$p - $c';
    if (p.isNotEmpty) return p;
    if (c.isNotEmpty) return c;
    return '—';
  }
}

class _SourceAccountNotice extends StatelessWidget {
  const _SourceAccountNotice({required this.platform});

  final MusicPlatform platform;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.all(KugoSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: kugo.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${platform.label}账号暂不提供等级 / 歌龄 / 关注粉丝等档案信息；'
              '歌单与「我喜欢」见「我的」页。',
              style: kugo.caption.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Text(label, style: kugo.caption),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: kugo.body.copyWith(fontSize: 13),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipTile extends StatelessWidget {
  const _MembershipTile({
    required this.title,
    required this.active,
    required this.accent,
    required this.icon,
    required this.expireText,
    required this.beginText,
    required this.endText,
  });

  final String title;
  final bool active;
  final Color accent;
  final IconData icon;
  final String? expireText;
  final String beginText;
  final String endText;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final bg = active
        ? accent.withValues(alpha: 0.12)
        : kugo.surfaceElevated.withValues(alpha: 0.55);
    final border = active ? accent.withValues(alpha: 0.25) : Colors.transparent;
    return Opacity(
      opacity: active ? 1 : 0.62,
      child: Container(
        padding: const EdgeInsets.all(KugoSpacing.md),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.18)
                    : kugo.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: active ? accent : kugo.textSecondary,
              ),
            ),
            const SizedBox(width: KugoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: kugo.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active ? accent : kugo.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (active && expireText != null)
                    Tooltip(
                      message: '开始 $beginText · 到期 $endText',
                      child: Text(
                        expireText!,
                        style: kugo.caption.copyWith(fontSize: 11),
                      ),
                    )
                  else
                    Text(
                      '未开通',
                      style: kugo.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (active)
              Icon(Icons.check_circle_rounded, color: accent, size: 18),
          ],
        ),
      ),
    );
  }
}
