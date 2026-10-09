import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';

import 'fakes/fake_kugo_client.dart' show ScriptedAdapter;

/// B 站适配层单测：ScriptedAdapter 回放真实形态的 fixture（探针实测结构），
/// 不联外网。覆盖 id 两种形态、选轨降级、防盗链头、兜底路径（方案 §10）。
void main() {
  // ── fixtures（结构对齐 2026-10-09 探针实测）──────────────────

  Map<String, dynamic> navJson() => {
        'code': -101,
        'message': '账号未登录',
        'data': {
          'isLogin': false,
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        },
      };

  final searchJson = {
    'code': 0,
    'data': {
      'numResults': 1000,
      'numPages': 50,
      'page': 1,
      'result': [
        {
          'type': 'video',
          'bvid': 'BV1songA',
          'aid': 111,
          'title': '【<em class="keyword">周杰伦</em>】晴天 &amp; 花海',
          'author': '音乐台',
          'mid': 42,
          'pic': '//i0.hdslb.com/bfs/archive/aaa.jpg',
          'duration': '04:35',
          'play': 123456,
          'pubdate': 1700000000,
        },
        {
          'type': 'video',
          'bvid': 'BV1long',
          'aid': 222,
          'title': '40分钟现场混音',
          'author': '某UP',
          'mid': 43,
          'pic': '//i0.hdslb.com/bfs/archive/bbb.jpg',
          'duration': '40:00',
          'play': 999,
          'pubdate': 1700000001,
        },
        {'type': 'live', 'bvid': 'LV1room', 'title': '直播间'},
      ],
    },
  };

  final pagelistJson = {
    'code': 0,
    'data': [
      {'cid': 39252201332, 'page': 1, 'part': '001.周杰伦_晴天', 'duration': 270},
      {'cid': 39252201462, 'page': 2, 'part': '002.周杰伦_夜曲', 'duration': 227},
    ],
  };

  Map<String, dynamic> playurlJson({
    List<Map<String, dynamic>>? audio,
    List<String>? durl,
    int code = 0,
  }) =>
      {
        'code': code,
        if (code != 0) 'message': 'request blocked',
        'data': {
          'dash': {
            'audio': audio ??
                [
                  {
                    'id': 30216,
                    'baseUrl': 'https://upos.example/30216.m4s',
                    'backupUrl': ['https://bak.example/30216.m4s'],
                    'bandwidth': 65903,
                    'mimeType': 'audio/mp4',
                    'codecs': 'mp4a.40.2',
                  },
                  {
                    'id': 30232,
                    'baseUrl': 'https://upos.example/30232.m4s',
                    'backupUrl': <String>[],
                    'bandwidth': 115000,
                    'mimeType': 'audio/mp4',
                    'codecs': 'mp4a.40.2',
                  },
                  {
                    'id': 30280,
                    'baseUrl': 'https://upos.example/30280.m4s',
                    'backupUrl': ['https://bak.example/30280.m4s'],
                    'bandwidth': 216000,
                    'mimeType': 'audio/mp4',
                    'codecs': 'mp4a.40.2',
                  },
                ],
            'dolby': {'audio': <Map<String, dynamic>>[]},
          },
          if (durl != null)
            'durl': [
              for (final u in durl) {'url': u, 'backup_url': <String>[]},
            ],
        },
      };

  ({ScriptedAdapter adapter, BiliSource source}) harness(
      List<dynamic> responses) {
    final adapter = ScriptedAdapter(responses);
    final dio = Dio()..httpClientAdapter = adapter;
    return (
      adapter: adapter,
      source: BiliSource(client: BiliClient(dio: dio)),
    );
  }

  Track track(String id) => Track(
        id: id,
        name: '晴天',
        artist: '周杰伦',
        album: '',
        coverUrl: '',
        durationMs: 275000,
        platform: MusicPlatform.bili,
      );

  group('searchSongs', () {
    test('搜索 → Track：裸 bvid 身份、剥壳、过滤长视频/直播间', () async {
      final h = harness([ScriptedAdapter.json(navJson()), ScriptedAdapter.json(searchJson)]);

      final result = await h.source.searchSongs('周杰伦');

      expect(result.total, 1000);
      expect(result.items, hasLength(1)); // 40min 与直播间被过滤
      final t = result.items.first;
      expect(t.id, 'BV1songA');
      expect(t.name, '【周杰伦】晴天 & 花海');
      expect(t.artist, '音乐台');
      expect(t.durationMs, 275000);
      expect(t.coverUrl, 'https://i0.hdslb.com/bfs/archive/aaa.jpg');
      // WBI 签名确实带上（w_rid 32 hex）。
      final searchReq = h.adapter.requests.last;
      expect(searchReq.uri.queryParameters['w_rid'],
          matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(searchReq.uri.queryParameters['search_type'], 'video');
    });
  });

  group('resolvePlayUrl · id 两种形态', () {
    test('裸 bvid → 先 pagelist 取 P1 cid 再取流', () async {
      // 请求顺序：pagelist（不带 WBI，不需要 nav）→ nav（mixinKey）→ playurl。
      final h = harness([
        ScriptedAdapter.json(pagelistJson),
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson()),
      ]);

      final r = await h.source.resolvePlayUrl(track('BV1songA'));

      expect(r.url, 'https://upos.example/30280.m4s'); // 默认取最高档
      expect(r.backupUrls, ['https://bak.example/30280.m4s']);
      expect(r.grantedQuality, AppQuality.sq);
      expect(r.isPreviewClip, isFalse);
      expect(r.headers['Referer'], 'https://www.bilibili.com');
      expect(r.headers['User-Agent'], isNotEmpty);

      final paths = h.adapter.requests.map((r) => r.uri.path).toList();
      expect(paths.where((p) => p.contains('pagelist')), hasLength(1));
      expect(paths.where((p) => p.contains('playurl')), hasLength(1));
      // playurl 带的是 pagelist 首条 cid。
      final playReq =
          h.adapter.requests.lastWhere((r) => r.uri.path.contains('playurl'));
      expect(playReq.uri.queryParameters['cid'], '39252201332');
      expect(playReq.uri.queryParameters['fnval'], '272');
    });

    test('bvid:cid → 直接用，不再打 pagelist', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson()),
      ]);

      final r = await h.source.resolvePlayUrl(track('BV1songA:39252201462'));

      expect(r.url, 'https://upos.example/30280.m4s');
      final paths = h.adapter.requests.map((r) => r.uri.path).toList();
      expect(paths.where((p) => p.contains('pagelist')), isEmpty);
      final playReq =
          h.adapter.requests.lastWhere((r) => r.uri.path.contains('playurl'));
      expect(playReq.uri.queryParameters['cid'], '39252201462');
    });
  });

  group('resolvePlayUrl · 选轨降级（按带宽，禁硬编码 id）', () {
    ({ScriptedAdapter adapter, BiliSource source}) threeTracks() => harness([
          ScriptedAdapter.json(navJson()),
          ScriptedAdapter.json(playurlJson()),
        ]);

    test('偏好 standard → 64k；hq → 115k；sq → 216k', () async {
      for (final (pref, url, granted) in [
        (AppQuality.standard, 'https://upos.example/30216.m4s', AppQuality.standard),
        (AppQuality.hq, 'https://upos.example/30232.m4s', AppQuality.hq),
        (AppQuality.sq, 'https://upos.example/30280.m4s', AppQuality.sq),
      ]) {
        final h = threeTracks();
        final r = await h.source.resolvePlayUrl(track('BV1songA:1'), preferred: pref);
        expect(r.url, url, reason: 'preferred=$pref');
        expect(r.grantedQuality, granted, reason: 'preferred=$pref');
      }
    });

    test('偏好 hiRes 无 hires 轨 → 落到最高普通轨（sq）', () async {
      final h = threeTracks();
      final r =
          await h.source.resolvePlayUrl(track('BV1songA:1'), preferred: AppQuality.hiRes);
      expect(r.url, 'https://upos.example/30280.m4s');
      expect(r.grantedQuality, AppQuality.sq);
    });

    test('低于偏好档：只有 64k/115k 而偏好 hiRes → 115k（hq）', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(audio: [
          {
            'id': 30216,
            'baseUrl': 'https://upos.example/30216.m4s',
            'bandwidth': 65903,
            'mimeType': 'audio/mp4',
            'codecs': 'mp4a.40.2',
          },
          {
            'id': 30232,
            'baseUrl': 'https://upos.example/30232.m4s',
            'bandwidth': 115000,
            'mimeType': 'audio/mp4',
            'codecs': 'mp4a.40.2',
          },
        ])),
      ]);
      final r =
          await h.source.resolvePlayUrl(track('BV1songA:1'), preferred: AppQuality.hiRes);
      expect(r.url, 'https://upos.example/30232.m4s');
      expect(r.grantedQuality, AppQuality.hq);
    });

    test('高于偏好档：只有 115k/216k 而偏好 standard → 取最低 115k', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(audio: [
          {
            'id': 30232,
            'baseUrl': 'https://upos.example/30232.m4s',
            'bandwidth': 115000,
            'mimeType': 'audio/mp4',
            'codecs': 'mp4a.40.2',
          },
          {
            'id': 30280,
            'baseUrl': 'https://upos.example/30280.m4s',
            'bandwidth': 216000,
            'mimeType': 'audio/mp4',
            'codecs': 'mp4a.40.2',
          },
        ])),
      ]);
      final r =
          await h.source.resolvePlayUrl(track('BV1songA:1'), preferred: AppQuality.standard);
      expect(r.url, 'https://upos.example/30232.m4s');
      expect(r.grantedQuality, AppQuality.hq);
    });

    test('dolby / flac 轨按组映射（sq / hiRes）', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json({
          'code': 0,
          'data': {
            'dash': {
              'audio': [
                {
                  'id': 30280,
                  'baseUrl': 'https://upos.example/30280.m4s',
                  'bandwidth': 216000,
                  'mimeType': 'audio/mp4',
                  'codecs': 'mp4a.40.2',
                },
              ],
              'dolby': {
                'audio': [
                  {
                    'id': 30250,
                    'baseUrl': 'https://upos.example/dolby.m4s',
                    'bandwidth': 100000,
                    'mimeType': 'audio/mp4',
                    'codecs': 'ec-3',
                  },
                ],
              },
              'flac': {
                'audio': [
                  {
                    'id': 30251,
                    'baseUrl': 'https://upos.example/hires.flac',
                    'bandwidth': 900000,
                    'mimeType': 'audio/flac',
                    'codecs': 'flac',
                  },
                ],
              },
            },
          },
        }),
      ]);

      final hr = await h.source.resolvePlayUrl(track('BV1songA:1'), preferred: AppQuality.hiRes);
      expect(hr.url, 'https://upos.example/hires.flac');
      expect(hr.grantedQuality, AppQuality.hiRes);

      final h2 = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json({
          'code': 0,
          'data': {
            'dash': {
              'audio': [
                {
                  'id': 30280,
                  'baseUrl': 'https://upos.example/30280.m4s',
                  'bandwidth': 216000,
                  'mimeType': 'audio/mp4',
                  'codecs': 'mp4a.40.2',
                },
              ],
              'dolby': {
                'audio': [
                  {
                    'id': 30250,
                    'baseUrl': 'https://upos.example/dolby.m4s',
                    'bandwidth': 100000,
                    'mimeType': 'audio/mp4',
                    'codecs': 'ec-3',
                  },
                ],
              },
            },
          },
        }),
      ]);
      final sq = await h2.source.resolvePlayUrl(track('BV1songA:1'), preferred: AppQuality.sq);
      expect(sq.url, 'https://upos.example/dolby.m4s');
      expect(sq.grantedQuality, AppQuality.sq);
    });
  });

  group('resolvePlayUrl · 兜底路径', () {
    test('DASH 空 → durl（MP4 整段）兜底，grantedQuality 未知', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(audio: [], durl: ['https://mp4.example/v.m4s'])),
        ScriptedAdapter.json(playurlJson(audio: [], durl: ['https://mp4.example/v.m4s'])),
      ]);

      final r = await h.source.resolvePlayUrl(track('BV1songA:1'));
      expect(r.url, 'https://mp4.example/v.m4s');
      expect(r.grantedQuality, isNull);
      expect(r.isPreviewClip, isFalse);
    });

    test('DASH 空且无 durl → 重试一次后回落 platform=html5', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(audio: [])),
        ScriptedAdapter.json(playurlJson(audio: [])),
        ScriptedAdapter.json(playurlJson(audio: [], durl: ['https://html5.example/v.m4s'])),
      ]);

      final r = await h.source.resolvePlayUrl(track('BV1songA:1'));
      expect(r.url, 'https://html5.example/v.m4s');

      final playReqs = h.adapter.requests
          .where((r) => r.uri.path.contains('playurl'))
          .toList();
      expect(playReqs, hasLength(3)); // 2 次 DASH + 1 次 html5
      expect(playReqs.last.uri.queryParameters['platform'], 'html5');
    });

    test('全空（含 html5）→ NotFound', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(audio: [])),
        ScriptedAdapter.json(playurlJson(audio: [])),
        ScriptedAdapter.json(playurlJson(audio: [])),
      ]);

      await expectLater(
        h.source.resolvePlayUrl(track('BV1songA:1')),
        throwsA(isA<NotFound>()),
      );
    });

    test('-412 风控 → RateLimited', () async {
      final h = harness([
        ScriptedAdapter.json(navJson()),
        ScriptedAdapter.json(playurlJson(code: -412)),
      ]);

      await expectLater(
        h.source.resolvePlayUrl(track('BV1songA:1')),
        throwsA(isA<RateLimited>()),
      );
    });
  });

  group('其余契约', () {
    test('fetchLyric 恒空（B 站无歌词接口）', () async {
      final h = harness([]);
      final lyric = await h.source.fetchLyric(track('BV1songA'));
      expect(lyric.lines, isEmpty);
      expect(lyric.isEmpty, isTrue);
    });

    test('歌单/专辑/歌手搜索返空且不发请求', () async {
      final h = harness([]);
      expect((await h.source.searchPlaylists('x')).items, isEmpty);
      expect((await h.source.searchAlbums('x')).items, isEmpty);
      expect((await h.source.searchArtists('x')).items, isEmpty);
      expect(h.adapter.requests, isEmpty);
    });

    test('platform = bili', () {
      expect(BiliSource().platform.wireName, 'bili');
      expect(BiliSource().platform.label, '哔哩哔哩');
    });
  });
}
