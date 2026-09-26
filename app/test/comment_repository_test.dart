import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugo_sign.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/repositories/comment_repository.dart';
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

/// 真实响应形态：**顶层平铺**（`list` / `count` / `childrenid` 都在顶层）。
const String _cmtListJson = '''
{
  "status": 1,
  "err_code": 0,
  "message": "success",
  "count": 706580,
  "childrenid": 20505418,
  "maxPage": 5000,
  "current_page": 1,
  "list": [
    {
      "id": 1723639894,
      "user_name": "屿知",
      "user_id": 1072328892,
      "user_pic": "http://imge.kugou.com/kugouicon/165/a.jpg",
      "content": "听《晴天》已听3000多遍了",
      "addtime": "2025-12-26 19:46:04",
      "location": "山东",
      "reply_num": 398,
      "like": {"count": 33512, "likenum": 33512, "haslike": false}
    },
    {
      "id": 1168471301,
      "user_name": "小明",
      "content": "很好听",
      "addtime": "1704153600",
      "reply_num": 0,
      "like_num": 4396
    }
  ]
}
''';

const String _topLikedJson = '''
{
  "status": 1,
  "err_code": 0,
  "count": 706580,
  "childrenid": 20505418,
  "list": [
    {
      "id": 315129160,
      "user_name": "热评用户",
      "content": "最热的一条",
      "addtime": "2024-05-01 10:00:00",
      "reply_num": 12,
      "like": {"likenum": 122115}
    }
  ]
}
''';

const String _floorJson = '''
{
  "status": 1,
  "err_code": 0,
  "comments_num": 398,
  "list": [
    {
      "id": 901,
      "user_name": "DYA",
      "content": "我1.2万遍晴天//@屿知:听《晴天》",
      "addtime": "2025-12-27 09:00:00",
      "is_reply": 1,
      "tid": 1723639894,
      "pid": 0,
      "like": {"likenum": 8}
    }
  ]
}
''';

const String _emptyJson =
    '{"status":1,"err_code":0,"count":0,"childrenid":20505418,"list":[]}';

const String _badParamJson = '{"status":0,"err_code":10002,"msg":"参数错误"}';

const String _ssaJson = '{"status":0,"err_code":20028,"msg":"security check"}';

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
    // registered=true → 跳过设备注册（否则测试会真的打网络）。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kugo_device_dfid': '-',
      'kugo_device_guid': 'test-guid-0123456789abcdef',
      'kugo_device_mid': '1234567890',
      'kugo_device_dfid_registered': true,
    });
    AuthTokenHolder.instance.clear();
  });

  test('cmtlist: 解析平铺响应并带出评论池', () async {
    final adapter = _ScriptedAdapter([_cmtListJson]);
    final repo = _repo(adapter);

    final page = await repo.fetchSongComments(mixSongId: '32100650');

    expect(page.items.length, 2);
    expect(page.total, 706580);
    expect(page.childrenId, '20505418');
    expect(page.maxPage, 5000);

    final first = page.items.first;
    expect(first.id, '1723639894');
    expect(first.user, '屿知');
    expect(first.userId, '1072328892');
    expect(first.likeCount, 33512);
    expect(first.replyCount, 398);
    expect(first.location, '山东');
    expect(first.timeLabel, '2025-12-26');
    expect(first.hasReplies, isTrue);

    final second = page.items[1];
    expect(second.likeCount, 4396); // like_num 扁平字段
    expect(second.hasReplies, isFalse);

    final req = adapter.seen.single;
    expect(req.uri.path, '/mcomment/v1/cmtlist');
    expect(req.method, 'POST');
    expect(req.queryParameters['mixsongid'], 32100650);
    expect(req.queryParameters['code'], 'fc4be23b4e972707f36b8a828a93ba8a');
    expect(req.queryParameters['p'], 1);
    expect(req.queryParameters['pagesize'], 20);
    expect((req.queryParameters['signature'] as String).length, 32);
  });

  test('hottest: 走 topLiked 路径并带评论池 id', () async {
    final adapter = _ScriptedAdapter([_cmtListJson, _topLikedJson]);
    final repo = _repo(adapter);

    await repo.fetchSongComments(mixSongId: '32100650'); // 先缓存 childrenid
    final hot = await repo.fetchSongComments(
      mixSongId: '32100650',
      sort: CommentSort.hottest,
    );

    expect(hot.items.single.likeCount, 122115);
    expect(adapter.seen.length, 2);
    final req = adapter.seen.last;
    expect(req.uri.path, '/m.comment.service/r/v1/rank/topliked');
    expect(req.queryParameters['childrenid'], '20505418');
  });

  test('hottest: 未缓存评论池时先用 cmtlist 垫一次', () async {
    final adapter = _ScriptedAdapter([_cmtListJson, _topLikedJson]);
    final repo = _repo(adapter);

    final hot = await repo.fetchSongComments(
      mixSongId: '32100650',
      sort: CommentSort.hottest,
    );

    expect(hot.items.single.user, '热评用户');
    expect(adapter.seen.length, 2);
    expect(adapter.seen.first.uri.path, '/mcomment/v1/cmtlist');
    expect(adapter.seen.first.queryParameters['pagesize'], 1);
    expect(adapter.seen.last.uri.path, '/m.comment.service/r/v1/rank/topliked');
  });

  test('最热响应缺 childrenid 时用已知评论池补齐', () async {
    final adapter = _ScriptedAdapter([
      _cmtListJson,
      '{"status":1,"err_code":0,"count":9,"list":[{"id":1,"user_name":"a","content":"x"}]}',
    ]);
    final repo = _repo(adapter);

    await repo.fetchSongComments(mixSongId: '32100650');
    final hot = await repo.fetchSongComments(
      mixSongId: '32100650',
      sort: CommentSort.hottest,
    );

    expect(hot.childrenId, '20505418');
  });

  test('floor: 用 childrenid + tid 打 hot_replylist', () async {
    final adapter = _ScriptedAdapter([_floorJson]);
    final repo = _repo(adapter);

    final replies = await repo.fetchFloorReplies(
      childrenId: '20505418',
      rootCommentId: '1723639894',
      mixSongId: '32100650',
    );

    expect(replies.single.user, 'DYA');
    expect(replies.single.content, contains('//@屿知'));
    final req = adapter.seen.single;
    expect(req.uri.path, '/mcomment/v1/hot_replylist');
    expect(req.queryParameters['childrenid'], '20505418');
    expect(req.queryParameters['tid'], 1723639894);
  });

  test('floor: 缺参数不发请求，直接给可读原因', () async {
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    final replies = await repo.fetchFloorReplies(
      childrenId: '',
      rootCommentId: '',
    );

    expect(replies, isEmpty);
    expect(adapter.seen, isEmpty);
    expect(repo.lastError, isNotEmpty);
  });

  test('评论数: web 签名 + x-router，返回 <hash>: n', () async {
    final adapter = _ScriptedAdapter([
      '{"b3a52a7a958bf0aed0ebfba2e9a818b7":706580}',
    ]);
    final repo = _repo(adapter);

    final count = await repo.fetchCommentCount(
      hash: 'b3a52a7a958bf0aed0ebfba2e9a818b7',
    );

    expect(count, 706580);
    final req = adapter.seen.single;
    expect(req.uri.path, '/index.php');
    expect(req.queryParameters['r'], 'comments/getcommentsnum');
    expect(req.queryParameters['hash'], 'b3a52a7a958bf0aed0ebfba2e9a818b7');
    expect((req.queryParameters['signature'] as String).length, 32);
    expect(req.headers['x-router'], 'sum.comment.service.kugou.com');
  });

  test('评论数: hash 为空时不发请求', () async {
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    expect(await repo.fetchCommentCount(hash: ''), isNull);
    expect(adapter.seen, isEmpty);
  });

  test('明确空列表不重试（避免翻页接口被连打三次）', () async {
    final adapter = _ScriptedAdapter([_emptyJson]);
    final repo = _repo(adapter);

    final page = await repo.fetchSongComments(mixSongId: '32100650');

    expect(page.items, isEmpty);
    expect(page.total, 0);
    expect(repo.lastError, isEmpty);
    expect(adapter.seen.length, 1);
  });

  test('业务错误翻译成人话，且不把 status=1 之外当成功', () async {
    final adapter = _ScriptedAdapter([_badParamJson]);
    final repo = _repo(adapter);

    final page = await repo.fetchSongComments(mixSongId: '32100650');

    expect(page.items, isEmpty);
    expect(repo.lastError, '评论参数无效');
    expect(adapter.seen.length, 1);
  });

  test('风控 20028 给出重登提示', () async {
    final adapter = _ScriptedAdapter([_ssaJson, _ssaJson]);
    final repo = _repo(adapter);

    await repo.fetchSongComments(mixSongId: '32100650');

    expect(repo.lastError, contains('20028'));
  });

  test('无 token 时不会因为 SSA 文案误报「请重新登录」', () async {
    final adapter = _ScriptedAdapter([_ssaJson, _ssaJson]);
    final repo = _repo(adapter);

    await repo.fetchSongComments(mixSongId: '32100650');

    expect(AuthTokenHolder.instance.hasToken, isFalse);
    expect(repo.lastError, contains('评论需要安全校验'));
    expect(repo.lastError, isNot(contains('重新登录')));
  });

  // ── 写侧 ────────────────────────────────────────────────
  //
  // 写口与读口是两条不同的链路：`index.php` + `x-router`，无 `signature`、
  // 无公共参数，靠 `key` 自证。下面的用例把 key 复算一遍，保证「body 参与签名」
  // 这条最容易写错的约定不会被改坏。

  void login() =>
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');

  test('发评论：未登录不发请求，直接抛 LoginRequired', () async {
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendSongComment(childrenId: '20505418', content: '你好'),
      throwsA(isA<LoginRequired>()),
    );
    expect(adapter.seen, isEmpty);
  });

  test('发评论：走 index.php + x-router，key 把 body 一起签', () async {
    login();
    final adapter = _ScriptedAdapter(['{"status":1,"err_code":0}']);
    final repo = _repo(adapter);

    await repo.sendSongComment(
      childrenId: '20505418',
      content: '  好听  ',
      songName: '晴天',
      mixSongId: '32100650',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/index.php');
    expect(req.method, 'POST');
    expect(req.queryParameters['r'], 'commentsv3/add');
    expect(req.queryParameters['childrenid'], 20505418);
    expect(req.queryParameters['childrenname'], '晴天');
    expect(req.queryParameters['kugouid'], 42);
    expect(req.queryParameters['clienttoken'], 'tok');
    expect(req.queryParameters['signature'], isNull); // 写口不吃 signature
    expect(req.headers['x-router'], 'm.comment.service.kugou.com');

    // 正文已 trim；body 形态与上游一致，且 key 必须覆盖这段 JSON
    final payload = req.data as String;
    expect(payload, '{"data":{"content":"好听","album_audio_id":32100650}}');
    final device = await DeviceIdentity.ensure();
    final ct = req.queryParameters['clienttime'] as int;
    expect(
      req.queryParameters['key'],
      KugoSign.signParamsKey('${ct}${device.mid}$payload'),
    );
  });

  test('发评论：20028 → RateLimited（引导去官方客户端验证）', () async {
    login();
    final adapter = _ScriptedAdapter([
      '{"status":0,"err_code":20028,"msg":"security"}',
    ]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendSongComment(childrenId: '20505418', content: '你好'),
      throwsA(isA<RateLimited>()),
    );
  });

  test('发评论：20006 → UpstreamChanged（key 被拒的文案）', () async {
    login();
    final adapter = _ScriptedAdapter([
      '{"status":0,"err_code":20006,"message":"参数验证失败"}',
    ]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendSongComment(childrenId: '20505418', content: '你好'),
      throwsA(isA<UpstreamChanged>()),
    );
  });

  test('发评论：空内容 / 超长在本地就拦下，不发请求', () async {
    login();
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);
    final tooLong = List<String>.filled(201, '字').join();

    await expectLater(
      repo.sendSongComment(childrenId: '20505418', content: '   '),
      throwsA(isA<UpstreamChanged>()),
    );
    await expectLater(
      repo.sendSongComment(childrenId: '20505418', content: tooLong),
      throwsA(isA<UpstreamChanged>()),
    );
    expect(adapter.seen, isEmpty);
  });

  test('发评论：评论池缺失不发请求', () async {
    login();
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendSongComment(childrenId: '', content: '你好'),
      throwsA(isA<NotFound>()),
    );
    expect(adapter.seen, isEmpty);
  });

  test('楼层回复：key 只算 clienttime+mid，正文走 query 且带 is_t/pid', () async {
    login();
    final adapter = _ScriptedAdapter(['{"status":1,"err_code":0}']);
    final repo = _repo(adapter);

    await repo.sendFloorReply(
      childrenId: '20505418',
      rootCommentId: '1723639894',
      content: '同意',
      replyToUser: '屿知',
      replyToContent: '听《晴天》',
      songName: '晴天',
      mixSongId: '32100650',
    );

    final req = adapter.seen.single;
    expect(req.uri.path, '/index.php');
    expect(req.queryParameters['r'], 'commentsv2/reply');
    expect(req.queryParameters['tid'], 1723639894);
    expect(req.queryParameters['is_t'], 1);
    expect(req.queryParameters['pid'], 0);
    expect(req.queryParameters['content'], '同意//@屿知:听《晴天》');
    expect(req.data, ''); // 回复无 body
    final device = await DeviceIdentity.ensure();
    final ct = req.queryParameters['clienttime'] as int;
    expect(
      req.queryParameters['key'],
      KugoSign.signParamsKey('${ct}${device.mid}'),
    );
  });

  test('楼层回复：缺 childrenId / rootId 不发请求', () async {
    login();
    final adapter = _ScriptedAdapter([]);
    final repo = _repo(adapter);

    await expectLater(
      repo.sendFloorReply(childrenId: '', rootCommentId: '', content: 'x'),
      throwsA(isA<NotFound>()),
    );
    expect(adapter.seen, isEmpty);
  });
}
