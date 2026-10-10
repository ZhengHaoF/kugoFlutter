import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/login_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/profile/user_profile_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _device = <String, Object>{
  'kugo_device_dfid': 'fixture-dfid',
  'kugo_device_guid': 'fixture-guid',
  'kugo_device_mid': 'fixture-mid',
  'kugo_device_dev': 'kugoFlutter',
  'kugo_device_dfid_registered': true,
};

class _Repo extends LoginRepository {
  _Repo() : super(dio: Dio());
  final gates = <String, Completer<MyProfile?>>{};
  final entered = <String, Completer<void>>{};
  Completer<LoginSession?>? loginGate;
  int profileCalls = 0;
  bool qrConfirmed = false;

  @override
  Future<MyProfile?> fetchMyInfo({
    required String token,
    required String userId,
    String t1 = '',
  }) async {
    profileCalls++;
    if (entered[token] case final gate?) {
      if (!gate.isCompleted) gate.complete();
    }
    return gates[token]?.future ??
        Future.value(MyProfile(nickname: 'new-$userId', userId: userId));
  }

  @override
  Future<LoginSession?> loginWithSms({
    required String mobile,
    required String code,
    String userid = '',
  }) async =>
      loginGate?.future ??
      Future.value(
        LoginSession(userId: userid, token: 'TOKEN_$userid', t1: 'T1_$userid'),
      );

  @override
  Future<LoginSession?> loginWithPassword({
    required String username,
    required String password,
  }) async =>
      loginGate?.future ??
      Future.value(LoginSession(userId: username, token: 'TOKEN_$username'));

  @override
  Future<({String key, String contentUrl})?> createQrLogin() async =>
      (key: 'fixture-key', contentUrl: 'https://example.invalid/qr');

  @override
  Future<({int status, LoginSession? session})?> checkQrLogin(
    String key,
  ) async => (
    status: qrConfirmed ? 4 : 1,
    session: qrConfirmed
        ? const LoginSession(userId: '200', token: 'TOKEN_200')
        : null,
  );
}

class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore(super.data) : super.withData();
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.auth.user.v1') {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

Future<(ProviderContainer, AuthController)> _boot(_Repo repo) async {
  final c = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => AuthController(repository: repo),
      ),
    ],
  );
  addTearDown(c.dispose);
  final auth = c.read(authControllerProvider.notifier);
  await auth.ensureReady();
  return (c, auth);
}

Future<void> _seed({bool logged = false}) async {
  SharedPreferences.setMockInitialValues({});
  await DeviceIdentity.reset();
  AuthTokenHolder.instance.clear();
  SharedPreferences.setMockInitialValues({
    ..._device,
    if (logged)
      'auth.user.v1': 'userId=100&nickname=old&token=TOKEN_100&t1=T1_100',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_seed);
  tearDown(AuthTokenHolder.instance.clear);

  for (final guest in [false, true]) {
    test(
      'R06 ${guest ? 'continueAsGuest' : 'logout'} wins over late profile refresh',
      () async {
        await _seed(logged: true);
        final repo = _Repo();
        repo.gates['TOKEN_100'] = Completer();
        final (c, auth) = await _boot(repo);
        final refresh = auth.refreshProfile();
        if (guest) {
          await auth.continueAsGuest();
        } else {
          await auth.logout();
        }
        repo.gates['TOKEN_100']!.complete(const MyProfile(nickname: 'late-A'));
        await refresh;
        expect(c.read(authControllerProvider).isLogged, false);
        expect(AuthTokenHolder.instance.hasToken, false);
        expect(
          (await SharedPreferences.getInstance()).getString('auth.user.v1'),
          isNull,
        );
      },
    );
  }

  test('late profile A cannot replace successful account B', () async {
    await _seed(logged: true);
    final repo = _Repo();
    repo.gates['TOKEN_100'] = Completer();
    final (c, auth) = await _boot(repo);
    final refresh = auth.refreshProfile();
    expect(
      await auth.loginWithSms(
        phone: '13800000000',
        code: '1234',
        userid: '200',
      ),
      true,
    );
    repo.gates['TOKEN_100']!.complete(const MyProfile(nickname: 'late-A'));
    await refresh;
    expect(c.read(authControllerProvider).user!.userId, '200');
    expect(AuthTokenHolder.instance.token, 'TOKEN_200');
    expect(AuthTokenHolder.instance.t1, 'T1_200');
    expect(
      (await SharedPreferences.getInstance()).getString('auth.user.v1'),
      contains('TOKEN_200'),
    );
  });

  test('logout wins over login profile enrichment', () async {
    final repo = _Repo();
    repo.gates['TOKEN_200'] = Completer();
    repo.entered['TOKEN_200'] = Completer();
    final (c, auth) = await _boot(repo);
    final login = auth.loginWithSms(
      phone: '13800000000',
      code: '1234',
      userid: '200',
    );
    await repo.entered['TOKEN_200']!.future;
    // A pending login must not expose its session to the global client.
    expect(AuthTokenHolder.instance.hasToken, false);
    await auth.logout();
    repo.gates['TOKEN_200']!.complete(const MyProfile(nickname: 'late-login'));
    expect(await login, false);
    expect(c.read(authControllerProvider).isLogged, false);
    expect(AuthTokenHolder.instance.hasToken, false);
    expect(
      (await SharedPreferences.getInstance()).getString('auth.user.v1'),
      isNull,
    );
  });

  for (final password in [false, true]) {
    test(
      'logout discards late ${password ? 'password' : 'SMS'} login response',
      () async {
        final repo = _Repo()..loginGate = Completer();
        final (c, auth) = await _boot(repo);
        final login = password
            ? auth.loginWithPassword(username: '200', password: 'fixture')
            : auth.loginWithSms(
                phone: '13800000000',
                code: '1234',
                userid: '200',
              );
        await auth.logout();
        repo.loginGate!.complete(
          const LoginSession(userId: '200', token: 'TOKEN_200'),
        );
        expect(await login, false);
        expect(repo.profileCalls, 0);
        expect(c.read(authControllerProvider).isLogged, false);
      },
    );
  }

  test('newer login wins when A profile completes after B', () async {
    final repo = _Repo();
    repo.gates['TOKEN_100'] = Completer();
    repo.entered['TOKEN_100'] = Completer();
    final (c, auth) = await _boot(repo);
    final first = auth.loginWithSms(
      phone: '13800000000',
      code: '1234',
      userid: '100',
    );
    await repo.entered['TOKEN_100']!.future;
    expect(
      await auth.loginWithSms(
        phone: '13800000000',
        code: '1234',
        userid: '200',
      ),
      true,
    );
    repo.gates['TOKEN_100']!.complete(const MyProfile(nickname: 'late-A'));
    expect(await first, false);
    expect(c.read(authControllerProvider).user!.userId, '200');
    expect(AuthTokenHolder.instance.token, 'TOKEN_200');
  });

  test('logout disk clear follows an already-started session save', () async {
    final original = SharedPreferencesStorePlatform.instance;
    final store = _DelayedStore({
      for (final e in _device.entries) 'flutter.${e.key}': e.value,
    });
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    final (c, auth) = await _boot(_Repo());
    final login = auth.loginWithSms(
      phone: '13800000000',
      code: '1234',
      userid: '200',
    );
    await store.started.future;
    final logout = auth.logout();
    expect(c.read(authControllerProvider).isLogged, false);
    store.release.complete();
    await Future.wait([login, logout]);
    expect((await store.getAll())['flutter.auth.user.v1'], isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('auth.user.v1'),
      isNull,
    );
    expect(AuthTokenHolder.instance.hasToken, false);
  });

  test('disposed controller cannot apply a late profile response', () async {
    await _seed(logged: true);
    final repo = _Repo();
    repo.gates['TOKEN_100'] = Completer();
    final c = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => AuthController(repository: repo),
        ),
      ],
    );
    final auth = c.read(authControllerProvider.notifier);
    await auth.ensureReady();
    final refresh = auth.refreshProfile();
    c.dispose();
    repo.gates['TOKEN_100']!.complete(const MyProfile(nickname: 'late'));
    await refresh;
    expect(
      (await SharedPreferences.getInstance()).getString('auth.user.v1'),
      contains('nickname=old'),
    );
  });

  testWidgets('logout wins over confirmed QR profile enrichment', (
    tester,
  ) async {
    final repo = _Repo()..qrConfirmed = true;
    repo.gates['TOKEN_200'] = Completer();
    final (c, auth) = await _boot(repo);
    await auth.startQrLogin();
    await tester.pump(const Duration(seconds: 3));
    await auth.logout();
    repo.gates['TOKEN_200']!.complete(const MyProfile(nickname: 'late-qr'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(c.read(authControllerProvider).isLogged, false);
    expect(AuthTokenHolder.instance.hasToken, false);
    expect(
      (await SharedPreferences.getInstance()).getString('auth.user.v1'),
      isNull,
    );
  });
}
