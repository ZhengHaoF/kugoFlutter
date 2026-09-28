import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/barrage.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/data/repositories/comment_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/mv/mv_barrage_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_music_source.dart';

/// 弹幕源：可控返回 + 记录调用（[FakeMusicSource] 本身不实现 MvBarrageSource）。
class _BarrageFakeSource extends FakeMusicSource implements MvBarrageSource {
  _BarrageFakeSource({this.items = const []});

  List<BarrageItem> items;
  int fetchCalls = 0;
  final List<String> sent = [];

  @override
  String get barrageError => '';

  @override
  Future<List<BarrageItem>> fetchMvBarrage(
    String hash, {
    int page = 1,
    int pageSize = 100,
  }) async {
    fetchCalls++;
    return items;
  }

  @override
  Future<void> sendMvBarrage({
    required String hash,
    required String content,
    String name = '',
    String videoId = '',
  }) async {
    sent.add(content);
  }
}

/// MV 视频弹幕的 `code`（VideoBarrage）。与歌曲弹幕 `articulossong` 不同池。
const String _videoCode = 'db3664c219a6e350b00ab08d7f723a79';

/// 按顺序吐预置响应体，记录每次请求。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final List<String> responses;
  final List<RequestOptions> seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final body = responses.isEmpty ? '{}' : responses.removeAt(0);
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

CommentRepository _repo(_ScriptedAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      validateStatus: (code) => code != null && code >= 200 && code < 500,
      responseType: ResponseType.plain,
    ),
  );
  dio.httpClientAdapter = adapter;
  return CommentRepository(dio: dio);
}

/// 真实响应形态：顶层平铺 `list` / `childrenid`。
const String _barrageJson = '''
{
  "status": 1,
  "err_code": 0,
  "childrenid": 987654,
  "list": [
    {"content": "前方高能", "user_id": 1072328892},
    {"content": "awsl", "user_id": "42"},
    {"content": "   ", "user_id": 1}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await DeviceIdentity.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kugo_device_dfid': '-',
      'kugo_device_guid': 'test-guid-0123456789abcdef',
      'kugo_device_mid': '1234567890',
      'kugo_device_dfid_registered': true,
    });
    AuthTokenHolder.instance.clear();
  });

  group('BarrageConfig — 归一化与落盘', () {
    test('默认值与 EchoMusic 一致', () {
      expect(BarrageConfig.defaults.opacity, 100);
      expect(BarrageConfig.defaults.fontSize, 17);
      expect(BarrageConfig.defaults.speed, 1);
      expect(BarrageConfig.defaults.area, 25);
      expect(BarrageConfig.defaults.density, 2);
    });

    test('越界值归一化到合法区间', () {
      final raw = const BarrageConfig(
        opacity: 5,
        fontSize: 99,
        speed: 9,
        area: 77,
        density: 9,
      ).normalized();
      expect(raw.opacity, 20);
      expect(raw.fontSize, 28);
      expect(raw.speed, 2);
      expect(raw.area, 25);
      expect(raw.density, 3);
    });

    test('encode / decode 往返；脏数据回落默认', () {
      const config = BarrageConfig(
        opacity: 60,
        fontSize: 20,
        speed: 1.25,
        area: 50,
        density: 3,
      );
      final back = BarrageConfig.decode(config.encode());
      expect(back.opacity, 60);
      expect(back.fontSize, 20);
      expect(back.speed, 1.25);
      expect(back.area, 50);
      expect(back.density, 3);

      expect(BarrageConfig.decode(null).opacity, 100);
      expect(BarrageConfig.decode('not json').opacity, 100);
      expect(BarrageConfig.decode('{"opacity":999}').opacity, 100);
    });
  });

  group('弹幕纯逻辑', () {
    test('normalizeBarrageUserId 只留正整数', () {
      expect(normalizeBarrageUserId(42), '42');
      expect(normalizeBarrageUserId('42'), '42');
      expect(normalizeBarrageUserId('007'), '');
      expect(normalizeBarrageUserId(0), '');
      expect(normalizeBarrageUserId('abc'), '');
      expect(normalizeBarrageUserId(null), '');
    });

    test('firstFreeBarrageLane 取第一条空轨；满则 -1', () {
      expect(firstFreeBarrageLane(const []), 0);
      expect(firstFreeBarrageLane(const [0, 2]), 1);
      expect(firstFreeBarrageLane(const [0, 1, 2, 3]), -1);
    });

    test('barrageTravelMs 与速度成反比', () {
      final normal = barrageTravelMs(
        containerWidth: 800,
        textWidth: 200,
        speed: 1,
      );
      expect(normal, 10000); // (800+200)/100 * 1000
      expect(
        barrageTravelMs(containerWidth: 800, textWidth: 200, speed: 2),
        normal ~/ 2,
      );
      // 非法速度按 1.0 处理。
      expect(
        barrageTravelMs(containerWidth: 800, textWidth: 200, speed: 0),
        normal,
      );
    });

    test('barrageIntervalMs：稀疏 > 适中 > 密集', () {
      expect(barrageIntervalMs(1), 4500);
      expect(barrageIntervalMs(2), 2800);
      expect(barrageIntervalMs(3), 1400);
    });
  });

  group('fetchMvBarrage — 视频弹幕读协议', () {
    test('GET index.php + x-router + 视频 code + extdata=hash，解析 content/user_id', () async {
      final adapter = _ScriptedAdapter([_barrageJson]);
      final repo = _repo(adapter);

      final items = await repo.fetchMvBarrage(hash: 'AABBCCDD');

      expect(items, hasLength(2)); // 第三条空内容被丢弃
      expect(items[0].text, '前方高能');
      expect(items[0].userId, '1072328892');
      expect(items[1].text, 'awsl');
      expect(items[1].userId, '42');
      expect(repo.barrageError, isEmpty);

      final req = adapter.seen.single;
      expect(req.method, 'GET');
      expect(req.uri.host, 'gateway.kugou.com');
      expect(req.uri.path, '/index.php');
      expect(req.headers['x-router'], 'm.comment.service.kugou.com');
      expect(req.queryParameters['r'], 'comments/getCommentWithLike');
      expect(req.queryParameters['code'], _videoCode);
      expect(req.queryParameters['extdata'], 'aabbccdd');
      expect(req.queryParameters['key'], isNotEmpty);
    });

    test('空 hash 直接返回空且不打网络', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      final items = await repo.fetchMvBarrage(hash: '  ');
      expect(items, isEmpty);
      expect(adapter.seen, isEmpty);
      expect(repo.barrageError, isNotEmpty);
    });

    test('status 非 1 时返回空 + barrageError', () async {
      final adapter = _ScriptedAdapter([
        '{"status":0,"err_code":20028,"msg":"风控"}',
      ]);
      final repo = _repo(adapter);
      final items = await repo.fetchMvBarrage(hash: 'abc');
      expect(items, isEmpty);
      expect(repo.barrageError, isNotEmpty);
    });
  });

  group('sendMvBarrage — 视频弹幕写协议', () {
    test('未登录抛 LoginRequired，不打网络', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      await expectLater(
        repo.sendMvBarrage(hash: 'abc', content: 'hi'),
        throwsA(isA<LoginRequired>()),
      );
      expect(adapter.seen, isEmpty);
    });

    test('只给 hash：先解析池，再 comments/addcomment（GET，正文在 query）', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      final adapter = _ScriptedAdapter([
        _barrageJson, // 解析池：返回 childrenid=987654
        '{"status":1,"error_code":0}', // 发送
      ]);
      final repo = _repo(adapter);

      await repo.sendMvBarrage(hash: 'AABBCCDD', content: ' 你好 ', name: '晴天 MV');

      expect(adapter.seen, hasLength(2));
      final resolve = adapter.seen[0];
      expect(resolve.queryParameters['code'], _videoCode);
      expect(resolve.queryParameters['pagesize'], isNotNull);

      final send = adapter.seen[1];
      expect(send.method, 'GET');
      expect(send.uri.path, '/index.php');
      expect(send.headers['x-router'], 'm.comment.service.kugou.com');
      expect(send.queryParameters['r'], 'comments/addcomment');
      expect(send.queryParameters['code'], _videoCode);
      expect(send.queryParameters['childrenid'], 987654);
      expect(send.queryParameters['childrenname'], '晴天 MV');
      expect(send.queryParameters['ver'], '1.02');
      expect(send.queryParameters['content'], '你好');
      expect(send.queryParameters['clienttoken'], 'tok');
      expect(send.queryParameters['kugouid'], 42);
    });

    test('已知 videoId 时跳过解析，只发一次', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      final adapter = _ScriptedAdapter(['{"status":1,"error_code":0}']);
      final repo = _repo(adapter);

      await repo.sendMvBarrage(
        hash: 'abc',
        content: 'hi',
        videoId: '987654',
      );

      expect(adapter.seen, hasLength(1));
      expect(adapter.seen.single.queryParameters['childrenid'], 987654);
    });

    test('空正文 / 超长正文在联网前拒绝', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);

      await expectLater(
        repo.sendMvBarrage(hash: 'abc', content: '   '),
        throwsA(isA<SourceFailure>()),
      );
      await expectLater(
        repo.sendMvBarrage(hash: 'abc', content: '字' * 101),
        throwsA(isA<SourceFailure>()),
      );
      expect(adapter.seen, isEmpty);
    });

    test('解析不到池时抛 NotFound', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      final adapter = _ScriptedAdapter([
        '{"status":1,"err_code":0,"list":[]}',
      ]);
      final repo = _repo(adapter);
      await expectLater(
        repo.sendMvBarrage(hash: 'abc', content: 'hi'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('MvBarrageLayer — 显隐、发射与暂停', () {
    tearDown(() => musicSourceRegistry = null);

    Future<void> pump(
      WidgetTester tester, {
      required bool enabled,
      required bool playing,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: MvBarrageLayer(
                hash: 'mvhash',
                enabled: enabled,
                playing: playing,
                config: BarrageConfig.defaults,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('关闭时不拉弹幕、不渲染', (tester) async {
      final src = _BarrageFakeSource(
        items: const [BarrageItem(text: '前方高能')],
      );
      musicSourceRegistry = MusicSourceRegistry([src]);

      await pump(tester, enabled: false, playing: true);
      await tester.pump(const Duration(milliseconds: 4000));

      expect(src.fetchCalls, 0);
      expect(find.text('前方高能'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('开启后按密度间隔发射；暂停时不发射', (tester) async {
      final src = _BarrageFakeSource(
        items: const [BarrageItem(text: '前方高能', userId: '1')],
      );
      musicSourceRegistry = MusicSourceRegistry([src]);

      await pump(tester, enabled: true, playing: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(src.fetchCalls, 1);

      // 暂停：间隔到了也不发射。
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.text('前方高能'), findsNothing);

      // 播放：下一 tick 发射。
      await pump(tester, enabled: true, playing: true);
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.text('前方高能'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}