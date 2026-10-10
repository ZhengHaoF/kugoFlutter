import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugou/credential_transport.dart';
import 'package:kugo/core/api/kugou/kugo_client.dart';
import 'package:kugo/core/api/network_log.dart';
import 'package:kugo/data/repositories/login_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_kugo_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    AuthTokenHolder.instance.clearDevice();
    SharedPreferences.setMockInitialValues({});
    await DeviceIdentity.reset();
    SharedPreferences.setMockInitialValues({
      'kugo_device_dfid': 'fixture-dfid',
      'kugo_device_guid': 'fixture-guid',
      'kugo_device_mid': 'fixture-mid',
      'kugo_device_dev': 'kugoFlutter',
      'kugo_device_dfid_registered': true,
    });
  });
  tearDown(AuthTokenHolder.instance.clearDevice);

  group('R10 centralized log safety', () {
    NetworkLog log({
      String? url,
      dynamic body,
      Map<String, dynamic>? headers,
      String? error,
      String? id,
    }) => NetworkLog(
      id: id ?? 'fixture',
      type: NetworkLogType.response,
      timestamp: DateTime(2026),
      method: 'GET',
      url: url ?? 'https://gateway.kugou.com/fixture',
      headers: headers,
      data: body,
      errorMessage: error,
    );

    test(
      'query, duplicate keys, fragment, userinfo and internal id are safe',
      () {
        const secret = 'AUDIT_FAKE_URL_SECRET';
        const url =
            'https://user:$secret@gateway.kugou.com/fixture'
            '?%74oken=$secret&token=$secret&page=2#access_token=$secret';
        final record = log(url: url, id: '123-$url');
        expect(record.url, isNot(contains(secret)));
        expect(record.id, isNot(contains(secret)));
        expect(record.toCopyText(), isNot(contains(secret)));
        expect(Uri.parse(record.url).queryParameters['page'], '2');
      },
    );

    test('nested maps and lists are immutable sanitized snapshots', () {
      final body = <String, dynamic>{
        'data': [
          {
            'SESSDATA': 'AUDIT_FAKE_BILI',
            'MUSIC_U': 'AUDIT_FAKE_NETEASE',
            'count': 3,
          },
        ],
        'status': 200,
      };
      final record = log(
        body: body,
        headers: {
          'Authorization': 'AUDIT_FAKE_AUTH',
          'Set-Cookie': 'AUDIT_FAKE_COOKIE',
          'x-refresh-token': 'AUDIT_FAKE_REFRESH',
          'Accept': 'application/json',
        },
      );
      (body['data'] as List).add({'token': 'AUDIT_FAKE_LATE_MUTATION'});
      expect(record.toCopyText(), isNot(contains('AUDIT_FAKE')));
      expect((record.data as Map)['status'], 200);
      expect(record.headers!['Accept'], 'application/json');
      expect(
        () => (record.data as Map)['token'] = 'new',
        throwsUnsupportedError,
      );
    });

    for (final body in [
      '{"data":{"token":"AUDIT_FAKE_JSON"},"code":200}',
      'token=AUDIT_FAKE_FORM&page=1',
      '%74%6f%6b%65%6e=AUDIT_FAKE_ENCODED&page=2',
      '{"token":"AUDIT_FAKE_INCOMPLETE",',
      '{token: AUDIT_FAKE_MAP_TEXT, ok: 1}',
    ]) {
      test('body format ${body.substring(0, 12)} is redacted', () {
        expect(log(body: body).toCopyText(), isNot(contains('AUDIT_FAKE')));
      });
    }

    test(
      'ordinary HTML percent text never breaks business response logging',
      () {
        final body = {'title': '<em class="keyword">100% 测试</em>', 'code': 200};
        final record = log(body: body);
        expect((record.data as Map)['code'], 200);
        expect(body['title'], '<em class="keyword">100% 测试</em>');
      },
    );

    test('malformed encoded form fails closed without throwing', () {
      final record = log(body: 'token=%GG');
      expect(record.toCopyText(), isNot(contains('%GG')));
    });

    test('malformed credential URL fails closed without throwing', () {
      final record = log(url: 'https://gateway.kugou.com/a?token=%GG');
      expect(record.url, isNot(contains('GG')));
      expect(Uri.parse(record.url).queryParameters['token'], '***');
    });

    test('provider signed media URLs are scrubbed before storage', () {
      final record = log(
        body: {
          'url':
              'https://cdn.example/play?upsig=AUDIT_FAKE_UPSIG'
              '&w_rid=AUDIT_FAKE_WRID&sign=AUDIT_FAKE_SIGN',
        },
      );
      expect(record.data.toString(), isNot(contains('AUDIT_FAKE')));
    });

    test('encoded secret keys in error assignments are scrubbed', () {
      final record = log(error: '%74oken=AUDIT_FAKE_ENCODED_ERROR');
      expect(record.errorMessage, isNot(contains('AUDIT_FAKE')));
    });

    test('secrets embedded in diagnostic map keys are scrubbed', () {
      final record = log(body: {'token=AUDIT_FAKE_KEY': 'value'});
      expect(record.data.toString(), isNot(contains('AUDIT_FAKE')));
    });

    test('redaction precedes truncation', () {
      final record = log(
        body: {'token': 'AUDIT_FAKE_${'x' * 4000}', 'count': 1},
      );
      expect(record.toCopyText(), isNot(contains('AUDIT_FAKE')));
      expect((record.data as Map)['count'], 1);
    });

    test(
      'authentication payloads are omitted even for opaque unknown fields',
      () {
        final record = log(
          url: 'https://music.163.com/weapi/login/qrcode/unikey',
          body: {'unknown_name': 'AUDIT_FAKE_OPAQUE'},
        );
        expect(record.data, '[认证接口内容已省略]');
        expect(record.toCopyText(), isNot(contains('AUDIT_FAKE')));
      },
    );

    test('error text redacts URLs, bearer and credential header lines', () {
      final record = log(
        error:
            'failure https://gateway.kugou.com/a?token=AUDIT_FAKE_QUERY\n'
            'Cookie: SESSDATA=AUDIT_FAKE_COOKIE; custom=AUDIT_FAKE_CUSTOM\n'
            'Bearer AUDIT_FAKE_BEARER',
      );
      expect(record.errorMessage, isNot(contains('AUDIT_FAKE')));
    });
  });

  group('R01 credential transport', () {
    for (final fixture in [
      (
        url: 'http://gateway.kugou.com/a',
        headers: <String, dynamic>{},
        query: {'token': 'AUDIT_FAKE'},
      ),
      (
        url: 'http://gateway.kugou.com/a',
        headers: <String, dynamic>{'Authorization': 'AUDIT_FAKE'},
        query: <String, String>{},
      ),
      (
        url: 'https://kugou.com.attacker.invalid/a',
        headers: <String, dynamic>{'Cookie': 'AUDIT_FAKE'},
        query: <String, String>{},
      ),
      (
        url: 'https://attacker.invalid/a',
        headers: <String, dynamic>{},
        query: {'token': 'AUDIT_FAKE'},
      ),
    ]) {
      test('blocks ${fixture.url} before the adapter sends it', () async {
        final adapter = ScriptedAdapter([ScriptedAdapter.json({})]);
        final dio = Dio()..httpClientAdapter = adapter;
        installKugouCredentialGuard(dio);
        await expectLater(
          dio.get<dynamic>(
            fixture.url,
            queryParameters: fixture.query,
            options: Options(headers: fixture.headers),
          ),
          throwsA(isA<DioException>()),
        );
        expect(adapter.requests, isEmpty);
        dio.close();
      });
    }

    test('secure auth request cannot follow redirects', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.json({})]);
      final dio = Dio()..httpClientAdapter = adapter;
      installKugouCredentialGuard(dio);
      await dio.post<dynamic>(
        'https://gateway.kugou.com/a',
        data: jsonEncode({'token': 'AUDIT_FAKE_BODY'}),
      );
      expect(adapter.requests.single.followRedirects, false);
      expect(adapter.requests.single.maxRedirects, 0);
      dio.close();
    });

    test('public HTTP media has no auto-injected account header', () async {
      AuthTokenHolder.instance.setSession(token: 'AUDIT_FAKE', userId: '123');
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({'status': 1}),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      await KugoClient(dio: dio).getJson('http://mobilecdn.kugou.com/public');
      expect(adapter.requests.single.headers['Authorization'], isNull);
      dio.close();
    });

    test(
      'HTTPS non-account host also has no auto-injected account header',
      () async {
        AuthTokenHolder.instance.setSession(token: 'AUDIT_FAKE', userId: '123');
        final adapter = ScriptedAdapter([ScriptedAdapter.json({})]);
        final dio = Dio()..httpClientAdapter = adapter;
        await KugoClient(dio: dio).getJson('https://www.baidu.com/fixture');
        expect(adapter.requests.single.headers['Authorization'], isNull);
        dio.close();
      },
    );

    test(
      'trusted gateway receives auth but its diagnostic record does not',
      () async {
        AuthTokenHolder.instance.setSession(token: 'AUDIT_FAKE', userId: '123');
        final adapter = ScriptedAdapter([
          ScriptedAdapter.json({'token': 'AUDIT_FAKE_RESPONSE'}),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final records = <NetworkLog>[];
        await KugoClient(dio: dio, onLog: records.add).getJson(
          'https://gateway.kugou.com/fixture',
          query: {'token': 'AUDIT_FAKE_QUERY'},
        );
        expect(
          adapter.requests.single.headers['Authorization'],
          contains('AUDIT_FAKE'),
        );
        expect(adapter.requests.single.followRedirects, false);
        for (final record in records) {
          expect(record.toCopyText(), isNot(contains('AUDIT_FAKE')));
        }
        dio.close();
      },
    );

    test(
      'profile uses only HTTPS usercenter and VIP, never legacy hosts',
      () async {
        final adapter = ScriptedAdapter([
          ScriptedAdapter.json({
            'status': 1,
            'data': {'nickname': 'fixture', 'userid': 123},
          }),
          ScriptedAdapter.json({'status': 1, 'data': {}}),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final profile = await LoginRepository(
          dio: dio,
        ).fetchMyInfo(token: 'AUDIT_FAKE_PROFILE', userId: '123');
        expect(profile, isNotNull);
        expect(adapter.requests.length, 2);
        for (final request in adapter.requests) {
          expect(request.uri.scheme, 'https');
          expect(request.followRedirects, false);
          expect(request.uri.host, isNot(contains('relation.user')));
          expect(request.uri.host, isNot(contains('userinfo.user')));
        }
        dio.close();
      },
    );

    test(
      'SMS gateway route is TLS-only and does not perform a real send',
      () async {
        final adapter = ScriptedAdapter([
          ScriptedAdapter.json({'status': 1}),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        expect(
          await LoginRepository(dio: dio).sendSmsCode('13800000000'),
          true,
        );
        final request = adapter.requests.single;
        expect(request.uri.scheme, 'https');
        expect(request.uri.host, 'gateway.kugou.com');
        expect(request.headers['x-router'], 'login.user.kugou.com');
        expect(request.followRedirects, false);
        dio.close();
      },
    );

    test(
      'new profile t1 never borrows the previous account credential',
      () async {
        AuthTokenHolder.instance.setSession(
          token: 'TOKEN_A',
          userId: '100',
          t1: 'T1_A',
        );
        final adapter = ScriptedAdapter([
          ScriptedAdapter.json({
            'status': 1,
            'data': {'nickname': 'B'},
          }),
          ScriptedAdapter.json({'status': 1, 'data': {}}),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        await LoginRepository(
          dio: dio,
        ).fetchMyInfo(token: 'TOKEN_B', userId: '200', t1: 'T1_B');
        for (final request in adapter.requests) {
          expect(request.headers['Authorization'], contains('t1=T1_B'));
          expect(request.headers['Authorization'], isNot(contains('T1_A')));
        }
        expect(AuthTokenHolder.instance.token, 'TOKEN_A');
        dio.close();
      },
    );

    test(
      'TLS transport failure has no HTTP retry or certificate bypass',
      () async {
        final adapter = ScriptedAdapter([
          DioException(
            requestOptions: RequestOptions(path: '/fixture'),
            type: DioExceptionType.badCertificate,
            message: 'fixture TLS failure',
          ),
          ScriptedAdapter.json({}),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        await LoginRepository(
          dio: dio,
        ).fetchMyInfo(token: 'AUDIT_FAKE', userId: '123');
        expect(adapter.requests.length, 2);
        expect(adapter.requests.every((r) => r.uri.scheme == 'https'), true);
        dio.close();
      },
    );

    test(
      'upload origin upgrades known HTTP host and rejects arbitrary targets',
      () {
        expect(
          secureKugouUploadBase('http://bssulbig.kugou.com'),
          'https://bssulbig.kugou.com',
        );
        for (final host in [
          'https://evil.invalid',
          'file:///tmp',
          'https://user:pass@kugou.com',
          'https://bssulbig.kugou.com?token=x',
        ]) {
          expect(() => secureKugouUploadBase(host), throwsStateError);
        }
      },
    );
  });
}
