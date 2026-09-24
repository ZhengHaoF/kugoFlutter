import 'package:kugo/core/source/capabilities.dart';

/// 测试用假扫码登录源：按脚本吐状态，不碰网络。
class FakeDeviceLoginSource implements DeviceLoginSource {
  /// 每拍弹出一个状态；用完后一直返回 [LoginQrStatus.waiting]。
  final List<LoginQrStatus> script = [];

  /// [currentAccount] 的返回值。
  LoginAccount? account;

  /// 非空时 [createLoginQr] 抛该错误。
  Object? createError;

  int createCalls = 0;
  int pollCalls = 0;
  int logoutCalls = 0;

  @override
  Future<LoginQrSession> createLoginQr() async {
    createCalls++;
    final err = createError;
    if (err != null) throw err;
    return const LoginQrSession(
      id: 'fake-key',
      qrContent: 'https://music.163.com/st/platform/scanlogin?codekey=fake-key',
    );
  }

  @override
  Future<LoginQrPoll> pollLoginQr(LoginQrSession session) async {
    pollCalls++;
    final status =
        script.isEmpty ? LoginQrStatus.waiting : script.removeAt(0);
    return LoginQrPoll(status: status);
  }

  @override
  Future<LoginAccount?> currentAccount() async => account;

  @override
  Future<void> logout() async {
    logoutCalls++;
    account = null;
  }
}
