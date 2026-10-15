import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/overtone_tokens.dart';
import '../../core/theme/overtone_theme.dart';
import '../../shared/widgets/smooth_scroll.dart';
import 'netease_login_controller.dart';

/// 网易云扫码登录页（与酷狗 [LoginPage] 分开，两套账号互不影响）。
class NeteaseLoginPage extends ConsumerStatefulWidget {
  const NeteaseLoginPage({super.key, this.forceRelogin = false});

  /// 设置页「切换账号」传入：无视已登录态直接出新码（扫码后顶替旧账号）。
  final bool forceRelogin;

  @override
  ConsumerState<NeteaseLoginPage> createState() => _NeteaseLoginPageState();
}

class _NeteaseLoginPageState extends ConsumerState<NeteaseLoginPage> {
  @override
  void initState() {
    super.initState();
    // 进页即初始化：已登录只回显账号，未登录才拉二维码。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = ref.read(neteaseLoginControllerProvider.notifier);
      if (widget.forceRelogin) {
        c.startQr();
      } else {
        c.bootstrap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    final state = ref.watch(neteaseLoginControllerProvider);
    final controller = ref.read(neteaseLoginControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('网易云账号')),
      body: SmoothSingleChildScrollView(
        padding: const EdgeInsets.all(OvertoneSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isLogged) ...[
              _AccountCard(
                nickname: state.account!.nickname,
                userId: state.account!.userId,
                isVip: state.account!.isVip,
                onLogout: () async {
                  await controller.logout();
                  if (context.mounted) context.pop();
                },
              ),
            ] else ...[
              Text('网易云扫码登录', style: theme.section),
              const SizedBox(height: 8),
              Text(
                '打开手机「网易云音乐」App → 扫一扫，扫描下方二维码',
                style: theme.caption,
              ),
              const SizedBox(height: OvertoneSpacing.xxl),
              Center(child: _QrArea(state: state, onRefresh: controller.startQr)),
            ],
            const SizedBox(height: OvertoneSpacing.xl),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(OvertoneRadius.tile),
              ),
              child: Text(
                '说明：登录仅走网易云真实网关，失败不会生成假账号。\n'
                '登录态（MUSIC_U）只存本机，退出即清除。',
                style: theme.caption.copyWith(
                  color: theme.textTertiary,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrArea extends StatelessWidget {
  const _QrArea({required this.state, required this.onRefresh});

  final NeteaseLoginState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    final phase = state.phase;

    if (phase == NeteaseQrPhase.loading || phase == NeteaseQrPhase.idle) {
      return const CircularProgressIndicator();
    }
    if (phase == NeteaseQrPhase.expired) {
      return _StatusBox(
        icon: Icons.qr_code_2_rounded,
        message: '二维码已过期',
        actionLabel: '刷新',
        onAction: onRefresh,
      );
    }
    if (phase == NeteaseQrPhase.error) {
      return _StatusBox(
        icon: Icons.wifi_off_rounded,
        message: state.errorMessage.isEmpty ? '二维码加载失败' : state.errorMessage,
        actionLabel: '重试',
        onAction: onRefresh,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(OvertoneRadius.card),
          ),
          child: QrImageView(
            data: state.qrContentUrl,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: OvertoneSpacing.lg),
        Text(
          switch (phase) {
            NeteaseQrPhase.scanned => '已扫码，请在手机上确认',
            NeteaseQrPhase.success => '登录成功',
            _ => '请用网易云音乐 App 扫码登录',
          },
          style: theme.body,
        ),
        if (phase == NeteaseQrPhase.waiting) ...[
          const SizedBox(height: 8),
          Text('每 2 秒自动检测', style: theme.caption),
        ],
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.nickname,
    required this.userId,
    required this.isVip,
    required this.onLogout,
  });

  final String nickname;
  final String userId;
  final bool isVip;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('已登录', style: theme.section),
        const SizedBox(height: OvertoneSpacing.md),
        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(OvertoneRadius.card),
          child: ListTile(
            leading: Icon(
              Icons.account_circle_rounded,
              size: 40,
              color: theme.primary,
            ),
            title: Text(nickname, style: theme.body),
            subtitle: Text(
              'UID $userId${isVip ? ' · VIP' : ''}',
              style: theme.caption,
            ),
            trailing: TextButton(
              onPressed: onLogout,
              child: const Text('退出登录'),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBox extends StatelessWidget {
  const _StatusBox({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final theme = OvertoneTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: theme.textTertiary),
        const SizedBox(height: OvertoneSpacing.md),
        Text(message, style: theme.caption, textAlign: TextAlign.center),
        const SizedBox(height: OvertoneSpacing.lg),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
