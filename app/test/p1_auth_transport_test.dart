import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugou/kugo_client.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/data/repositories/login_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/data/storage/credential_store.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/profile/user_profile_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancel,
  ) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(int code, String body, {String? cookie}) =>
    ResponseBody.fromString(
      body,
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        if (cookie != null) 'set-cookie': [cookie],
      },
    );

class _Repo extends LoginRepository {
  _Repo() : super(dio: Dio());
  @override
  Future<LoginSession?> loginWithPassword({
    required String username,
    required String password,
  }) async => LoginSession(userId: username, token: 'TOKEN_$username');

  @override
  Future<MyProfile?> fetchMyInfo({
    required String token,
    required String userId,
    String t1 = '',
  }) async => MyProfile(nickname: 'fixture', userId: userId);
}

Future<(ProviderContainer, AuthController)> _boot() async {
  final c = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => AuthController(repository: _Repo()),
      ),
    ],
  );
  addTearDown(c.dispose);
  final auth = c.read(authControllerProvider.notifier);
  await auth.ensureReady();
  return (c, auth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DeviceIdentity.reset();
    AuthTokenHolder.instance.clearDevice();
    SharedPreferences.setMockInitialValues({
      'kugo_device_dfid': 'fixture-dfid',
      'kugo_device_guid': 'fixture-guid',
      'kugo_device_mid': 'fixture-mid',
      'kugo_device_dev': 'kugoFlutter',
      'kugo_device_dfid_registered': true,
      'auth.user.v1': 'userId=100&nickname=fixture&token=TOKEN_100',
    });
  });
  tearDown(AuthTokenHolder.instance.clear);

  for (final accept401 in [false, true]) {
    test(
      'R11 current authenticated 401 synchronizes holder/UI/prefs (response=$accept401)',
      () async {
        final (c, _) = await _boot();
        final dio = Dio(
          BaseOptions(validateStatus: (code) => accept401 || code == 200),
        );
        final adapter = _Adapter((_) async => _response(401, '{"code":401}'));
        dio.httpClientAdapter = adapter;
        final client = KugoClient(dio: dio);
        try {
          await client.getJson('https://gateway.kugou.com/fixture');
        } catch (_) {}
        expect(AuthTokenHolder.instance.hasToken, isFalse);
        expect(c.read(authControllerProvider).isLogged, isFalse);
        // The HTTP interceptor initiates the controller's serialized disk clear.
        // Await an event-loop turn, not a second logout that could mask a defect.
        await Future<void>.delayed(Duration.zero);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth.user.v1'), isNull);
        expect(prefs.getBool('auth.guest.v1'), isTrue);
        expect(
          adapter.requests.single.headers['Authorization'],
          contains('TOKEN_100'),
        );
      },
    );
  }

  test(
    'R11 obsolete authenticated 401 cannot expire newly logged-in account',
    () async {
      final (c, auth) = await _boot();
      final entered = Completer<void>();
      final reply = Completer<ResponseBody>();
      final adapter = _Adapter((_) {
        entered.complete();
        return reply.future;
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final pending = KugoClient(dio: dio)
          .getJson('https://gateway.kugou.com/fixture')
          .catchError((Object _) => null);
      await entered.future;
      expect(
        await auth.loginWithPassword(username: '200', password: 'fixture'),
        isTrue,
      );
      reply.complete(_response(401, '{"code":401}'));
      await pending;
      expect(AuthTokenHolder.instance.token, 'TOKEN_200');
      expect(c.read(authControllerProvider).user!.userId, '200');
      expect(await CredentialStore.read('auth.user.v1'), contains('TOKEN_200'));
    },
  );

  test('R11 anonymous 401 does not expire current account', () async {
    final (c, _) = await _boot();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async => _response(401, '{}'));
    try {
      await KugoClient(dio: dio).getJson('https://example.invalid/fixture');
    } catch (_) {}
    expect(AuthTokenHolder.instance.token, 'TOKEN_100');
    expect(c.read(authControllerProvider).isLogged, isTrue);
  });

  test(
    'R11 repeated 401 notification happens once per credential generation',
    () {
      final holder = AuthTokenHolder.instance;
      holder.setSession(token: 'token', userId: '1');
      final generation = holder.generation;
      var count = 0;
      void listener() => count++;
      holder.addUnauthorizedListener(listener);
      try {
        holder.invalidate(generation);
        holder.invalidate(generation);
        expect(count, 1);
      } finally {
        holder.removeUnauthorizedListener(listener);
      }
    },
  );

  test(
    'R09 isolated QR request never sends persistent or Dio default cookies',
    () async {
      final adapter = _Adapter(
        (_) async => _response(
          200,
          '{"code":200,"unikey":"fixture-key"}',
          cookie: 'qr_nonce=fresh; Path=/',
        ),
      );
      final dio = Dio(BaseOptions(headers: {'cookie': 'MUSIC_U=DEFAULT_OLD'}))
        ..httpClientAdapter = adapter;
      final client = NeteaseClient(dio: dio)
        ..seedCookies({'MUSIC_U': 'OLD', '__csrf': 'OLD_CSRF'});
      final qr = await client.createQrSession();
      final request = adapter.requests.single;
      expect(
        request.headers.keys.any((k) => k.toLowerCase() == 'cookie'),
        isFalse,
      );
      expect(request.uri.queryParameters['csrf_token'], '');
      expect(client.cookies['MUSIC_U'], 'OLD');
      expect(client.cookies, isNot(contains('qr_nonce')));
      await client.pollQrLogin(qr);
      expect(adapter.requests.last.headers['Cookie'], 'qr_nonce=fresh');
      expect(adapter.requests.last.headers['Cookie'], isNot(contains('OLD')));
    },
  );

  test(
    'R09 no new credential cannot confirm existing account as QR success',
    () async {
      final client = NeteaseClient(dio: Dio())..seedCookies({'MUSIC_U': 'OLD'});
      expect(await client.confirmQrLogin(refreshToken: ''), isFalse);
      expect(client.cookies['MUSIC_U'], 'OLD');
    },
  );

  test(
    'R09 confirmed QR replaces old account and old CSRF rather than merging',
    () async {
      final adapter = _Adapter(
        (request) async => request.uri.path.contains('unikey')
            ? _response(200, '{"code":200,"unikey":"key"}')
            : _response(
                200,
                jsonEncode({
                  'code': 200,
                  'account': {'id': 200},
                }),
              ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = NeteaseClient(dio: dio)
        ..seedCookies({'MUSIC_U': 'OLD', '__csrf': 'OLD_CSRF'});
      await client.createQrSession();
      expect(await client.confirmQrLogin(refreshToken: 'NEW'), isTrue);
      expect(client.cookies['MUSIC_U'], 'NEW');
      expect(client.cookies['__csrf'], isNull);
      expect(adapter.requests.last.headers['Cookie'], contains('MUSIC_U=NEW'));
      expect(adapter.requests.last.headers['Cookie'], isNot(contains('OLD')));
    },
  );

  test(
    'R09 old QR response cookies cannot pollute a newer QR generation',
    () async {
      final firstEntered = Completer<void>();
      final firstResponse = Completer<ResponseBody>();
      var count = 0;
      final adapter = _Adapter((_) {
        count++;
        if (count == 1) {
          firstEntered.complete();
          return firstResponse.future;
        }
        return Future.value(_response(200, '{"code":200,"unikey":"second"}'));
      });
      final client = NeteaseClient(dio: Dio()..httpClientAdapter = adapter);
      final first = client.createQrSession();
      await firstEntered.future;
      final second = await client.createQrSession();
      firstResponse.complete(
        _response(
          200,
          '{"code":200,"unikey":"first"}',
          cookie: 'MUSIC_U=STALE; Path=/',
        ),
      );
      await first;
      await client.pollQrLogin(second);
      expect(adapter.requests.last.headers['Cookie'], isNull);
      expect(client.hasLogin, isFalse);
    },
  );

  test('R09 old QR session is rejected before sending a new request', () async {
    final adapter = _Adapter(
      (_) async => _response(200, '{"code":200,"unikey":"key"}'),
    );
    final client = NeteaseClient(dio: Dio()..httpClientAdapter = adapter);
    final old = await client.createQrSession();
    await client.createQrSession();
    expect((await client.pollQrLogin(old)).code, 800);
    expect(adapter.requests, hasLength(2));
    expect(
      await client.confirmQrLogin(
        refreshToken: 'STALE',
        generation: old.generation,
      ),
      isFalse,
    );
    expect(client.hasLogin, isFalse);
  });

  test('R09 logout invalidates in-flight QR response cookies', () async {
    final entered = Completer<void>();
    final response = Completer<ResponseBody>();
    final adapter = _Adapter((_) {
      entered.complete();
      return response.future;
    });
    final client = NeteaseClient(dio: Dio()..httpClientAdapter = adapter);
    final pending = client.createQrSession();
    await entered.future;
    client.clearLogin();
    response.complete(
      _response(
        200,
        '{"code":200,"unikey":"old"}',
        cookie: 'MUSIC_U=STALE; Path=/',
      ),
    );
    final old = await pending;
    expect((await client.pollQrLogin(old)).code, 800);
    expect(await client.confirmQrLogin(refreshToken: ''), isFalse);
    expect(client.hasLogin, isFalse);
  });

  test('R09 isolation preserves non-QR phone-login response cookies', () async {
    final adapter = _Adapter(
      (_) async =>
          _response(200, '{"code":200}', cookie: 'MUSIC_U=PHONE_NEW; Path=/'),
    );
    final client = NeteaseClient(dio: Dio()..httpClientAdapter = adapter)
      ..seedCookies({'MUSIC_U': 'OLD'});
    await client.loginByPhoneRaw('fixture-phone', 'fixture-password');
    expect(adapter.requests.single.headers['Cookie'], isNull);
    expect(client.cookies['MUSIC_U'], 'PHONE_NEW');
  });

  test(
    'R09 source does not report 803 as successful without new credentials',
    () async {
      var calls = 0;
      final adapter = _Adapter(
        (_) async => ++calls == 1
            ? _response(200, '{"code":200,"unikey":"key"}')
            : _response(200, '{"code":803}'),
      );
      final client = NeteaseClient(dio: Dio()..httpClientAdapter = adapter)
        ..seedCookies({'MUSIC_U': 'OLD'});
      final source = NeteaseSource(client: client);
      final session = await source.createLoginQr();
      expect((await source.pollLoginQr(session)).status, LoginQrStatus.expired);
      expect(client.cookies['MUSIC_U'], 'OLD');
    },
  );
}
