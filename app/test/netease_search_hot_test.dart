/// 网易热搜（N3）：映射与源层。
///
/// fixture 是 2026-09-27 真机实测响应（10 条），结构照抄。
///
/// 钉住两条：① 词在 **`result.hots[].first`**（网易的第三套包裹，别按惯性去
/// `data` 下找）；② `second` / `third` 不是热度值，**不编造热度**。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';

const String _hotJson = '''
{"code":200,"result":{"hots":[
  {"first":"华晨宇","second":1,"third":null,"iconType":1},
  {"first":"薛之谦","second":1,"third":null,"iconType":1},
  {"first":"孙天宇","second":1,"third":null,"iconType":1},
  {"first":"茶汤","second":1,"third":null,"iconType":1},
  {"first":"林俊杰","second":1,"third":null,"iconType":1},
  {"first":"刘欢","second":1,"third":null,"iconType":1},
  {"first":"孙燕姿","second":1,"third":null,"iconType":1},
  {"first":"琵琶曲","second":1,"third":null,"iconType":1},
  {"first":"失去你的痛","second":1,"third":null,"iconType":1},
  {"first":"许嵩","second":1,"third":null,"iconType":1}]}}
''';

const String _emptyJson = '{"code":200,"result":{"hots":[]}}';

/// 词缺 `first` 的畸形行：应被跳过而不是产出空字符串。
const String _partialJson = '''
{"code":200,"result":{"hots":[
  {"first":"许嵩","second":1},
  {"second":1,"third":null},
  {"first":"","second":1}]}}
''';

class _FakeClient extends NeteaseClient {
  String hotRaw = _hotJson;

  @override
  Future<String> searchHotRaw() async => hotRaw;
}

void main() {
  group('映射：E6 热搜', () {
    test('词在 result.hots[].first，共 10 条', () {
      final words = mapNeteaseSearchHot(_hotJson);
      expect(words, hasLength(10));
      expect(words.first, '华晨宇');
      expect(words.last, '许嵩');
    });

    test('空列表正常返回空', () {
      expect(mapNeteaseSearchHot(_emptyJson), isEmpty);
    });

    test('缺 first / 空词的行跳过，不留空字符串', () {
      expect(mapNeteaseSearchHot(_partialJson), ['许嵩']);
    });
  });

  group('源层', () {
    test('热搜走 weapi /weapi/search/hot + type=1111', () async {
      final client = _FakeClient();
      final source = NeteaseSource(client: client);
      final words = await source.hotKeywords();
      expect(words, hasLength(10));
    });

    test('count 只在更长时截断（网易固定 10 条，够用就原样返回）', () async {
      final source = NeteaseSource(client: _FakeClient());
      expect(await source.hotKeywords(count: 5), hasLength(5));
      expect(await source.hotKeywords(count: 20), hasLength(10));
    });

    test('取不到时给空列表，不抛异常（UI 自行收起区块）', () async {
      final source = NeteaseSource(client: _FakeClient()..hotRaw = '{');
      expect(await source.hotKeywords(), isEmpty);
    });
  });
}
