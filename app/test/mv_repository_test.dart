import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugou/kugo_client.dart';
import 'package:kugo/core/api/mappers.dart' show mvCoverUrl;
import 'package:kugo/core/models/mv_models.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/repositories/mv_repository.dart';
import 'package:kugo/data/storage/device_identity.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按队列吐响应体，并记录请求，供断言 URL / body。
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

/// 简版 search/mv 用的 client。
class _FakeClient extends KugoClient {
  _FakeClient(this.responses);

  final Map<String, Object?> responses;
  final List<String> requestedPaths = [];

  @override
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query}) async {
    final uri = Uri.parse(url);
    requestedPaths.add(uri.path);
    for (final entry in responses.entries) {
      if (uri.path.contains(entry.key)) {
        final body = entry.value;
        return body is String ? jsonDecode(body) : body;
      }
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

MvRepository _repo(_ScriptedAdapter adapter, {_FakeClient? client}) {
  final dio = Dio(
    BaseOptions(
      validateStatus: (code) => code != null && code >= 200 && code < 500,
      responseType: ResponseType.plain,
    ),
  );
  dio.httpClientAdapter = adapter;
  return MvRepository(client: client ?? _FakeClient(const {}), dio: dio);
}

Track _track({String mixSongId = '32100650'}) => Track(
      id: mixSongId,
      name: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      coverUrl: '',
      durationMs: 269000,
      mixSongId: mixSongId,
    );

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

  group('normalizeMvCollectId — 收藏 ID 坑', () {
    test('只接受正整数 video_id；hash / 0 / 负数 / 小数一律拒绝', () {
      for (final bad in [
        '',
        'abcdef1234',
        '0',
        '-1',
        '1.5',
        '1e3',
        '9007199254740992',
        'mvhash_deadbeef',
      ]) {
        expect(normalizeMvCollectId(bad), '', reason: bad);
      }
      expect(normalizeMvCollectId('00123'), '123');
      expect(normalizeMvCollectId(456), '456');
    });
  });

  group('mvCoverUrl — MV 封面 CDN', () {
    test('裸文件名走 mvhdpic，不走 soft/collection', () {
      expect(
        mvCoverUrl('abc123.jpg'),
        'https://imge.kugou.com/mvhdpic/400/abc123.jpg',
      );
      expect(
        mvCoverUrl('DEF.JPG', size: '720'),
        'https://imge.kugou.com/mvhdpic/720/DEF.JPG',
      );
    });

    test('完整 URL 原样保留（只做协议/域名归一）', () {
      expect(
        mvCoverUrl('http://imge.kugou.com/mvhdpic/400/x.jpg'),
        'https://imge.kugou.com/mvhdpic/400/x.jpg',
      );
      expect(
        mvCoverUrl('//imge.kugou.com/a/b.jpg'),
        'https://imge.kugou.com/a/b.jpg',
      );
    });

    test('空串返回空，不用 hash 兜底', () {
      expect(mvCoverUrl(''), '');
      expect(mvCoverUrl('   '), '');
    });
  });

  group('searchMvs — 富/简映射', () {
    test('富版：MvID / MvHash / MixSongID 各归其位，Pic 走 mvhdpic', () async {
      final adapter = _ScriptedAdapter([
        jsonEncode({
          'status': 1,
          'data': {
            'total': 1,
            'lists': [
              {
                'MvID': 987654,
                'MvHash': 'AABBCCDD',
                'MixSongID': 32100650,
                'MvName': '晴天 MV',
                'Pic': 'mv_cover_file.jpg',
                'Duration': 269,
                'Singers': [
                  {'name': '周杰伦'},
                ],
                'SingerID': [3520],
                'MvHashMark': '1080P',
                'FileHash': 'SONGHash',
                'PublishDate': '2003-07-31',
              },
            ],
          },
        }),
      ]);
      final repo = _repo(adapter);

      final page = await repo.searchMvs('晴天');

      expect(page.items, hasLength(1));
      final mv = page.items.single;
      expect(mv.id, '987654');
      expect(mv.hash, 'aabbccdd'); // 主 MV hash，小写
      expect(mv.mixSongId, '32100650');
      expect(mv.name, '晴天 MV');
      expect(mv.artist, '周杰伦');
      expect(mv.artistId, '3520');
      expect(mv.qualityMark, '1080P');
      expect(mv.audioHash, 'songhash');
      expect(
        mv.coverUrl,
        'https://imge.kugou.com/mvhdpic/400/mv_cover_file.jpg',
      );
      expect(adapter.seen.single.uri.path, contains('/v1/search/mv'));
    });

    test('简版兜底：hash 来自 search/mv 的 hash，不是 mvhash', () async {
      final client = _FakeClient({
        '/api/v3/search/mv': {
          'status': 1,
          'data': {
            'total': 1,
            'info': [
              {
                'hash': 'MVMAINHASH',
                'filename': '周杰伦 - 晴天',
                'singername': '周杰伦',
                'duration': 269,
                'imgurl': 'http://imge.kugou.com/x.jpg',
              },
            ],
          },
        },
      });
      // 富版直接抛 → 走简版。
      final adapter = _ScriptedAdapter([]);
      final dio = Dio()..httpClientAdapter = adapter;
      // 让富版失败：返回非 JSON 顶层会 throw UpstreamChanged，被 searchMvs 吞掉。
      final repo = MvRepository(client: client, dio: dio);

      // 富版 _signedGet 会拿到 '{}' → lists 空 → 回落简版。
      final page = await repo.searchMvs('晴天');

      expect(page.items, hasLength(1));
      expect(page.items.single.hash, 'mvmainhash');
      expect(page.items.single.name, '周杰伦 - 晴天');
      expect(client.requestedPaths.single, contains('/api/v3/search/mv'));
    });
  });

  group('songMvs — album_audio_id 必须是 MixSongID', () {
    test('body.data[0].album_audio_id = track.mixSongId', () async {
      final adapter = _ScriptedAdapter([
        jsonEncode({
          'status': 1,
          'data': [
            [
              {
                'video_id': '111',
                'video_name': '晴天 (官方版)',
                'album_audio_id': '32100650',
                'mkv': {'sd_hash': 'mkvsdhash'},
                'h264': {
                  'sd_hash': 'h264sd',
                  'hd_hash': 'h264hd',
                  'qhd_hash': 'h264qhd',
                },
                'authors': [
                  {'author_name': '周杰伦'},
                ],
                'timelength': 269000,
              },
            ],
          ],
        }),
      ]);
      final repo = _repo(adapter);

      final list = await repo.songMvs(_track(mixSongId: '32100650'));

      expect(list, hasLength(1));
      final req = adapter.seen.single;
      expect(req.uri.path, contains('/kmr/v1/audio/mv'));
      expect(req.method, 'POST');
      final body = jsonDecode(req.data as String) as Map<String, dynamic>;
      final data = (body['data'] as List).first as Map<String, dynamic>;
      expect(data['album_audio_id'], '32100650');
      expect(body['fields'], contains('h264'));
      // hash 优先 mkv.sd_hash
      expect(list.single.hash, 'mkvsdhash');
      expect(list.single.id, '111');
    });

    test('无 mixSongId 时直接返回空，不打网络', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      final empty = await repo.songMvs(const Track(
        id: 'x',
        name: 'x',
        artist: '',
        album: '',
        coverUrl: '',
        durationMs: 0,
      ));
      expect(empty, isEmpty);
      expect(adapter.seen, isEmpty);
    });
  });

  group('fetchMvDetail — 片源抽取', () {
    test('扁平形态：ld/sd/qhd/hd/fhd + _265，按清到糊排序', () async {
      final adapter = _ScriptedAdapter([
        jsonEncode({
          'status': 1,
          'data': [
            {
              'video_id': '987654',
              'video_name': '晴天 MV',
              'fhd_hash': 'hash1080',
              'hd_hash': 'hash720',
              'qhd_hash': 'hash540',
              'sd_hash': 'hash432',
              'ld_hash': 'hash270',
              'hd_hash_265': 'hash720_265',
              'play_times': 12345678,
              'download_total': 999,
              'collection_total': 888,
              'duration': 269,
              'publish_time': '2003-07-31',
              'desc': '官方 MV',
            },
          ],
        }),
      ]);
      final repo = _repo(adapter);
      final brief = MvBrief(
        id: '987654',
        hash: 'hash1080',
        name: '晴天 MV',
        coverUrl: '',
      );

      final detail = await repo.fetchMvDetail(brief);

      expect(detail, isNotNull);
      final sources = detail!.sources;
      expect(sources.first.label, '1080P');
      expect(sources.first.hash, 'hash1080');
      expect(sources.map((s) => s.hash), containsAll(['hash720', 'hash720_265']));
      expect(detail.defaultSource!.hash, 'hash1080');
      expect(detail.playCountLabel, isNotEmpty);
      expect(detail.description, '官方 MV');
      expect(detail.brief.publishDate, '2003-07-31');
      expect(detail.brief.durationMs, 269000);
    });

    test('嵌套形态：h264/h265/mkv 的 {q}_hash 都能抽出', () async {
      final adapter = _ScriptedAdapter([
        jsonEncode({
          'status': 1,
          'data': [
            {
              'video_id': '111',
              'video_name': '晴天 (现场)',
              'h264': {
                'ld_hash': 'a_ld',
                'sd_hash': 'a_sd',
                'qhd_hash': 'a_qhd',
                'hd_hash': 'a_hd',
                'fhd_hash': 'a_fhd',
              },
              'h265': {
                'hd_hash': 'b_hd',
              },
              'mkv': {
                'sd_hash': 'c_sd',
              },
            },
          ],
        }),
      ]);
      final repo = _repo(adapter);
      final detail = await repo.fetchMvDetail(
        const MvBrief(id: '111', hash: '', name: '', coverUrl: ''),
      );

      final hashes = detail!.sources.map((s) => s.hash).toSet();
      expect(
        hashes,
        containsAll(['a_ld', 'a_sd', 'a_qhd', 'a_hd', 'a_fhd', 'b_hd', 'c_sd']),
      );
      // 最清优先
      expect(detail.defaultSource!.label, '1080P');
    });

    test('video_id 为空时返回 null，不打网络', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      final detail = await repo.fetchMvDetail(
        const MvBrief(id: '', hash: 'abc', name: 'x', coverUrl: ''),
      );
      expect(detail, isNull);
      expect(adapter.seen, isEmpty);
    });
  });

  group('resolveMvPlayUrl — 播放 hash', () {
    test('key=signKey(hash)，响应按 hash 取 downurl', () async {
      final adapter = _ScriptedAdapter([
        jsonEncode({
          'status': 1,
          'data': {
            'hash1080': {
              'downurl': 'http://trackermv.kugou.com/play/1080.mp4',
              'backupdownurl': ['http://backup/1080.mp4'],
              'filesize': 1024,
            },
          },
        }),
      ]);
      final repo = _repo(adapter);

      final url = await repo.resolveMvPlayUrl('HASH1080');

      expect(url.url, 'http://trackermv.kugou.com/play/1080.mp4');
      expect(url.backupUrls, ['http://backup/1080.mp4']);
      final req = adapter.seen.single;
      expect(req.uri.path, contains('/v2/interface/index'));
      expect(req.queryParameters['hash'], 'hash1080');
      expect(req.queryParameters['key'], isNotEmpty);
    });

    test('空 hash 抛 NotFound', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      await expectLater(
        repo.resolveMvPlayUrl('  '),
        throwsA(isA<NotFound>()),
      );
      expect(adapter.seen, isEmpty);
    });
  });

  group('setMvCollected — 收藏协议', () {
    test('hash id 直接拒绝，不打网络', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      await expectLater(
        repo.setMvCollected('deadbeefhash', collected: true),
        throwsA(isA<NotFound>()),
      );
      expect(adapter.seen, isEmpty);
    });

    test('未登录抛 LoginRequired', () async {
      final adapter = _ScriptedAdapter([]);
      final repo = _repo(adapter);
      await expectLater(
        repo.setMvCollected('123', collected: true),
        throwsA(isA<LoginRequired>()),
      );
      expect(adapter.seen, isEmpty);
    });

    test('登录后走 collectservice + ctype=2', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      // 明文 JSON 兜底（AES 解密失败时读 raw）。
      final adapter = _ScriptedAdapter([
        '{"status":1,"error_code":0}',
      ]);
      final repo = _repo(adapter);

      await repo.setMvCollected('123', collected: true);

      final req = adapter.seen.single;
      expect(req.uri.host, 'collectservice.kugou.com');
      expect(req.uri.path, '/v1/collect');
      expect(req.queryParameters['p'], isNotEmpty);
      expect(req.queryParameters['key'], isNotEmpty);
    });

    test('取消收藏走 cancel_collect', () async {
      AuthTokenHolder.instance.setSession(token: 'tok', userId: '42');
      final adapter = _ScriptedAdapter([
        '{"status":1,"error_code":0}',
      ]);
      final repo = _repo(adapter);

      await repo.setMvCollected('123', collected: false);

      expect(adapter.seen.single.uri.path, '/v1/cancel_collect');
    });
  });
}
