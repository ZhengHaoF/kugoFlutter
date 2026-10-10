import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/repositories/cloud_repository.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/cloud/cloud_upload_picker.dart';
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

ResponseBody _json(Object body) {
  return ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
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

  group('parseCloudFileName', () {
    test('splits Artist - Title and strips extension', () {
      final r = parseCloudFileName('周杰伦 - 晴天.flac');
      expect(r.artist, '周杰伦');
      expect(r.title, '晴天');
    });

    test('falls back to full basename as title', () {
      final r = parseCloudFileName('晴天.mp3');
      expect(r.artist, '');
      expect(r.title, '晴天');
    });
  });

  group('CloudRepository.uploadCloudFile', () {
    test('second-upload path: empty upload_id skips multipart', () async {
      final dio = Dio();
      final paths = <String>[];
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        paths.add(options.uri.path);
        if (options.uri.path.endsWith('upload/auth')) {
          return _json({
            'status': 1,
            'data': {'authorization': 'AUTH_TOKEN'},
          });
        }
        if (options.uri.path.endsWith('initiate/music')) {
          // 秒传：无 upload_id
          return _json({
            'status': 1,
            'data': {
              'x-bss-filename': 'serverhash',
            },
          });
        }
        if (options.uri.path.endsWith('get_list') ||
            options.uri.path.endsWith('add_files')) {
          // mcloud 信封 → 明文 JSON 回落
          return _json({'status': 1, 'error_code': 0});
        }
        if (options.uri.path.endsWith('album_audio/audio')) {
          return _json({
            'status': 1,
            'data': [
              {
                'album_audio_id': 555,
                'audio_info': {'audio_id': 777, 'hash': 'stdhash'},
                'author_name': '周杰伦',
                'audio_name': '晴天',
              },
            ],
          });
        }
        return _json({'status': 0, 'msg': 'unexpected ${options.uri}'});
      });

      final repo = CloudRepository(dio: dio);
      final result = await repo.uploadCloudFile(
        bytes: utf8.encode('fake-audio-bytes'),
        title: '晴天',
        extendname: 'mp3',
        authorName: '周杰伦',
      );

      expect(result.secondUpload, isTrue);
      expect(result.matched, isTrue);
      expect(result.hash, 'serverhash');
      // 秒传不应打分片上传/完成口
      expect(paths.any((p) => p.endsWith('multipart/upload')), isFalse);
      expect(paths.any((p) => p.endsWith('multipart/complete')), isFalse);
      expect(paths.any((p) => p.endsWith('add_files')), isTrue);
    });

    test('full multipart path when upload_id present', () async {
      final dio = Dio();
      final paths = <String>[];
      var completeCalled = false;
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        paths.add(options.uri.path);
        if (options.uri.path.endsWith('upload/auth')) {
          return _json({
            'status': 1,
            'data': {'authorization': 'AUTH_TOKEN'},
          });
        }
        if (options.uri.path.endsWith('initiate/music')) {
          return _json({
            'status': 1,
            'data': {
              'upload_id': 'UP1',
              'external_host': 'http://bssulbig.kugou.com',
              'x-bss-filename': 'abc',
            },
          });
        }
        if (options.uri.path.endsWith('multipart/upload')) {
          expect(options.uri.scheme, 'https');
          expect(options.followRedirects, isFalse);
          return _json({'status': 1});
        }
        if (options.uri.path.endsWith('multipart/complete')) {
          completeCalled = true;
          return _json({
            'status': 1,
            'data': {'x-bss-filename': 'finalhash'},
          });
        }
        if (options.uri.path.endsWith('add_files')) {
          return _json({'status': 1});
        }
        return _json({'status': 0, 'msg': 'unexpected ${options.uri}'});
      });

      final repo = CloudRepository(dio: dio);
      // 2.5 个分片 → 3 次 upload
      final bytes = List<int>.filled(2 * 1024 * 1024 + 100, 1);
      final result = await repo.uploadCloudFile(
        bytes: bytes,
        title: 'X',
        extendname: 'flac',
      );

      expect(result.secondUpload, isFalse);
      expect(result.hash, 'finalhash');
      expect(completeCalled, isTrue);
      expect(
        paths.where((p) => p.endsWith('multipart/upload')).length,
        3,
      );
    });

    test('requires login', () async {
      AuthTokenHolder.instance.clear();
      final repo = CloudRepository(dio: Dio());
      await expectLater(
        repo.uploadCloudFile(bytes: [1], title: 'a', extendname: 'mp3'),
        throwsA(isA<LoginRequired>()),
      );
    });
  });
}
