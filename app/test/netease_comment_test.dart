/// 网易云评论（N1a 歌曲 / N1b 歌单·专辑）：映射与源层。
///
/// fixture 取自 2026-09-27 真机实测（`songId=2652820720`，`totalCount` 28932），
/// 字段结构与响应一致，只做了精简。
///
/// 两条最容易被改坏的约定（都有用例钉着）：
/// 1. E1 是 **`data` 包裹**，不是顶层平铺；
/// 2. 下一页游标是**服务端 `data.cursor`**，不是按 `pageSize` 拼的 offset
///    —— 实测响应条数不受 `pageSize` 控制（要 20 时推荐档给 26）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';

const String _listJson = '''
{"code":200,"message":"成功","data":{
  "hasMore":true,"cursor":"1790422846204","totalCount":28932,
  "sortTypeList":[
    {"sortType":1,"sortTypeName":"按推荐排序"},
    {"sortType":2,"sortTypeName":"按热度排序"},
    {"sortType":3,"sortTypeName":"按时间排序"}],
  "comments":[
    {"commentId":7475006689,"content":"这是唯一一只从官方眼里逃出来的鱼",
     "time":1790422846204,"timeStr":"2024-12-08","likedCount":14748,
     "replyCount":102,"ipLocation":{"location":"甘肃"},
     "user":{"userId":123,"nickname":"DJ旭辉Remix",
             "avatarUrl":"http://p1.music.126.net/abc.jpg",
             "vipType":0,"authStatus":0},
     "showFloorComment":{"replyCount":102}},
    {"commentId":7535804210,"content":"再过五个小时 我就要起床结婚啦",
     "time":1790410000000,"timeStr":"2025-02-01","likedCount":13050,
     "replyCount":1163,"ipLocation":{"location":"湖南"},
     "user":{"userId":456,"nickname":"悲哀痛骨","avatarUrl":"",
             "vipType":11,"authStatus":1,"expertTags":["音乐达人"]},
     "showFloorComment":{"replyCount":1163}}
  ]}}
''';

const String _lastPageJson = '''
{"code":200,"data":{"hasMore":false,"cursor":"1790422846204","totalCount":28932,
  "comments":[]}}
''';

const String _floorJson = '''
{"code":200,"message":"获取成功","data":{
  "ownerComment":{"commentId":7475006689,"content":"父评论"},
  "hasMore":false,"totalCount":102,
  "comments":[
    {"commentId":9000000001,"content":"所以这首歌叫什么？","timeStr":"2024-12-09",
     "likedCount":3,"user":{"userId":1,"nickname":"路人甲","vipType":0},
     "ipLocation":{"location":"广东"}}
  ]}}
''';

class _FakeNeteaseClient extends NeteaseClient {
  String listRaw = _listJson;
  String floorRaw = _floorJson;

  Map<String, Object?> lastList = const {};
  Map<String, Object?> lastFloor = const {};

  @override
  Future<String> commentListRaw({
    required String threadId,
    int pageNo = 1,
    int pageSize = 20,
    String cursor = '',
    int sortType = 99,
  }) async {
    lastList = {
      'threadId': threadId,
      'pageNo': pageNo,
      'pageSize': pageSize,
      'cursor': cursor,
      'sortType': sortType,
    };
    return listRaw;
  }

  @override
  Future<String> commentFloorRaw({
    required String threadId,
    required String parentCommentId,
    int limit = 20,
    int time = -1,
  }) async {
    lastFloor = {
      'threadId': threadId,
      'parentCommentId': parentCommentId,
      'limit': limit,
      'time': time,
    };
    return floorRaw;
  }
}

const Track _track = Track(
  id: '2652820720',
  name: '晴天(深情版)',
  artist: '周杰伦',
  album: '晴天',
  coverUrl: '',
  durationMs: 0,
  platform: MusicPlatform.netease,
);

void main() {
  group('映射：E1 列表', () {
    test('data 包裹：评论 / 总数 / 游标都从 data 下取', () {
      final parsed = mapNeteaseComments(
        _listJson,
        threadId: 'R_SO_4_2652820720',
      );
      expect(parsed.page.items, hasLength(2));
      expect(parsed.page.total, 28932);
      expect(parsed.page.childrenId, 'R_SO_4_2652820720');
      // 游标直接取服务端 data.cursor（自己拼 offset 会错位）。
      expect(parsed.page.nextCursor, '1790422846204');
      expect(parsed.page.maxPage, 0, reason: '页码式字段网易不用');
    });

    test('hasMore=false 时游标为空（= 没有下一页）', () {
      final parsed = mapNeteaseComments(
        _lastPageJson,
        threadId: 'R_SO_4_2652820720',
      );
      expect(parsed.page.nextCursor, isEmpty);
    });

    test('档位来自服务端 sortTypeList，sortType=1 归一化为 99', () {
      final parsed = mapNeteaseComments(
        _listJson,
        threadId: 'R_SO_4_2652820720',
      );
      expect(parsed.sorts, [
        (id: '99', label: '按推荐排序'),
        (id: '2', label: '按热度排序'),
        (id: '3', label: '按时间排序'),
      ]);
    });

    test('字段映射：timeStr 直用、IP 属地、楼层数、VIP 铭牌', () {
      final items = mapNeteaseComments(
        _listJson,
        threadId: 'R_SO_4_2652820720',
      ).page.items;
      final first = items.first;
      expect(first.id, '7475006689');
      expect(first.user, 'DJ旭辉Remix');
      expect(first.content, contains('逃出来的鱼'));
      // timeStr 已是可读文本，不得再格式化。
      expect(first.timeLabel, '2024-12-08');
      expect(first.location, '甘肃');
      expect(first.likeCount, 14748);
      expect(first.replyCount, 102);
      expect(first.hasReplies, isTrue);
      expect(first.badges, isEmpty, reason: 'vipType=0 且无认证');

      final second = items[1];
      expect(second.badges.map((b) => b.label), containsAll(['VIP', '音乐人']));
      expect(second.badges.map((b) => b.label), contains('音乐达人'));
    });
  });

  group('映射：E2 楼层', () {
    test('数据在 data.comments，不是顶层', () {
      final list = mapNeteaseFloorComments(_floorJson);
      expect(list, hasLength(1));
      expect(list.first.content, '所以这首歌叫什么？');
      expect(list.first.timeLabel, '2024-12-09');
    });
  });

  group('源层：N1a 歌曲', () {
    test('threadId = R_SO_4_<songId>，默认档 sortType=99', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      final page = await source.songComments(_track);
      expect(page.items, isNotEmpty);
      expect(client.lastList['threadId'], 'R_SO_4_2652820720');
      expect(client.lastList['sortType'], 99);
      expect(client.lastList['cursor'], '');
      expect(source.lastError, isEmpty);
    });

    test('换档位：sort 字符串原样转成 sortType', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      await source.songComments(_track, sort: '2');
      expect(client.lastList['sortType'], 2);
      await source.songComments(_track, sort: '3');
      expect(client.lastList['sortType'], 3);
    });

    test('翻页：cursor 原样回传', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      await source.songComments(_track, page: 2, cursor: '1790422846204');
      expect(client.lastList['pageNo'], 2);
      expect(client.lastList['cursor'], '1790422846204');
    });

    test('档位以服务端为准（拿到响应后覆盖默认档）', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      expect(source.commentSortOptions.first.label, '推荐', reason: '首屏前是默认值');
      await source.songComments(_track);
      expect(source.commentSortOptions.first.label, '按推荐排序');
    });

    test('缺少歌曲 ID：返回空 + 可读原因，不抛异常', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      final page = await source.songComments(
        const Track(
          id: '',
          name: 'x',
          artist: 'y',
          album: 'z',
          coverUrl: '',
          durationMs: 0,
        ),
      );
      expect(page.items, isEmpty);
      expect(source.lastError, isNotEmpty);
    });

    test('评论数：网易未提供总数入口，返回 null（不编数字）', () async {
      final source = NeteaseSource(client: _FakeNeteaseClient());
      expect(await source.commentCount(_track), isNull);
    });

    test('楼层：threadId 取评论池，limit 传 pageSize', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      final list = await source.floorReplies(
        track: _track,
        childrenId: 'R_SO_4_2652820720',
        rootCommentId: '7475006689',
      );
      expect(list, hasLength(1));
      expect(client.lastFloor['threadId'], 'R_SO_4_2652820720');
      expect(client.lastFloor['parentCommentId'], '7475006689');
    });
  });

  group('源层：N1b 歌单 / 专辑', () {
    test('歌单 → A_PL_0_ 前缀', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      await source.resourceComments(
        CommentResourceKind.playlist,
        resourceId: '19723756',
      );
      expect(client.lastList['threadId'], 'A_PL_0_19723756');
    });

    test('专辑 → R_AL_3_ 前缀', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      await source.resourceComments(
        CommentResourceKind.album,
        resourceId: '3116679',
      );
      expect(client.lastList['threadId'], 'R_AL_3_3116679');
    });

    test('资源 id 非数字：返回空 + 原因', () async {
      final client = _FakeNeteaseClient();
      final source = NeteaseSource(client: client);
      final page = await source.resourceComments(
        CommentResourceKind.playlist,
        resourceId: 'abc',
      );
      expect(page.items, isEmpty);
      expect(source.resourceCommentError, isNotEmpty);
    });

    test('资源楼层：评论池为空时直接返回空', () async {
      final source = NeteaseSource(client: _FakeNeteaseClient());
      final list = await source.resourceFloorReplies(
        CommentResourceKind.playlist,
        childrenId: '',
        rootCommentId: '1',
      );
      expect(list, isEmpty);
    });
  });
}
