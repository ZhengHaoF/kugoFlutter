import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugo_sign.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/repositories/comment_repository.dart';
import 'package:kugo/data/sources/kugou/kugou_source.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按顺序吐预置响应体，并记录每次请求，供断言 URL / 参数。
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

/// 真实响应形态（专辑 966846 实测）：顶层平铺，且**不带** classify / hot_word。
const String _resourceListJson = '''
{
  "status": 1,
  "err_code": 0,
  "message": "success",
  "count": 3923,
  "childrenid": 966846,
  "maxPage": 197,
  "current_page": 1,
  "list": [
    {
      "id": 9481741,
      "user_name": "范特西的床边故事",
      "user_id": 1072328892,
      "user_pic": "http://imge.kugou.com/kugouicon/165/a.jpg",
      "content": "真是什么人裂了都要碰瓷周杰伦",
      "addtime": "2021-12-01 10:00:00",
      "reply_num": 11,
      "like": {"count": 33512, "likenum": 33512}
    }
  ]
}
''';

/// 0 条评论的歌单（7845129 实测）：`childrenid` 仍在，列表为空。
const String _resourceEmptyJson = '''
{"status":1,"err_code":0,"count":0,"childrenid":7845129,"list":[]}
''';

const String _resourceFloorJson = '''
{
  "status": 1,
  "err_code": 0,
  "comments_num": 11,
  "list": [
    {
      "id": 901,
      "user_name": "DYA",
      "content": "周杰伦：你了不起//@范特西的床边故事:真是什么人",
      "addtime": "2021-12-02 09:00:00",
      "tid": 9481741,
      "like": {"likenum": 8}
    }
  ]
}
''';

CommentRepository _repo(_ScriptedAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      validateStatus: (code) => code != null && code >= 200 && code < 500,
    ),
  );
  dio.httpClientAdapter = adapter;
  return CommentRepository(dio: dio);
}

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

  // ── 读侧：端点与 code ──────────────────────────────────
  //
  // 歌单 / 专辑走 **B 组** `/m.comment.service/v1/cmtlist`，不是歌曲的
  // `/mcomment/v1/cmtlist` —— 这两条最容易串，所以逐个断言。

  test('歌单评论：走 B 组 cmtlist，带 PLAYLIST code 与 content_type/tag', () async {
    final adapter = _ScriptedAdapter([_resourceEmptyJson]);
    final repo = _repo(adapter);

    final page = await repo.fetchResourceComments(
      CommentResourceKind.playlist,
      resourceId: '7845129',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/m.comment.service/v1/cmtlist');
    expect(req.queryParameters['childrenid'], 7845129);
    expect(req.queryParameters['code'], 'ca53b96fe5a1d9c22d71c8f522ef7c4f');
    expect(req.queryParameters['content_type'], 0);
    expect(req.queryParameters['tag'], 5);
    // 与歌曲不同：这里**没有** mixsongid。
    expect(req.queryParameters['mixsongid'], isNull);
    expect(page.items, isEmpty);
    expect(page.childrenId, '7845129'); // 资源 id 本身就是评论池
  });

  test('专辑评论：同端点但换 ALBUM code，不带 content_type/tag', () async {
    final adapter = _ScriptedAdapter([_resourceListJson]);
    final repo = _repo(adapter);

    final page = await repo.fetchResourceComments(
      CommentResourceKind.album,
      resourceId: '966846',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/m.comment.service/v1/cmtlist');
    expect(req.queryParameters['code'], '94f1792ced1df89aa68a7939eaf2efca');
    expect(req.queryParameters['content_type'], isNull);
    expect(req.queryParameters['tag'], isNull);
    expect(page.items, hasLength(1));
    expect(page.total, 3923);
    expect(page.childrenId, '966846');
    expect(page.maxPage, 197);
    // 实测歌单 / 专辑响应不带筛选项 —— UI 据此不出 chips 行。
    expect(page.classifyList, isEmpty);
    expect(page.hotwordList, isEmpty);
  });

  test('楼层：走 B 组 hot_replylist，不是歌曲的 /mcomment/v1/', () async {
    final adapter = _ScriptedAdapter([_resourceFloorJson]);
    final repo = _repo(adapter);

    final replies = await repo.fetchResourceFloorReplies(
      CommentResourceKind.album,
      childrenId: '966846',
      rootCommentId: '9481741',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/m.comment.service/v1/hot_replylist');
    expect(req.queryParameters['childrenid'], 966846);
    expect(req.queryParameters['tid'], 9481741);
    expect(req.queryParameters['code'], '94f1792ced1df89aa68a7939eaf2efca');
    expect(replies, hasLength(1));
    expect(replies.first.content, contains('//@'));
  });

  test('评论数：用 childrenid 口径（不是 hash），且换对应的 code', () async {
    final adapter = _ScriptedAdapter(['{"7845129":42}']);
    final repo = _repo(adapter);

    final count = await repo.fetchResourceCommentCount(
      CommentResourceKind.playlist,
      '7845129',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/index.php');
    expect(req.queryParameters['r'], 'comments/getcommentsnum');
    expect(req.queryParameters['childrenid'], '7845129');
    expect(req.queryParameters['hash'], isNull);
    expect(req.queryParameters['code'], 'ca53b96fe5a1d9c22d71c8f522ef7c4f');
    expect(req.headers['x-router'], 'sum.comment.service.kugou.com');
    expect(count, 42);
  });

  test('资源 id 缺失：不请求，给可读文案', () async {
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    final page = await repo.fetchResourceComments(
      CommentResourceKind.album,
      resourceId: ' ',
    );

    expect(adapter.seen, isEmpty);
    expect(page.items, isEmpty);
    expect(repo.lastError, contains('缺少资源 ID'));
  });

  // ── 写侧 ────────────────────────────────────────────────

  void login() =>
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');

  test('发歌单评论：commentsv3/add + 资源 code，body 不带 album_audio_id',
      () async {
    login();
    final adapter = _ScriptedAdapter(['{"status":1,"err_code":0}']);
    final repo = _repo(adapter);

    await repo.sendResourceComment(
      CommentResourceKind.playlist,
      childrenId: '7845129',
      content: ' 好听 ',
      resourceName: '我的歌单',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/index.php');
    expect(req.queryParameters['r'], 'commentsv3/add');
    expect(req.queryParameters['code'], 'ca53b96fe5a1d9c22d71c8f522ef7c4f');
    expect(req.queryParameters['childrenid'], 7845129);
    expect(req.queryParameters['childrenname'], '我的歌单');
    // 与歌曲的关键差异：**没有** mixsongid / album_audio_id。
    expect(req.queryParameters['mixsongid'], isNull);
    expect(req.data, '{"data":{"content":"好听"}}');

    final device = await DeviceIdentity.ensure();
    final ct = req.queryParameters['clienttime'] as int;
    expect(
      req.queryParameters['key'],
      KugoSign.signParamsKey('$ct${device.mid}{"data":{"content":"好听"}}'),
    );
  });

  test('回复歌单楼层：commentsv2/reply，key 不含 body', () async {
    login();
    final adapter = _ScriptedAdapter(['{"status":1,"err_code":0}']);
    final repo = _repo(adapter);

    await repo.sendResourceFloorReply(
      CommentResourceKind.album,
      childrenId: '966846',
      rootCommentId: '9481741',
      content: '同意',
      replyToUser: '范特西的床边故事',
      replyToContent: '真是什么人',
    );

    final req = adapter.seen.single;
    expect(req.queryParameters['r'], 'commentsv2/reply');
    expect(req.queryParameters['tid'], 9481741);
    expect(req.queryParameters['is_t'], 1);
    expect(req.queryParameters['pid'], 0);
    expect(req.queryParameters['mixsongid'], isNull);
    // 引用格式：与歌曲楼层一致。
    expect(
      req.queryParameters['content'],
      '同意//@范特西的床边故事:真是什么人',
    );
    expect(req.data, ''); // 回复走 query，body 为空串

    final device = await DeviceIdentity.ensure();
    final ct = req.queryParameters['clienttime'] as int;
    expect(
      req.queryParameters['key'],
      KugoSign.signParamsKey('$ct${device.mid}'),
    );
  });

  test('发歌单评论：未登录直接抛 LoginRequired，不发请求', () async {
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendResourceComment(
        CommentResourceKind.playlist,
        childrenId: '7845129',
        content: '你好',
      ),
      throwsA(isA<LoginRequired>()),
    );
    expect(adapter.seen, isEmpty);
  });

  // ── 源层：kind 分派 ────────────────────────────────────

  test('KugouSource 把 kind 原样传给 repository（不自己做 code 计算）', () async {
    final adapter = _ScriptedAdapter([
      _resourceEmptyJson,
      _resourceListJson,
    ]);
    final source = KugouSource(commentRepository: _repo(adapter));

    await source.resourceComments(
      CommentResourceKind.playlist,
      resourceId: '7845129',
    );
    await source.resourceComments(
      CommentResourceKind.album,
      resourceId: '966846',
    );

    expect(adapter.seen, hasLength(2));
    expect(
      adapter.seen.first.queryParameters['code'],
      'ca53b96fe5a1d9c22d71c8f522ef7c4f',
    );
    expect(
      adapter.seen.last.queryParameters['code'],
      '94f1792ced1df89aa68a7939eaf2efca',
    );
  });

  test('KugouSource 资源 id 为空：不请求，文案可读', () async {
    final adapter = _ScriptedAdapter([]);
    final source = KugouSource(commentRepository: _repo(adapter));

    final page = await source.resourceComments(
      CommentResourceKind.album,
      resourceId: '0',
    );

    expect(adapter.seen, isEmpty);
    expect(page.items, isEmpty);
    expect(source.resourceCommentError, contains('缺少资源 ID'));
  });

  test('歌单 0 条评论时仍带出评论池 id（否则发评论会误报「评论池未知」）',
      () async {
    final adapter = _ScriptedAdapter([_resourceEmptyJson]);
    final source = KugouSource(commentRepository: _repo(adapter));

    final page = await source.resourceComments(
      CommentResourceKind.playlist,
      resourceId: '7845129',
    );

    expect(page.items, isEmpty);
    expect(page.childrenId, isNotEmpty);
  });
}
