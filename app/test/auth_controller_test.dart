import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/login_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/data/storage/credential_store.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/profile/user_profile_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登录态状态机。
///
/// 这份用例原先第一个 test 会打**真实酷狗网关**（`loginRepository` 是全局
/// 单例，`AuthController` 直接调它），而且写成 `if (!ok) {断言A} else {断言B}`
/// ——两个分支都断言合法值，永远不可能失败。`AuthController` 因此加了可注入的
/// `repository`，这里用假仓库把三条登录路径（QR / 短信 / 密码）全部离线化，
/// 并守住「网关失败绝不伪造本地会话」这条产品底线。
class _FakeLoginRepository extends LoginRepository {
  _FakeLoginRepository() : super(dio: Dio());

  // ── 脚本化返回 ──
  ({String key, String contentUrl})? qrCreated;
  ({int status, LoginSession? session})? pollResult;
  bool smsSent = false;
  LoginSession? smsSession;
  LoginSession? passwordSession;
  MyProfile? myInfo;

  // ── 调用记录 ──
  int createQrCalls = 0;
  final List<String> polledKeys = [];
  final List<String> smsMobiles = [];
  final List<({String username, String password})> passwordLogins = [];
  int fetchMyInfoCalls = 0;

  @override
  Future<({String key, String contentUrl})?> createQrLogin() async {
    createQrCalls++;
    return qrCreated;
  }

  @override
  Future<({int status, LoginSession? session})?> checkQrLogin(
    String key,
  ) async {
    polledKeys.add(key);
    return pollResult;
  }

  @override
  Future<bool> sendSmsCode(String mobile) async {
    smsMobiles.add(mobile);
    return smsSent;
  }

  @override
  Future<LoginSession?> loginWithSms({
    required String mobile,
    required String code,
    String userid = '',
  }) async {
    smsMobiles.add(mobile);
    return smsSession;
  }

  @override
  Future<LoginSession?> loginWithPassword({
    required String username,
    required String password,
  }) async {
    passwordLogins.add((username: username, password: password));
    return passwordSession;
  }

  @override
  Future<MyProfile?> fetchMyInfo({
    required String token,
    required String userId,
    String t1 = '',
  }) async {
    fetchMyInfoCalls++;
    return myInfo;
  }
}

LoginSession _session({
  String userId = '12345',
  String token = 'tok-abc',
  String nickname = '测试用户',
}) => LoginSession(userId: userId, token: token, nickname: nickname);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 把挂起的 Future（轮询 → 完成登录 → 写盘）跑完。
  /// 不用 pumpAndSettle：轮询 timer 还活着，会一直超时。
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  /// 预置「设备已注册」，否则 `DeviceIdentity.ensure()` 会打
  /// `/risk/v2/r_register_dev`（又一个真实网络调用）。
  void seedRegisteredDevice() {
    SharedPreferences.setMockInitialValues(const {
      'kugo_device_dfid': 'test-dfid',
      'kugo_device_guid': 'test-guid',
      'kugo_device_mid': 'test-mid',
      'kugo_device_dev': 'kugoFlutter',
      'kugo_device_dfid_registered': true,
    });
  }

  setUp(() async {
    AuthTokenHolder.instance.clear();
    // 先装上 shared_preferences 的内存实现，否则 reset() 会撞 MissingPlugin。
    SharedPreferences.setMockInitialValues(const {});
    await DeviceIdentity.reset();
    seedRegisteredDevice();
  });

  /// 建一个注入了 [repo] 的容器，并等到本地会话恢复完成。
  Future<(ProviderContainer, _FakeLoginRepository, AuthController)> bootstrap(
    _FakeLoginRepository repo,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => AuthController(repository: repo),
        ),
      ],
    );
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier);
    await auth.ensureReady();
    return (container, repo, auth);
  }

  group('短信登录', () {
    test('网关返回会话 → 登录态落盘（扁平 key=value），不编造本地会话', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (container, _, auth) = await bootstrap(repo);

      final ok = await auth.loginWithSms(phone: '13800138000', code: '1234');
      expect(ok, isTrue);

      final state = container.read(authControllerProvider);
      expect(state.isLogged, isTrue);
      expect(state.status, LoginStatus.logged);
      expect(state.errorMessage, isEmpty);
      // 关键：isLocalDemo 必须为 false——失败时可以兜游客，成功时不能造假用户。
      expect(state.user?.isLocalDemo, isFalse);
      expect(state.user?.userId, '12345');
      expect(state.user?.token, 'tok-abc');
      expect(AuthTokenHolder.instance.hasToken, isTrue);

      // 落盘的是 `k=v&k=v` 扁平串（AuthUser.toJson 的编码）。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
      expect(
        await CredentialStore.read('auth.user.v1'),
        contains('userId=12345'),
      );
      expect(
        await CredentialStore.read('auth.user.v1'),
        contains('token=tok-abc'),
      );
      // 登录成功会摘掉 guest 标记（remove 后 getBool 返回 null）。
      expect(prefs.getBool('auth.guest.v1'), isNull);
    });

    test('网关失败（无会话）→ 不进本地会话，错误码上抛，且不写盘', () async {
      final repo = _FakeLoginRepository()
        ..smsSession = null
        ..lastError = '验证码错误';
      final (container, _, auth) = await bootstrap(repo);

      final ok = await auth.loginWithSms(phone: '13800138000', code: '1234');
      expect(ok, isFalse);

      final state = container.read(authControllerProvider);
      expect(state.isLogged, isFalse);
      expect(state.status, LoginStatus.error);
      expect(state.user?.isLocalDemo ?? false, isFalse);
      expect(state.errorMessage, '验证码错误');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
      expect(AuthTokenHolder.instance.hasToken, isFalse);
    });

    test('lastError 为空时给中文兜底文案', () async {
      final repo = _FakeLoginRepository()..smsSession = null;
      final (container, _, auth) = await bootstrap(repo);

      await auth.loginWithSms(phone: '13800138000', code: '1234');
      expect(container.read(authControllerProvider).errorMessage, '登录失败');
    });

    test('非法手机号 / 验证码过短 → 短路，根本不调仓库', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (container, _, auth) = await bootstrap(repo);

      expect(await auth.loginWithSms(phone: '123', code: '1234'), isFalse);
      expect(
        container.read(authControllerProvider).errorMessage,
        '请输入 11 位手机号',
      );
      expect(
        await auth.loginWithSms(phone: '13800138000', code: '12'),
        isFalse,
      );
      expect(
        container.read(authControllerProvider).errorMessage,
        '请输入至少 4 位验证码',
      );
      // 两次都在参数校验阶段返回，仓库一次都没被碰到。
      expect(repo.smsMobiles, isEmpty);
      expect(repo.fetchMyInfoCalls, 0);
    });

    test('手机号首尾空白被裁掉后再传给仓库', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (_, _, auth) = await bootstrap(repo);

      await auth.loginWithSms(phone: '  13800138000  ', code: '1234');
      expect(repo.smsMobiles, ['13800138000']);
    });
  });

  group('验证码发送', () {
    test('非法手机号短路，不起 60 秒倒计时', () async {
      final repo = _FakeLoginRepository();
      final (container, _, auth) = await bootstrap(repo);

      await auth.sendSmsCode('123');
      expect(
        container.read(authControllerProvider).errorMessage,
        '请输入 11 位手机号',
      );
      expect(repo.smsMobiles, isEmpty);
      expect(container.read(authControllerProvider).smsCountdown, 0);
    });

    test('发送成功 → 倒计时从 60 开始并逐秒递减', () async {
      final repo = _FakeLoginRepository()..smsSent = true;
      final (container, _, auth) = await bootstrap(repo);

      expect(await auth.sendSmsCode('13800138000'), isTrue);
      expect(repo.smsMobiles, ['13800138000']);
      expect(container.read(authControllerProvider).smsCountdown, 60);
    });

    test('发送失败 → 带回错误文案，不倒计时', () async {
      final repo = _FakeLoginRepository()
        ..smsSent = false
        ..lastError = '发送太频繁';
      final (container, _, auth) = await bootstrap(repo);

      expect(await auth.sendSmsCode('13800138000'), isFalse);
      expect(container.read(authControllerProvider).errorMessage, '发送太频繁');
      expect(container.read(authControllerProvider).smsCountdown, 0);
    });
  });

  group('密码登录', () {
    test('空账号/密码短路，不调仓库', () async {
      final repo = _FakeLoginRepository()..passwordSession = _session();
      final (container, _, auth) = await bootstrap(repo);

      expect(
        await auth.loginWithPassword(username: '', password: 'x'),
        isFalse,
      );
      expect(container.read(authControllerProvider).errorMessage, '请输入账号和密码');
      expect(repo.passwordLogins, isEmpty);
    });

    test('网关失败 → error 态 + 不写盘', () async {
      final repo = _FakeLoginRepository()
        ..passwordSession = null
        ..lastError = '密码错误';
      final (container, _, auth) = await bootstrap(repo);

      expect(
        await auth.loginWithPassword(username: 'u', password: 'p'),
        isFalse,
      );
      final state = container.read(authControllerProvider);
      expect(state.status, LoginStatus.error);
      expect(state.errorMessage, '密码错误');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
    });
  });

  group('资料补全', () {
    test('fetchMyInfo 补昵称 / 头像 / VIP，并写回落盘', () async {
      final repo = _FakeLoginRepository()
        ..smsSession = _session(nickname: '网关昵称')
        ..myInfo = const MyProfile(
          nickname: '真实昵称',
          avatarUrl: 'https://avatar/x.jpg',
          isVip: true,
          userId: '12345',
        );
      final (container, _, auth) = await bootstrap(repo);

      await auth.loginWithSms(phone: '13800138000', code: '1234');
      expect(repo.fetchMyInfoCalls, 1);

      final user = container.read(authControllerProvider).user!;
      expect(user.nickname, '真实昵称');
      expect(user.avatarUrl, 'https://avatar/x.jpg');
      expect(user.isVip, isTrue);
      expect(user.detail, UserProfileDetail.empty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
      expect(await CredentialStore.read('auth.user.v1'), contains('nickname='));
    });

    test('fetchMyInfo 返回 null 时保留网关给的基本身份', () async {
      final repo = _FakeLoginRepository()
        ..smsSession = _session(nickname: '网关昵称')
        ..myInfo = null;
      final (container, _, auth) = await bootstrap(repo);

      await auth.loginWithSms(phone: '13800138000', code: '1234');
      final user = container.read(authControllerProvider).user!;
      expect(user.nickname, '网关昵称');
      expect(user.avatarUrl, isEmpty);
      expect(user.isVip, isFalse);
    });

    test('refreshProfile 未登录时直接返回，不发请求', () async {
      final repo = _FakeLoginRepository()..myInfo = const MyProfile();
      final (_, _, auth) = await bootstrap(repo);

      await auth.refreshProfile();
      expect(repo.fetchMyInfoCalls, 0);
    });

    test('refreshProfile 合并档案并只在校验变化时重算', () async {
      final repo = _FakeLoginRepository()
        ..smsSession = _session()
        ..myInfo = const MyProfile(
          nickname: '第一版',
          avatarUrl: 'https://a/1.jpg',
        );
      final (container, _, auth) = await bootstrap(repo);
      await auth.loginWithSms(phone: '13800138000', code: '1234');

      repo.myInfo = const MyProfile(
        nickname: '第二版',
        avatarUrl: 'https://a/2.jpg',
      );
      await auth.refreshProfile();
      expect(container.read(authControllerProvider).user?.nickname, '第二版');

      // fetchMyInfo 每次都发；早退只避免**状态被重新赋值**（昵称/头像/
      /// VIP/档案全同则不建新 AuthState），所以调用数照涨但用户数据不抖。
      await auth.refreshProfile();
      expect(container.read(authControllerProvider).user?.nickname, '第二版');
      expect(repo.fetchMyInfoCalls, 3);
    });
  });

  group('本地会话恢复', () {
    test('有落盘用户 → 冷启动直接进登录态（无网络）', () async {
      final encoded =
          <String, String>{
                'userId': '777',
                'nickname': '老用户',
                'token': 'old-token',
                'avatarUrl': '',
                'isVip': 'false',
                'isLocalDemo': 'false',
                't1': '',
                'detailJson': '{}',
              }.entries
              .map(
                (e) =>
                    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
              )
              .join('&');
      SharedPreferences.setMockInitialValues({'auth.user.v1': encoded});
      final repo = _FakeLoginRepository();
      final (container, _, _) = await bootstrap(repo);

      final state = container.read(authControllerProvider);
      expect(state.isLogged, isTrue);
      expect(state.user?.userId, '777');
      expect(state.user?.nickname, '老用户');
      expect(AuthTokenHolder.instance.hasToken, isTrue);
      // 恢复路径不碰网关。
      expect(repo.fetchMyInfoCalls, 0);
    });

    test('无落盘用户 → 游客态，并写下 guest 标记', () async {
      final repo = _FakeLoginRepository();
      final (container, _, _) = await bootstrap(repo);

      final state = container.read(authControllerProvider);
      expect(state.isLogged, isFalse);
      expect(state.isGuest, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth.guest.v1'), isTrue);
    });
  });

  group('游客 / 登出 / 未授权', () {
    test('continueAsGuest 清掉 token 并落 guest 标记', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (container, _, auth) = await bootstrap(repo);
      await auth.loginWithSms(phone: '13800138000', code: '1234');

      await auth.continueAsGuest();
      final state = container.read(authControllerProvider);
      expect(state.isGuest, isTrue);
      expect(state.isLogged, isFalse);
      expect(AuthTokenHolder.instance.hasToken, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
      expect(prefs.getBool('auth.seen.v1'), isTrue);
    });

    test('logout 回到游客并清掉落盘用户', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (container, _, auth) = await bootstrap(repo);
      await auth.loginWithSms(phone: '13800138000', code: '1234');

      await auth.logout();
      final state = container.read(authControllerProvider);
      expect(state.isLogged, isFalse);
      expect(state.isGuest, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.user.v1'), isNull);
      expect(prefs.getBool('auth.guest.v1'), isTrue);
    });

    test('onUnauthorized 未登录时是空操作', () async {
      final repo = _FakeLoginRepository();
      final (_, _, auth) = await bootstrap(repo);

      await auth.onUnauthorized();
      // 不抛、状态仍是游客。
      expect(auth.state.isGuest, isTrue);
    });

    test('onUnauthorized 已登录时执行登出', () async {
      final repo = _FakeLoginRepository()..smsSession = _session();
      final (container, _, auth) = await bootstrap(repo);
      await auth.loginWithSms(phone: '13800138000', code: '1234');

      await auth.onUnauthorized();
      expect(container.read(authControllerProvider).isLogged, isFalse);
    });
  });

  group('二维码登录', () {
    testWidgets('拿到二维码 → waiting 态 + 内容 URL', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = (key: 'qr-key-1', contentUrl: 'https://qr/x');
      final (container, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();

      final state = container.read(authControllerProvider);
      expect(state.qrPhase, QrPhase.waiting);
      expect(state.qrContentUrl, 'https://qr/x');
      expect(state.qrKey, 'qr-key-1');
      expect(repo.createQrCalls, 1);

      // 收尾：轮询 timer 是周期性的，不取消会被 binding 判定为 pending timer。
      auth.stopQrPolling();
    });

    testWidgets('创建失败 → error 态带错误文案', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = null
        ..lastError = '获取二维码失败';
      final (container, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();

      final state = container.read(authControllerProvider);
      expect(state.qrPhase, QrPhase.error);
      expect(state.errorMessage, '获取二维码失败');
    });

    testWidgets('轮询到已确认 → 完成登录并停止轮询', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = (key: 'qr-key-1', contentUrl: 'https://qr/x')
        ..pollResult = (status: 4, session: _session(nickname: '扫码用户'));
      final (container, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      await flush(tester);

      expect(repo.polledKeys, ['qr-key-1']);
      final state = container.read(authControllerProvider);
      expect(state.isLogged, isTrue);
      expect(state.user?.nickname, '扫码用户');
      expect(state.qrPhase, QrPhase.success);

      // 再走 6 秒不应继续轮询（stopQrPolling 已取消 timer）。
      await tester.pump(const Duration(seconds: 6));
      expect(repo.polledKeys, ['qr-key-1']);
    });

    testWidgets('已扫码 / 已过期 两个中间态', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = (key: 'qr-key-1', contentUrl: 'https://qr/x')
        ..pollResult = (status: 2, session: null);
      final (container, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await flush(tester);
      expect(container.read(authControllerProvider).qrPhase, QrPhase.scanned);

      repo.pollResult = (status: 0, session: null);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await flush(tester);
      final state = container.read(authControllerProvider);
      expect(state.qrPhase, QrPhase.expired);
    });

    testWidgets('stopQrPolling 之后迟到的轮询结果被丢弃（代数守卫）', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = (key: 'qr-key-1', contentUrl: 'https://qr/x')
        ..pollResult = (status: 4, session: _session());
      final (container, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();
      await flush(tester);
      auth.stopQrPolling();

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      await flush(tester);

      expect(repo.polledKeys, isEmpty);
      expect(container.read(authControllerProvider).isLogged, isFalse);
    });

    testWidgets('重新发起二维码会取消上一轮轮询', (tester) async {
      final repo = _FakeLoginRepository()
        ..qrCreated = (key: 'qr-key-1', contentUrl: 'https://qr/x')
        ..pollResult = (status: 4, session: _session());
      final (_, _, auth) = await bootstrap(repo);

      await auth.startQrLogin();
      await tester.pump();
      await auth.startQrLogin();
      await tester.pump();

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      // 只有第二轮（key 相同但只跑一个 timer）在轮询。
      expect(repo.polledKeys, ['qr-key-1']);
    });
  });
}
