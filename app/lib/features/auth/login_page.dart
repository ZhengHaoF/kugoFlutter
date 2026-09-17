import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() {
    return ref.read(authControllerProvider.notifier).sendSmsCode(_phone.text);
  }

  Future<void> _login() async {
    final ok = await ref.read(authControllerProvider.notifier).loginWithSms(
          phone: _phone.text,
          code: _code.text,
        );
    if (ok && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(KugoSpacing.xl),
          children: [
            const SizedBox(height: KugoSpacing.md),
            const Text('欢迎回来', style: KugoTypography.greeting),
            const SizedBox(height: 8),
            Text(
              '登录可同步我喜欢与播放记录；不登录也能完整听歌',
              style: KugoTypography.caption,
            ),
            const SizedBox(height: KugoSpacing.xxl),
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
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: auth.smsCountdown > 0 ? null : _sendCode,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KugoColors.primary,
                      side: const BorderSide(color: KugoColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KugoRadius.chip),
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
              onPressed: auth.status == LoginStatus.loading ? null : _login,
              child: auth.status == LoginStatus.loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
            const SizedBox(height: KugoSpacing.lg),
            // Guest-first CTA
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref
                      .read(authControllerProvider.notifier)
                      .continueAsGuest();
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
            const SizedBox(height: KugoSpacing.xl),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KugoColors.surface,
                borderRadius: BorderRadius.circular(KugoRadius.tile),
              ),
              child: Text(
                '说明\n'
                '· 游客模式：公开搜索 / 歌单 / 播放可用，数据仅存本机\n'
                '· 登录仅走真实网关，失败不会生成假账号\n'
                '· 本应用为学习/研究向第三方客户端，不提供账号托管',
                style: KugoTypography.caption.copyWith(
                  color: KugoColors.textTertiary,
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
