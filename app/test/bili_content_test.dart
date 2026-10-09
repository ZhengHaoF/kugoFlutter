import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/api/bili/bili_failures.dart';
import 'package:kugo/core/models/catalog_models.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/sources/bili/bili_content.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';
import 'fakes/fake_kugo_client.dart';

Map<String, dynamic> ok(Object data) => {'code': 0, 'data': data};
final nav = ok({
  'isLogin': true,
  'mid': 42,
  'uname': 'UP',
  'wbi_img': {
    'img_url': 'https://i0.hdslb.com/7cd084941338484aae1ad9425b84077c.png',
    'sub_url': 'https://i0.hdslb.com/4932caff0ff746eab6f01bf08b70ac45.png',
  },
});

void main() {
  test('UP 主风控返回可重试错误，不误报协议变更', () {
    expect(BiliFailures.fromCode(-352, '风控校验失败'), isA<RateLimited>());
    expect(BiliFailures.fromCode(-401, '风控校验失败'), isA<RateLimited>());
  });
  BiliClient client(List<Object> responses, {ScriptedAdapter? adapter}) {
    final dio = Dio();
    dio.httpClientAdapter =
        adapter ??
        ScriptedAdapter(responses.map(ScriptedAdapter.json).toList());
    return BiliClient(dio: dio);
  }

  test('内容映射支持 cid、备用 bv_id、封面、时长与来源', () {
    final t = BiliContent.track({
      'bv_id': 'BV1a',
      'cid': 123,
      'title': '<em>歌</em> &amp;',
      'cover': '//i0.hdslb.com/a.jpg',
      'length': '03:20',
      'upper': {'mid': 42, 'name': 'UP'},
    })!;
    expect(t.id, 'BV1a:123');
    expect(t.name, '歌 &');
    expect(t.durationMs, 200000);
    expect(t.artistId, '42');
    expect(t.platform, MusicPlatform.bili);
    expect(t.coverUrl, startsWith('https:'));
  });

  test('空 bvid 与失效收藏不会进入播放列表', () {
    expect(BiliContent.track({'title': '失效'}), isNull);
    expect(BiliContent.track({'bvid': 'BV1a', 'attr': 9}), isNull);
  });

  test('收藏夹分页合并、去重，cid 缺失不做逐曲请求', () async {
    final source = BiliSource(
      client: client([
        ok({
          'info': {'title': '歌单', 'media_count': 2},
          'has_more': true,
          'medias': [
            {'bvid': 'BV1a', 'title': 'a'},
          ],
        }),
        ok({
          'has_more': false,
          'medias': [
            {'bvid': 'BV1a', 'title': 'a'},
            {'bvid': 'BV1b', 'title': 'b', 'cid': 22},
          ],
        }),
      ]),
    );
    final result = (await source.fetchPlaylistDetail('fav:1'))!;
    expect(result.tracks.map((t) => t.id), ['BV1a', 'BV1b:22']);
    expect(result.brief.name, '歌单');
    expect(result.brief.platform, MusicPlatform.bili);
  });

  test('错误内容 ID 在发请求前拒绝', () async {
    final source = BiliSource(client: client([]));
    for (final id in ['1', 'fav:0', 'season:1', 'season:0:2', 'album:2']) {
      await expectLater(
        source.fetchPlaylistDetail(id),
        throwsA(isA<NotFound>()),
      );
    }
  });

  test('分页无进展报错，不能把截断列表当完整列表', () async {
    final source = BiliSource(
      client: client([
        ok({
          'has_more': true,
          'medias': [
            {'bvid': 'BV1a'},
          ],
        }),
        ok({
          'has_more': true,
          'medias': [
            {'bvid': 'BV1a'},
          ],
        }),
      ]),
    );
    await expectLater(
      source.fetchPlaylistDetail('fav:1'),
      throwsA(isA<UpstreamChanged>()),
    );
  });

  test('合集使用 WBI、mid/season_id 与 page_num', () async {
    final adapter = ScriptedAdapter([
      ScriptedAdapter.json(nav),
      ScriptedAdapter.json(
        ok({
          'meta': {'name': '合集'},
          'page': {'total': 1},
          'archives': [
            {'bvid': 'BV1a', 'cid': 1},
          ],
        }),
      ),
    ]);
    final source = BiliSource(client: client([], adapter: adapter));
    final result = (await source.fetchPlaylistDetail('season:42:7'))!;
    expect(result.brief.name, '合集');
    expect(adapter.requests.last.queryParameters['mid'], '42');
    expect(adapter.requests.last.queryParameters['season_id'], '7');
    expect(adapter.requests.last.queryParameters['page_num'], '1');
    expect(adapter.requests.last.queryParameters['w_rid'], isNotEmpty);
  });

  test('系列不使用 WBI，并读取系列元数据', () async {
    final source = BiliSource(
      client: client([
        ok({
          'archives': [
            {'bvid': 'BV1a'},
          ],
          'page': {'total': 1},
        }),
        ok({
          'meta': {'name': '系列', 'description': '说明'},
        }),
      ]),
    );
    expect((await source.fetchPlaylistDetail('series:42:7'))!.brief.name, '系列');
  });

  test('UP 主合集与系列都能返回不同类型的深链 ID', () async {
    final source = BiliSource(
      client: client([
        nav,
        ok({
          'items_lists': {
            'page': {'total': 2},
            'seasons_list': [
              {
                'meta': {'season_id': 7, 'name': '合集'},
              },
            ],
            'series_list': [
              {
                'meta': {'series_id': 8, 'name': '系列'},
              },
            ],
          },
        }),
      ]),
    );
    final page = await source.artistContents('42');
    expect(page.items.map((p) => p.id), ['season:42:7', 'series:42:8']);
    expect(page.total, 2);
  });

  test('UP 主投稿分页与最新排序映射', () async {
    final adapter = ScriptedAdapter([
      ScriptedAdapter.json(nav),
      ScriptedAdapter.json(
        ok({
          'list': {
            'vlist': [
              {'bvid': 'BV1a', 'length': '01:00'},
            ],
          },
          'page': {'count': 31},
        }),
      ),
    ]);
    final source = BiliSource(client: client([], adapter: adapter));
    final page = await source.fetchArtistSongsPage(
      '42',
      sort: ArtistSongSort.newest,
    );
    expect(page.hasMore, isTrue);
    expect(page.songs.single.artistId, '42');
    expect(adapter.requests.last.queryParameters['order'], 'pubdate');
  });

  test('未登录读取个人收藏夹要求登录', () async {
    await expectLater(
      BiliSource(client: client([])).userPlaylists(),
      throwsA(isA<LoginRequired>()),
    );
  });

  test('收藏口 count 分页和 type=21 合集不会误走收藏夹端点', () async {
    final c = client([
      nav,
      ok({
        'list': [
          {'id': 1, 'title': '自建'},
        ],
      }),
      ok({
        'count': 21,
        'list': [
          {'id': 7, 'mid': 42, 'type': 21, 'title': '合集'},
        ],
      }),
      ok({'list': []}),
      ok({
        'count': 21,
        'list': [
          {'id': 8, 'title': '他人夹'},
        ],
      }),
    ])..seedCookies({'SESSDATA': 'test'});
    final page = await BiliSource(client: c).userPlaylists();
    expect(page.created.single.id, 'fav:1');
    expect(page.collected.map((p) => p.id), ['season:42:7', 'fav:8']);
    expect(page.more, isFalse);
    expect(page.favoritedAlbums, isEmpty);
  });

  test('多 P 视频展开独立身份', () async {
    final source = BiliSource(
      client: client([
        nav,
        ok({
          'title': '合集视频',
          'bvid': 'BV1a',
          'owner': {'mid': 42, 'name': 'UP'},
        }),
        ok([
          {'cid': 1, 'page': 1, 'part': '第一首', 'duration': 100},
          {'cid': 2, 'page': 2, 'part': '第二首', 'duration': 200},
        ]),
      ]),
    );
    final result = (await source.fetchPlaylistDetail('video:BV1a'))!;
    expect(result.tracks.map((t) => t.id), ['BV1a:1', 'BV1a:2']);
    expect(result.tracks.last.durationMs, 200000);
  });
}
