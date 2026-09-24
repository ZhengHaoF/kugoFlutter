import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';
import 'package:kugo/data/storage/netease_auth_store.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_device_login_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('mapNeteaseQrStatus', () {
    test('800/801/802/803 映射', () {
      expect(mapNeteaseQrStatus(800), LoginQrStatus.expired);
      expect(mapNeteaseQrStatus(801), LoginQrStatus.waiting);
      expect(mapNeteaseQrStatus(802), LoginQrStatus.scanned);
      expect(mapNeteaseQrStatus(803), LoginQrStatus.confirmed);
    });

    test('未知码保持 unknown（不误判成功）', () {
      expect(mapNeteaseQrStatus(-1), LoginQrStatus.unknown);
      expect(mapNeteaseQrStatus(200), LoginQrStatus.unknown);
    });
  });

  group('NeteaseClient 扫码构造', () {
    test('chainId 格式 v1_<device>_web_login_<ms>', () {
      expect(
        NeteaseClient.buildLoginChainId(),
        matches(RegExp(r'^v1_unknown-\d+_web_login_\d{13}$')),
      );
    });

    test('chainId 使用传入的 sDeviceId', () {
      expect(
        NeteaseClient.buildLoginChainId(sDeviceId: 'abc'),
        startsWith('v1_abc_web_login_'),
      );
    });

    test('二维码内容是 scanlogin URL，不是裸 unikey', () {
      final url = NeteaseClient.buildScanLoginUrl('KEY', 'CHAIN');
      expect(url, startsWith('https://music.163.com/st/platform/scanlogin?'));
      expect(url, contains('codekey=KEY'));
      expect(url, contains('chainId=CHAIN'));
      expect(url, contains('hdw_device=web'));
      expect(url, contains('hdw_appid=web'));
      expect(url, contains('hitExp=1'));
    });

    test('mergeQrCredentialCookies 用 refresh token 顶替 MUSIC_U', () {
      final merged =
          NeteaseClient.mergeQrCredentialCookies({'__csrf': 'x'}, 'RT');
      expect(merged['MUSIC_U'], 'RT');
      expect(merged['__csrf'], 'x');
    });

    test('已有 MUSIC_U 时不被 refresh token 覆盖', () {
      final merged =
          NeteaseClient.mergeQrCredentialCookies({'MUSIC_U': 'real'}, 'RT');
      expect(merged['MUSIC_U'], 'real');
    });
  });

  group('mapNeteaseAccount', () {
    test('登录态解析 profile', () {
      const raw = '{"code":200,"account":{"id":1},"profile":'
          '{"userId":42,"nickname":"小明","avatarUrl":"http://x/a.jpg",'
          '"vipType":11}}';
      final a = mapNeteaseAccount(raw);
      expect(a, isNotNull);
      expect(a!.userId, '42');
      expect(a.nickname, '小明');
      expect(a.avatarUrl, startsWith('https://'));
      expect(a.isVip, isTrue);
    });

    test('游客态 / 坏响应返回 null', () {
      expect(mapNeteaseAccount('{"code":250,"account":null}'), isNull);
      expect(mapNeteaseAccount('{"code":200}'), isNull);
      expect(mapNeteaseAccount('not json'), isNull);
    });
  });

  group('NeteaseAuthStore', () {
    test('encode/decode 往返', () {
      final raw = NeteaseAuthStore.encode(
        {'MUSIC_U': 'abc', '__csrf': 'c'},
        savedAt: DateTime(2026, 1, 1),
      );
      expect(raw, isNotNull);
      final back = NeteaseAuthStore.decode(raw!);
      expect(back['MUSIC_U'], 'abc');
      expect(back['__csrf'], 'c');
    });

    test('无登录 cookie 不落盘 / 不还原', () {
      expect(NeteaseAuthStore.encode({'__csrf': 'c'}), isNull);
      expect(
        NeteaseAuthStore.decode('{"cookies":{"__csrf":"c"}}'),
        isEmpty,
      );
    });

    test('非法键值被拒收', () {
      final raw = NeteaseAuthStore.encode({
        'MUSIC_U': 'ok',
        'bad key': 'v',
        'has;semi': 'v',
        'ctrl': 'a\u0001b',
      });
      final back = NeteaseAuthStore.decode(raw!);
      expect(back['MUSIC_U'], 'ok');
      expect(back.containsKey('bad key'), isFalse);
      expect(back.containsKey('has;semi'), isFalse);
      expect(back.containsKey('ctrl'), isFalse);
    });

    test('坏 JSON 返回空 Map', () {
      expect(NeteaseAuthStore.decode('{'), isEmpty);
      expect(NeteaseAuthStore.decode('[]'), isEmpty);
      expect(NeteaseAuthStore.decode('{"cookies":"x"}'), isEmpty);
    });
  });

  group('NeteaseLoginController', () {
    ProviderContainer makeContainer(FakeDeviceLoginSource fake) {
      final container = ProviderContainer(
        overrides: [
          neteaseLoginSourceProvider.overrideWithValue(fake),
          neteaseLoginPollIntervalProvider
              .overrideWithValue(const Duration(milliseconds: 1)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// 等 [test] 成立，最多 2s。
    Future<void> waitFor(bool Function() test) async {
      for (var i = 0; i < 100 && !test(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('801 → 802 → 803 走到 success 并回填账号', () async {
      final fake = FakeDeviceLoginSource()
        ..script.addAll([
          LoginQrStatus.waiting,
          LoginQrStatus.scanned,
          LoginQrStatus.confirmed,
        ])
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final container = makeContainer(fake);
      NeteaseLoginState state() =>
          container.read(neteaseLoginControllerProvider);

      await container.read(neteaseLoginControllerProvider.notifier).startQr();
      expect(state().phase, NeteaseQrPhase.waiting);
      expect(state().qrContentUrl, contains('scanlogin'));

      await waitFor(() => state().phase == NeteaseQrPhase.success);
      expect(state().phase, NeteaseQrPhase.success);
      expect(state().account?.nickname, '小明');
    });

    test('800 过期后停止轮询', () async {
      final fake = FakeDeviceLoginSource()..script.add(LoginQrStatus.expired);
      final container = makeContainer(fake);
      NeteaseLoginState state() =>
          container.read(neteaseLoginControllerProvider);

      await container.read(neteaseLoginControllerProvider.notifier).startQr();
      await waitFor(() => state().phase == NeteaseQrPhase.expired);
      expect(state().phase, NeteaseQrPhase.expired);

      final calls = fake.pollCalls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fake.pollCalls, calls, reason: '过期后不应继续轮询');
    });

    test('建码失败 → error 并带错误文案', () async {
      final fake = FakeDeviceLoginSource()..createError = 'boom';
      final container = makeContainer(fake);
      NeteaseLoginState state() =>
          container.read(neteaseLoginControllerProvider);

      await container.read(neteaseLoginControllerProvider.notifier).startQr();
      expect(state().phase, NeteaseQrPhase.error);
      expect(state().errorMessage, isNotEmpty);
    });

    test('bootstrap 已登录时不重复扫码', () async {
      final fake = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '7', nickname: '已登录');
      final container = makeContainer(fake);

      await container.read(neteaseLoginControllerProvider.notifier).bootstrap();
      final s = container.read(neteaseLoginControllerProvider);
      expect(s.isLogged, isTrue);
      expect(fake.createCalls, 0);
    });

    test('logout 清状态并调用源登出', () async {
      final fake = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '7', nickname: '已登录');
      final container = makeContainer(fake);
      final notifier = container.read(neteaseLoginControllerProvider.notifier);

      await notifier.refreshAccount();
      expect(container.read(neteaseLoginControllerProvider).isLogged, isTrue);

      await notifier.logout();
      expect(container.read(neteaseLoginControllerProvider).isLogged, isFalse);
      expect(fake.logoutCalls, 1);
    });
  });
}
