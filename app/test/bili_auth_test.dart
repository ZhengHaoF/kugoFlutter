import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/api/bili/bili_qr_login.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';
import 'package:kugo/data/storage/bili_auth_store.dart';
import 'package:kugo/features/auth/bili_login_controller.dart';
import 'package:kugo/features/auth/bili_login_page.dart';

class FakeClient extends BiliClient {
  FakeClient() : super(dio: Dio());
  bool valid = true;
  @override
  Future<BiliAccount?> currentAccount() async =>
      valid && hasLogin ? const BiliAccount(mid: 42, uname: 'UP') : null;
}

class FakeQr extends BiliQrLoginClient {
  FakeQr() : super(dio: Dio());
  int code = 0;
  Map<String, String> result = {'SESSDATA': 'session', 'DedeUserID': '42'};
  Completer<BiliQrLoginPoll>? pending;
  @override
  Future<BiliQrLoginSession> createSession() async =>
      const BiliQrLoginSession(key: 'key', qrContent: 'https://qr.example');
  @override
  Future<BiliQrLoginPoll> pollLogin(BiliQrLoginSession session) async =>
      pending == null
      ? BiliQrLoginPoll(code: code, message: '', cookies: result)
      : pending!.future;
}

class FakeLogin implements DeviceLoginSource {
  LoginAccount? account;
  LoginQrStatus status = LoginQrStatus.waiting;
  int polls = 0;
  int concurrent = 0;
  int maxConcurrent = 0;
  Completer<LoginQrPoll>? pending;
  @override
  Future<LoginQrSession> createLoginQr() async =>
      const LoginQrSession(id: 'key', qrContent: 'https://qr.example');
  @override
  Future<LoginQrPoll> pollLoginQr(LoginQrSession session) async {
    polls++;
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    final result = pending == null
        ? LoginQrPoll(status: status)
        : await pending!.future;
    concurrent--;
    if (result.isConfirmed) {
      account = const LoginAccount(userId: '42', nickname: 'UP');
    }
    return result;
  }

  @override
  Future<LoginAccount?> currentAccount() async => account;
  @override
  Future<void> logout() async {
    account = null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('凭据解码拒绝损坏内容、非字符串值、无 SESSDATA', () {
    expect(BiliAuthStore.decode('bad'), isEmpty);
    expect(BiliAuthStore.decode('{"cookies":{"DedeUserID":"42"}}'), isEmpty);
    expect(BiliAuthStore.decode('{"cookies":{"SESSDATA":123}}'), isEmpty);
    expect(
      BiliAuthStore.decode(
        '{"cookies":{"SESSDATA":"ok","bad key":"x","x":"a;b","y":"a\\r\\nb"}}',
      ),
      {'SESSDATA': 'ok'},
    );
  });

  test('保存、重启恢复与清理只影响 B 站独立 key', () async {
    SharedPreferences.setMockInitialValues({'netease.auth.v1': 'other'});
    final c = FakeClient()..seedCookies({'SESSDATA': 'ok'});
    await BiliAuthStore.save(c);
    final restored = FakeClient();
    await BiliAuthStore.restoreInto(restored);
    expect(restored.hasLogin, isTrue);
    await BiliAuthStore.clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(BiliAuthStore.key), isNull);
    expect(prefs.getString('netease.auth.v1'), 'other');
  });

  test('扫码确认验证账号后持久化，切换账号不会混入旧 Cookie', () async {
    final c = FakeClient()..seedCookies({'SESSDATA': 'old', 'oldOnly': 'x'});
    final source = BiliSource(client: c, qrClient: FakeQr());
    final session = await source.createLoginQr();
    expect((await source.pollLoginQr(session)).isConfirmed, isTrue);
    expect(c.cookies.containsKey('oldOnly'), isFalse);
    expect((await source.currentAccount())!.userId, '42');
    await BiliAuthStore.save(c);
    final prefs = await SharedPreferences.getInstance();
    expect(
      BiliAuthStore.decode(prefs.getString(BiliAuthStore.key)!)['SESSDATA'],
      'session',
    );
    await source.logout();
    await BiliAuthStore.clear();
    expect(c.cookies, isEmpty);
    expect(prefs.containsKey(BiliAuthStore.key), isFalse);
  });

  test('确认码但没有凭据必须报错，不能生成假账号', () async {
    final qr = FakeQr()..result = {};
    final source = BiliSource(client: FakeClient(), qrClient: qr);
    final session = await source.createLoginQr();
    await expectLater(source.pollLoginQr(session), throwsException);
  });

  test('nav 校验失败不保存凭据', () async {
    final c = FakeClient()..valid = false;
    final source = BiliSource(client: c, qrClient: FakeQr());
    final session = await source.createLoginQr();
    await expectLater(source.pollLoginQr(session), throwsException);
    expect(
      (await SharedPreferences.getInstance()).containsKey(BiliAuthStore.key),
      isFalse,
    );
  });

  test('退出使在途轮询失效，旧结果不能重新写入 Cookie', () async {
    final qr = FakeQr()..pending = Completer<BiliQrLoginPoll>();
    final c = FakeClient();
    final source = BiliSource(client: c, qrClient: qr);
    final session = await source.createLoginQr();
    final poll = source.pollLoginQr(session);
    await source.logout();
    qr.pending!.complete(
      BiliQrLoginPoll(code: 0, message: '', cookies: qr.result),
    );
    expect((await poll).status, LoginQrStatus.expired);
    expect(c.hasLogin, isFalse);
  });

  test('刷新二维码使旧会话失效', () async {
    final source = BiliSource(client: FakeClient(), qrClient: FakeQr());
    final old = await source.createLoginQr();
    await source.createLoginQr();
    expect((await source.pollLoginQr(old)).status, LoginQrStatus.expired);
  });

  testWidgets('二维码页等待、扫码、过期、刷新', (tester) async {
    final source = FakeLogin();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biliLoginSourceProvider.overrideWithValue(source),
          biliLoginPollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
        child: const MaterialApp(home: BiliLoginPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('等待扫码'), findsOneWidget);
    source.status = LoginQrStatus.scanned;
    await tester.pump(const Duration(milliseconds: 15));
    await tester.pump();
    expect(find.text('已扫码，请在手机上确认'), findsOneWidget);
    source.status = LoginQrStatus.expired;
    await tester.pump(const Duration(milliseconds: 15));
    await tester.pump();
    expect(find.text('二维码已过期，请刷新'), findsOneWidget);
    final polls = source.polls;
    await tester.pump(const Duration(seconds: 1));
    expect(source.polls, polls);
    await tester.tap(find.text('刷新二维码'));
    await tester.pump();
    expect(find.text('等待扫码'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('轮询不重叠，离页停止，确认后回显账号', (tester) async {
    final source = FakeLogin()..pending = Completer<LoginQrPoll>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biliLoginSourceProvider.overrideWithValue(source),
          biliLoginPollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
        child: const MaterialApp(home: BiliLoginPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 15));
    await tester.pump(const Duration(seconds: 1));
    expect(source.polls, 1);
    expect(source.maxConcurrent, 1);
    source.pending!.complete(
      const LoginQrPoll(status: LoginQrStatus.confirmed),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('UID 42'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
