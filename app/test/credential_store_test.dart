import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/data/storage/bili_auth_store.dart';
import 'package:kugo/data/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _key = 'test.auth.v1';
const _secure = 'kugo.credentials.test.auth.v1';
const _blocked = 'test.auth.v1.secure.blocked.v1';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void useChannel() {
    FlutterSecureStoragePlatform.instance = MethodChannelFlutterSecureStorage();
  }

  test(
    'legacy credentials migrate and disappear from ordinary preferences',
    () async {
      SharedPreferences.setMockInitialValues({_key: 'old-secret'});
      expect(await CredentialStore.read(_key), 'old-secret');
      expect((await SharedPreferences.getInstance()).getString(_key), isNull);
      expect(await CredentialStore.read(_key), 'old-secret');
    },
  );

  test('new writes never persist plaintext', () async {
    await CredentialStore.write(_key, 'new-secret');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), isNull);
    expect(prefs.getBool(_blocked), isNull);
    expect(await CredentialStore.read(_key), 'new-secret');
  });

  test(
    'failed migration preserves legacy without authenticating from it',
    () async {
      SharedPreferences.setMockInitialValues({_key: 'old-secret'});
      useChannel();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (_) async {
            throw PlatformException(code: 'vault_locked');
          });
      await expectLater(
        CredentialStore.read(_key),
        throwsA(isA<PlatformException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(_key),
        'old-secret',
      );
    },
  );

  test('read-back mismatch keeps legacy and reports failure', () async {
    SharedPreferences.setMockInitialValues({_key: 'old-secret'});
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
    await expectLater(CredentialStore.read(_key), throwsStateError);
    expect(
      (await SharedPreferences.getInstance()).getString(_key),
      'old-secret',
    );
  });

  test('failed replacement blocks restoration of the prior account', () async {
    await CredentialStore.write(_key, 'old-secret');
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'write') {
            throw PlatformException(code: 'vault_locked');
          }
          return 'old-secret';
        });
    await expectLater(
      CredentialStore.write(_key, 'new-secret'),
      throwsA(isA<PlatformException>()),
    );
    expect(await CredentialStore.read(_key), isNull);
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
  });

  test('logout remains effective even when secure deletion fails', () async {
    await CredentialStore.write(_key, 'old-secret');
    SharedPreferences.setMockInitialValues({_key: 'old-plaintext'});
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'delete') {
            throw PlatformException(code: 'vault_locked');
          }
          return 'old-secret';
        });
    await expectLater(
      CredentialStore.clear(_key),
      throwsA(isA<PlatformException>()),
    );
    expect(await CredentialStore.read(_key), isNull);
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
  });

  test('logout is ordered after an already-started secure write', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final values = <String, String>{};
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'write':
              started.complete();
              await release.future;
              values[key] = args['value'] as String;
            case 'read':
              return values[key];
            case 'delete':
              values.remove(key);
          }
          return null;
        });
    final save = CredentialStore.write(_key, 'late-secret');
    await started.future;
    final logout = CredentialStore.clear(_key);
    release.complete();
    await Future.wait([save, logout]);
    expect(values[_secure], isNull);
    expect(await CredentialStore.read(_key), isNull);
  });

  test('failed operation does not poison later successful login', () async {
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async {
          throw PlatformException(code: 'vault_locked');
        });
    await expectLater(
      CredentialStore.write(_key, 'bad'),
      throwsA(isA<PlatformException>()),
    );
    final values = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          if (call.method == 'write') values[key] = args['value'] as String;
          if (call.method == 'read') return values[key];
          return null;
        });
    await CredentialStore.write(_key, 'good');
    expect(await CredentialStore.read(_key), 'good');
  });

  test(
    'logout guard is persisted before a stalled native save completes',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final values = <String, String>{};
      useChannel();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'] as String;
            if (call.method == 'write') {
              started.complete();
              await release.future;
              values[key] = args['value'] as String;
            }
            if (call.method == 'read') return values[key];
            if (call.method == 'delete') values.remove(key);
            return null;
          });
      final save = CredentialStore.write(_key, 'late-secret');
      await started.future;
      final logout = CredentialStore.clear(_key);
      // Drain guard persistence independently of the stalled native operation.
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 10 && prefs.getBool(_blocked) != true; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(prefs.getBool(_blocked), true);
      release.complete();
      await Future.wait([save, logout]);
      expect(prefs.getBool(_blocked), true);
      expect(await CredentialStore.read(_key), isNull);
    },
  );

  test('late Bilibili restore cannot revive cookies after logout', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final secureKey = 'kugo.credentials.${BiliAuthStore.key}';
    final values = {secureKey: '{"cookies":{"SESSDATA":"old"}}'};
    useChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          if (call.method == 'read') {
            if (!started.isCompleted) started.complete();
            await release.future;
            return values[key];
          }
          if (call.method == 'delete') values.remove(key);
          return null;
        });
    final client = BiliClient();
    final restore = BiliAuthStore.restoreInto(client);
    await started.future;
    final clear = BiliAuthStore.clear();
    release.complete();
    await Future.wait([restore, clear]);
    expect(client.cookies, isEmpty);
  });
}
