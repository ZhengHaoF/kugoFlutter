import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';
import 'package:kugo/core/models/cloud_models.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/repositories/cloud_repository.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBytes(Map<String, dynamic> body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    encoded,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthTokenHolder.instance.clearDevice();
    AuthTokenHolder.instance.setSession(
      token: 'tok',
      userId: '123456',
      mid: 'mid-1',
      guid: 'guid-1',
      dfid: 'dfid-1',
    );
  });

  tearDown(AuthTokenHolder.instance.clearDevice);

  group('mapCloudTrack', () {
    test('maps kv_id / hash / capacity fields with multi-key fallback', () {
      final track = mapCloudTrack({
        'kv_id': 9001,
        'hash': 'AABBCCDD',
        'hash_std': 'EEFF0011',
        'filename': '周杰伦 - 晴天.flac',
        'author_name': '周杰伦',
        'album_name': '叶惠美',
        'timelen': 269000,
        'bitrate': 4,
        'size': 12345678,
        'ext': 'flac',
        'album_info': {
          'sizable_cover': 'http://imge.kugou.com/{size}/cover.jpg',
        },
        'album_audio_id': 555,
        'audio_id': 777,
      });

      expect(track.cloudFileId, '9001');
      expect(track.id, '9001');
      expect(track.hash, 'aabbccdd');
      expect(track.name, '周杰伦 - 晴天');
      expect(track.artist, '周杰伦');
      expect(track.durationMs, 269000);
      expect(track.cloudAudioSource?.hashStd, 'eeff0011');
      expect(track.cloudAudioSource?.albumAudioId, '555');
      expect(track.cloudAudioSource?.audioId, '777');
      expect(track.cloudAudioSource?.bitrate, 4);
      expect(track.isCloudTrack, isTrue);
    });

    test('falls back to hash id when kv_id missing; artist from filename', () {
      final track = mapCloudTrack({
        'hash': 'deadbeef',
        'filename': '林俊杰 - 江南.mp3',
        'duration': 200,
      });

      expect(track.cloudFileId, '');
      expect(track.id, 'deadbeef');
      expect(track.artist, '林俊杰');
      expect(track.name, '林俊杰 - 江南');
      expect(track.durationMs, 200000);
      expect(track.isCloudTrack, isTrue);
    });

    test('mapCloudCapacity reads max_size / availble_size spelling', () {
      final cap = mapCloudCapacity({
        'max_size': 10000,
        'used_size': 4000,
        'availble_size': 6000,
      });
      expect(cap.totalBytes, 10000);
      expect(cap.usedBytes, 4000);
      expect(cap.availableBytes, 6000);
      expect(cap.usedRatio, closeTo(0.4, 0.001));
    });

    test('cloudDeleteTargetFromTrack prefers kv_id over hash', () {
      final track = mapCloudTrack({
        'kv_id': 42,
        'hash': 'abc',
        'album_audio_id': 7,
        'filename': 'A - B.mp3',
      });
      final target = cloudDeleteTargetFromTrack(track);
      expect(target.cloudFileId, '42');
      expect(target.hash, 'abc');
      expect(target.albumAudioId, '7');
      expect(target.canDelete, isTrue);
    });
  });

  group('CloudRepository', () {
    test('fetchCloudDiskPage requires login', () async {
      AuthTokenHolder.instance.clear();
      final repo = CloudRepository(dio: Dio());
      await expectLater(
        repo.fetchCloudDiskPage(),
        throwsA(isA<LoginRequired>()),
      );
    });

    test('fetchCloudDiskPage maps list + capacity and dedups ids', () async {
      final dio = Dio();
      var called = 0;
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        called++;
        expect(options.uri.path, '/v1/get_list');
        return _jsonBytes({
          'status': 1,
          'data': {
            'list_count': 3,
            'max_size': 100,
            'used_size': 40,
            'availble_size': 60,
            'list': [
              {
                'kv_id': 1,
                'hash': 'aaa',
                'filename': 'A - 一.mp3',
                'timelen': 10000,
              },
              {
                'kv_id': 1,
                'hash': 'bbb',
                'filename': 'B - 二.mp3',
                'timelen': 20000,
              },
              {
                'kv_id': 3,
                'hash': 'ccc',
                'filename': 'C - 三.mp3',
                'timelen': 30000,
              },
            ],
          },
        });
      });

      final repo = CloudRepository(dio: dio);
      final page = await repo.fetchCloudDiskPage(page: 1, pageSize: 30);

      expect(called, 1);
      expect(page.total, 3);
      expect(page.tracks.length, 3);
      expect(page.capacity.totalBytes, 100);
      // Duplicate kv_id gets a suffix so queue keys stay unique.
      expect(page.tracks[0].id, '1');
      expect(page.tracks[1].id, '1_2');
      expect(page.tracks[2].id, '3');
    });

    test('resolveCloudPlayUrl uses signCloudKey and returns backup urls', () async {
      final dio = Dio();
      RequestOptions? recorded;
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        recorded = options;
        expect(options.uri.path, contains('query_musicclound_url'));
        expect(options.queryParameters['bucket'], 'musicclound');
        expect(options.queryParameters['pid'], 20026);
        expect(options.queryParameters['hash'], 'aabb');
        return ResponseBody.fromString(
          jsonEncode({
            'status': 1,
            'data': {
              'url': 'https://cdn.example/a.mp3',
              'backup_url': ['https://cdn.example/b.mp3', 'https://cdn.example/a.mp3'],
            },
          }),
          200,
        );
      });

      final repo = CloudRepository(dio: dio);
      final track = mapCloudTrack({
        'kv_id': 9,
        'hash': 'AABB',
        'filename': 'X - Y.mp3',
      });
      final result = await repo.resolveCloudPlayUrl(track);

      expect(result.url, 'https://cdn.example/a.mp3');
      // Duplicate backup dropped.
      expect(result.backupUrls, ['https://cdn.example/b.mp3']);
      expect(recorded!.queryParameters.containsKey('signature'), isTrue);
      expect(recorded!.queryParameters['key'], isNotEmpty);
    });

    test('deleteCloudTracks sends kv_id list and reports skipped', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        expect(options.uri.path, '/v1/del_files');
        // Body is AES ciphertext; decrypt is covered by envelope tests.
        // Ensure RSA p is present and no android signature.
        expect(options.queryParameters.containsKey('p'), isTrue);
        expect(options.queryParameters.containsKey('signature'), isFalse);
        return _jsonBytes({'status': 1, 'error_code': 0});
      });

      final repo = CloudRepository(dio: dio);
      await repo.deleteCloudTracks([
        const CloudDeleteTarget(cloudFileId: '11', albumAudioId: '22'),
        const CloudDeleteTarget(hash: 'onlyhash'),
      ]);

      expect(repo.lastError, contains('1 首缺少文件标识'));
    });

    test('deleteCloudTracks rejects when no file id at all', () async {
      final repo = CloudRepository(dio: Dio());
      await expectLater(
        repo.deleteCloudTracks([const CloudDeleteTarget(hash: 'abc')]),
        throwsA(isA<NotFound>()),
      );
    });
  });
}
