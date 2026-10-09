import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/device_repository.dart';

import 'fakes/fake_kugo_client.dart';

/// 设备注册 `/risk/v2/r_register_dev`。
///
/// 为什么重要：风控接口对陌生 `dfid` 直接回 `err_code=20028`，评论区/部分
/// 歌单接口会整体不可用。注册失败时 `DeviceIdentity` 会退回官方匿名值 `-`，
/// 所以这里每一条失败路径的 `lastError` 文案都是排障线索。
DeviceRepository _repoWith(ScriptedAdapter adapter) {
  // BaseOptions 必须和 DeviceRepository._createDio() 一致：responseType=bytes
  // 决定 res.data 是字节数组（否则 JSON 解码后 `utf8.decode` 会炸），
  // validateStatus 决定 4xx/5xx 不抛 DioException 而是走业务错误分支。
  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c >= 200 && c < 500,
    ),
  )..httpClientAdapter = adapter;
  return DeviceRepository(dio: dio);
}

void main() {
  group('请求形状', () {
    test('POST 到 userservice，query 带 dfid/appid/part 与 signature', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.json({'status': 1})]);
      await _repoWith(adapter).register(mid: 'mid-1', guid: 'guid-1');

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.host, 'userservice.kugou.com');
      expect(req.uri.path, '/risk/v2/r_register_dev');

      final q = req.queryParameters;
      // 匿名 dfid：官方接受的值，注册成功后才换成服务端颁发的。
      expect(q['dfid'], '-');
      expect(q['mid'], 'mid-1');
      expect(q['uuid'], '-');
      expect(q['part'], 1);
      expect(q['platid'], 1);
      expect(q['appid'], isA<int>());
      expect(q['clientver'], isA<int>());
      expect(q['clienttime'], isA<int>());
      // p 是 RSA 加密的 {aes, uid, token}；signature 覆盖 data 字段。
      expect((q['p'] as String), isNotEmpty);
      expect((q['signature'] as String), isNotEmpty);
    });

    test('请求头带风控标识与设备身份', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.json({'status': 1})]);
      await _repoWith(adapter).register(mid: 'mid-2', guid: 'guid-2');

      final h = adapter.requests.single.headers;
      expect(h['dfid'], '-');
      expect(h['mid'], 'mid-2');
      expect(h['clienttime'], isA<String>());
      expect(h['kg-rc'], '1');
      expect(h['kg-thash'], '5d816a0');
      expect(h['kg-rec'], '1');
      expect(h['kg-rf'], 'B9EDA08A64250DEFFBCADDEE00F8F25F');
      expect(h['User-Agent'], isNotEmpty);
    });

    test('请求体是 AES 加密串（非空、非 JSON）', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.json({'status': 1})]);
      await _repoWith(adapter).register(mid: 'm', guid: 'g');

      final body = adapter.requests.single.data;
      expect(body, isA<String>());
      expect((body as String).isNotEmpty, isTrue);
      expect(body.startsWith('{'), isFalse);
    });
  });

  group('响应解析', () {
    test('明文 JSON 成功 → 取出服务端颁发的身份', () async {
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({
          'status': 1,
          'data': {
            'dfid': 'server-dfid-xyz',
            'mid': 'server-mid',
            'guid': 'server-guid',
            'uuid': 'server-uuid',
            'serverDev': 'dev-1',
            'mac': 'AA:BB',
          },
        }),
      ]);

      final reg = await _repoWith(adapter).register(mid: 'm', guid: 'g');
      expect(reg, isNotNull);
      expect(reg!.dfid, 'server-dfid-xyz');
      expect(reg.mid, 'server-mid');
      expect(reg.guid, 'server-guid');
      expect(reg.uuid, 'server-uuid');
      expect(reg.serverDev, 'dev-1');
      expect(reg.mac, 'AA:BB');
    });

    test('status 为字符串 "1" 也算成功', () async {
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({'status': '1', 'data': {'dfid': 'd'}}),
      ]);
      final reg = await _repoWith(adapter).register(mid: 'm', guid: 'g');
      expect(reg?.dfid, 'd');
    });

    test('status != 1 → 带 errmsg 与 status 值', () async {
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({'status': 0, 'msg': '风控拒绝'}),
      ]);
      final repo = _repoWith(adapter);
      expect(await repo.register(mid: 'm', guid: 'g'), isNull);
      expect(repo.lastError, contains('风控拒绝'));
      expect(repo.lastError, contains('status=0'));
    });

    test('data 缺 dfid → 明确报「未返回 dfid」', () async {
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({'status': 1, 'data': {'mid': 'x'}}),
      ]);
      final repo = _repoWith(adapter);
      expect(await repo.register(mid: 'm', guid: 'g'), isNull);
      expect(repo.lastError, '设备注册未返回 dfid');
    });

    test('空响应体 → 「响应为空」', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.text('')]);
      final repo = _repoWith(adapter);
      expect(await repo.register(mid: 'm', guid: 'g'), isNull);
      expect(repo.lastError, '设备注册响应为空');
    });

    test('响应不是 JSON → 「无法解析」', () async {
      final adapter = ScriptedAdapter([ScriptedAdapter.text('<html>gateway deny</html>')]);
      final repo = _repoWith(adapter);
      expect(await repo.register(mid: 'm', guid: 'g'), isNull);
      expect(repo.lastError, '设备注册响应无法解析');
    });

    test('网络异常 → lastError 带 Dio 信息', () async {
      final adapter = ScriptedAdapter([
        DioException(requestOptions: RequestOptions(path: '/x')),
      ]);
      final repo = _repoWith(adapter);
      expect(await repo.register(mid: 'm', guid: 'g'), isNull);
      expect(repo.lastError, isNotEmpty);
    });

    test('lastError 在每次调用前被清空', () async {
      final adapter = ScriptedAdapter([
        ScriptedAdapter.json({'status': 0, 'msg': '第一次失败'}),
        ScriptedAdapter.json({'status': 1, 'data': {'dfid': 'ok'}}),
      ]);
      final repo = _repoWith(adapter);
      await repo.register(mid: 'm', guid: 'g');
      expect(repo.lastError, isNotEmpty);

      await repo.register(mid: 'm', guid: 'g');
      expect(repo.lastError, isEmpty);
    });
  });

  test('anonymousDfid 是官方匿名值 "-"', () {
    expect(DeviceRepository.anonymousDfid, '-');
  });
}
