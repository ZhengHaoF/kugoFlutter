import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/kugo_tokens.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscureCode = true;
  bool _obscurePwd = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).startQrLogin();
    });
  }

  @override
  void dispose() {
    ref.read(authControllerProvider.notifier).stopQrPolling();
    _tabs.dispose();
    _phone.dispose();
    _code.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _popIfLogged() async {
    // Navigation handled by ref.listen → context.go('/profile').
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);

    // Any successful login (QR / SMS / password) → back to 我的 tab.
    ref.listen(authControllerProvider, (prev, next) {
      final wasLogged = prev?.isLogged ?? false;
      if (next.isLogged && !wasLogged && mounted) {
        context.go('/profile');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: KugoColors.primary,
          labelColor: KugoColors.primary,
          unselectedLabelColor: KugoColors.textSecondary,
          tabs: const [
            Tab(text: '扫码'),
            Tab(text: '验证码'),
            Tab(text: '账号'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: [
            // --- QR ---
            _QrLoginView(
              auth: auth,
              onRefresh: controller.startQrLogin,
            ),
            // --- SMS ---
            ListView(
              padding: const EdgeInsets.all(KugoSpacing.xl),
              children: [
                const Text('手机验证码登录', style: KugoTypography.section),
                const SizedBox(height: 8),
                Text(
                  '使用酷狗绑定手机号接收短信验证码',
                  style: KugoTypography.caption,
                ),
                const SizedBox(height: KugoSpacing.xl),
                _Field(
                  controller: _phone,
                  hint: '手机号',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: KugoSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _code,
                        hint: '验证码',
                        keyboardType: TextInputType.number,
                        obscure: _obscureCode,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureCode
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _obscureCode = !_obscureCode),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: auth.smsCountdown > 0
                            ? null
                            : () => controller.sendSmsCode(_phone.text),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KugoColors.primary,
                          side: const BorderSide(color: KugoColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(KugoRadius.chip),
                          ),
                        ),
                        child: Text(
                          auth.smsCountdown > 0
                              ? '${auth.smsCountdown}s'
                              : '获取验证码',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KugoSpacing.lg),
                if (auth.errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KugoSpacing.md),
                    child: Text(
                      auth.errorMessage,
                      style: KugoTypography.caption.copyWith(
                        color: auth.status == LoginStatus.logged
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: auth.status == LoginStatus.loading
                      ? null
                      : () async {
                          final ok = await controller.loginWithSms(
                            phone: _phone.text,
                            code: _code.text,
                          );
                          if (ok) await _popIfLogged();
                        },
                  child: auth.status == LoginStatus.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            ),
            // --- Password ---
            ListView(
              padding: const EdgeInsets.all(KugoSpacing.xl),
              children: [
                const Text('账号密码登录', style: KugoTypography.section),
                const SizedBox(height: 8),
                Text(
                  '酷狗账号 / 手机号 + 密码',
                  style: KugoTypography.caption,
                ),
                const SizedBox(height: KugoSpacing.xl),
                _Field(controller: _username, hint: '账号 / 手机号'),
                const SizedBox(height: KugoSpacing.md),
                _Field(
                  controller: _password,
                  hint: '密码',
                  obscure: _obscurePwd,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePwd
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePwd = !_obscurePwd),
                  ),
                ),
                const SizedBox(height: KugoSpacing.lg),
                if (auth.errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: KugoSpacing.md),
                    child: Text(
                      auth.errorMessage,
                      style: KugoTypography.caption
                          .copyWith(color: Colors.redAccent),
                    ),
                  ),
                FilledButton(
                  onPressed: auth.status == LoginStatus.loading
                      ? null
                      : () async {
                          final ok = await controller.loginWithPassword(
                            username: _username.text,
                            password: _password.text,
                          );
                          if (ok) await _popIfLogged();
                        },
                  child: auth.status == LoginStatus.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.xl,
            0,
            KugoSpacing.xl,
            KugoSpacing.lg,
          ),
          child: OutlinedButton.icon(
            onPressed: () async {
              await controller.continueAsGuest();
              if (context.mounted) context.pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: KugoColors.textPrimary,
              side: const BorderSide(color: KugoColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KugoRadius.chip),
              ),
            ),
            icon: const Icon(Icons.person_outline_rounded, size: 18),
            label: const Text('游客继续，先听歌'),
          ),
        ),
      ),
    );
  }
}

class _QrLoginView extends StatelessWidget {
  const _QrLoginView({required this.auth, required this.onRefresh});

  final AuthState auth;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final phase = auth.qrPhase;
    final url = auth.qrContentUrl;

    Widget center;
    if (phase == QrPhase.loading) {
      center = const CircularProgressIndicator();
    } else if (phase == QrPhase.waiting ||
        phase == QrPhase.scanned ||
        phase == QrPhase.success) {
      center = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(KugoRadius.card),
            ),
            child: QrImageView(
              data: url,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: KugoSpacing.lg),
          Text(
            switch (phase) {
              QrPhase.scanned => '已扫码，请在手机上确认',
              QrPhase.success => '登录成功',
              _ => '请用酷狗 App 扫码登录',
            },
            style: KugoTypography.body,
          ),
          if (phase == QrPhase.waiting) ...[
            const SizedBox(height: 8),
            Text('每 3 秒自动检测', style: KugoTypography.caption),
          ],
        ],
      );
    } else if (phase == QrPhase.expired) {
      center = _StatusBox(
        icon: Icons.qr_code_2_rounded,
        message: '二维码已过期',
        actionLabel: '刷新',
        onAction: onRefresh,
      );
    } else {
      center = _StatusBox(
        icon: Icons.wifi_off_rounded,
        message: auth.errorMessage.isEmpty ? '二维码加载失败' : auth.errorMessage,
        actionLabel: '重试',
        onAction: onRefresh,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KugoSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('酷狗扫码登录', style: KugoTypography.section),
          const SizedBox(height: 8),
          Text(
            '打开手机酷狗扫一扫；登录后可同步喜欢与播放地址权限',
            style: KugoTypography.caption,
          ),
          const SizedBox(height: KugoSpacing.xxl),
          Center(child: center),
          const SizedBox(height: KugoSpacing.xl),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KugoColors.surface,
              borderRadius: BorderRadius.circular(KugoRadius.tile),
            ),
            child: Text(
              '说明：登录仅走真实网关，失败不会生成假账号。\n'
              '播放公开曲目通常也需要登录态（游客通道已关闭）。',
              style: KugoTypography.caption.copyWith(
                color: KugoColors.textTertiary,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
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
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: KugoColors.textTertiary),
        const SizedBox(height: KugoSpacing.md),
        Text(message, style: KugoTypography.caption, textAlign: TextAlign.center),
        const SizedBox(height: KugoSpacing.lg),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: KugoTypography.body,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KugoTypography.caption,
        filled: true,
        fillColor: KugoColors.surface,
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KugoRadius.tile),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
