import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/source/capabilities.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/smooth_scroll.dart';
import 'bili_login_controller.dart';

class BiliLoginPage extends ConsumerStatefulWidget {
  const BiliLoginPage({super.key, this.forceRelogin = false});
  final bool forceRelogin;
  @override
  ConsumerState<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends ConsumerState<BiliLoginPage> {
  late BiliLoginController _controller;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(biliLoginControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.forceRelogin) {
        _controller.startQr();
      } else {
        _controller.bootstrap();
      }
    });
  }

  @override
  void dispose() {
    _controller.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(biliLoginControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('哔哩哔哩账号')),
      body: SmoothSingleChildScrollView(
        padding: const EdgeInsets.all(KugoSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.account case final account?) ...[
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.nickname),
                subtitle: Text('UID ${account.userId}'),
              ),
              TextButton(
                onPressed: _controller.startQr,
                child: const Text('切换账号'),
              ),
              TextButton(
                onPressed: _controller.logout,
                child: const Text('退出登录'),
              ),
            ] else ...[
              const Text('打开哔哩哔哩 App 扫一扫，扫码后在手机上确认登录。'),
              const SizedBox(height: KugoSpacing.xl),
              if (state.loading)
                const Center(child: CircularProgressIndicator()),
              if (state.session != null &&
                  state.status != LoginQrStatus.expired)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: state.session!.qrContent,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(height: KugoSpacing.lg),
              Text(switch (state.status) {
                LoginQrStatus.scanned => '已扫码，请在手机上确认',
                LoginQrStatus.expired => '二维码已过期，请刷新',
                _ => '等待扫码',
              }, textAlign: TextAlign.center),
              if (state.error.isNotEmpty)
                Text(state.error, textAlign: TextAlign.center),
              TextButton(
                onPressed: _controller.startQr,
                child: const Text('刷新二维码'),
              ),
            ],
            const SizedBox(height: KugoSpacing.xl),
            const Text(
              '登录凭据仅存本机，退出登录即清除。游客仍可搜索与播放；'
              '登录后可读取收藏夹。B 站不提供云端红心歌曲，红心仅保存在本地。',
            ),
          ],
        ),
      ),
    );
  }
}
