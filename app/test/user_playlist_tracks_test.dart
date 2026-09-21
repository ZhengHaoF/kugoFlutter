import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/user_repository.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/playlist/playlist_detail_page.dart';
import 'package:kugo/features/profile/user_collections_controller.dart';
import 'fakes/fake_audio_player.dart';

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

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final testUser = AuthUser(
    userId: '123456',
    nickname: '酷狗音乐达人',
    token: 'test_token_abc',
  );
  final loggedInState = AuthState(
    status: LoginStatus.logged,
    user: testUser,
  );

  group('fetchUserPlaylistTracks', () {
    test('calls /v4/get_list_all_file_v3 with proper headers, params, and maps songs',
        () async {
      final dio = Dio();
      RequestOptions? recordedOptions;

      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        recordedOptions = options;
        final payload = {
          'status': 1,
          'errcode': 0,
          'error': '',
          'data': {
            'list_ver': 9,
            'total': 969,
            'count': 2,
            'info': [
              {
                'fileid': 1001,
                'hash': 'A1B2C3D4E5F6789012345678901234AB',
                'songname': '晴天',
                'singername': '周杰伦',
                'album_name': '叶惠美',
                'album_id': '101',
                'timelen': 269000,
                'pic': 'http://img.kugou.com/cover/qingtian.jpg',
                'privilege': 0,
              },
              {
                'fileid': 1002,
                'hash': 'B2C3D4E5F6789012345678901234ABCD',
                'audio_info': {
                  'hash': 'B2C3D4E5F6789012345678901234ABCD',
                  'songname': '夜曲',
                  'author_name': '周杰伦',
                  'album_name': '十一月的萧邦',
                  'duration': 225,
                },
                'privilege': 10,
              },
            ],
          },
        };

        return ResponseBody.fromString(
          jsonEncode(payload),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final repo = UserRepository(dio: dio);
      final result = await repo.fetchUserPlaylistTracks(
        listId: '2',
        userId: testUser.userId,
        token: testUser.token,
        type: 0,
        page: 1,
        pageSize: 300,
      );

      expect(recordedOptions, isNotNull);
      expect(recordedOptions!.path, contains('/v4/get_list_all_file_v3'));
      expect(recordedOptions!.headers['x-router'], 'cloudlist.service.kugou.com');
      expect(recordedOptions!.headers['Cookie'], contains('token=test_token_abc'));
      expect(recordedOptions!.headers['Cookie'], contains('userid=123456'));

      final body = jsonDecode(recordedOptions!.data.toString()) as Map;
      expect(body['listid'], 2);
      expect(body['userid'], 123456);
      expect(body['type'], 0);
      expect(body['pagesize'], 300);
      expect(body['token'], 'test_token_abc');

      expect(result.error, isEmpty);
      expect(result.total, 969);
      expect(result.tracks.length, 2);

      final track1 = result.tracks[0];
      expect(track1.name, '晴天');
      expect(track1.artist, '周杰伦');
      expect(track1.album, '叶惠美');
      expect(track1.hash, 'a1b2c3d4e5f6789012345678901234ab');
      expect(track1.durationMs, 269000);
      expect(track1.coverUrl, contains('qingtian.jpg'));
      expect(track1.isVip, false);

      final track2 = result.tracks[1];
      expect(track2.name, '夜曲');
      expect(track2.artist, '周杰伦');
      expect(track2.album, '十一月的萧邦');
      expect(track2.hash, 'b2c3d4e5f6789012345678901234abcd');
      expect(track2.durationMs, 225000);
      expect(track2.isVip, true);
    });

    test('returns error when status is 0 or network is intercepted', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        final payload = {
          'status': 0,
          'error': '登录态失效',
        };
        return ResponseBody.fromString(
          jsonEncode(payload),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final repo = UserRepository(dio: dio);
      final result = await repo.fetchUserPlaylistTracks(
        listId: '2',
        userId: testUser.userId,
        token: testUser.token,
      );

      expect(result.error, '登录态失效');
      expect(result.tracks, isEmpty);
    });
  });

  group('UserCollectionsController favorite tracks sync', () {
    test('loadFavoriteTracks populates cloudFavoriteTracks from default playlist',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        if (options.path.contains('/v7/get_all_list')) {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 1,
              'data': {
                'info': [
                  {
                    'listid': '2',
                    'name': '我喜欢',
                    'is_def': 1,
                    'source': 1,
                    'count': 969,
                    'list_create_userid': '123456',
                  }
                ]
              }
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else if (options.path.contains('/v4/get_list_all_file_v3')) {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 1,
              'data': {
                'total': 969,
                'info': [
                  {
                    'hash': 'A1B2C3D4E5F678901234567890123456',
                    'songname': '稻香',
                    'singername': '周杰伦',
                    'timelen': 223000,
                  }
                ]
              }
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else {
          return ResponseBody.fromString(
            jsonEncode({'status': 1, 'data': {'lists': []}}),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
      });

      final repo = UserRepository(dio: dio);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(loggedInState)),
          userCollectionsProvider.overrideWith(
            () => UserCollectionsNotifier(repository: repo),
          ),
        ],
      );

      final notifier = container.read(userCollectionsProvider.notifier);
      await notifier.loadPlaylists();

      final state = container.read(userCollectionsProvider);
      expect(state.createdPlaylists.length, 1);
      expect(state.createdPlaylists.first.isDefault, true);
      expect(state.cloudFavoriteTracks.length, 1);
      expect(state.cloudFavoriteTracks.first.name, '稻香');
      expect(state.cloudFavoriteTracks.first.artist, '周杰伦');
    });
  });

  group('PlaylistDetailPage with user cloud playlist', () {
    testWidgets('renders tracks loaded via userRepository when opening user playlist',
        (tester) async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        if (options.path.contains('/v4/get_list_all_file_v3')) {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 1,
              'data': {
                'total': 969,
                'info': [
                  {
                    'hash': 'TEST_HASH_CLOUD_1',
                    'songname': '青花瓷',
                    'singername': '周杰伦',
                    'timelen': 240000,
                  }
                ]
              }
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString(
          jsonEncode({'status': 1, 'data': null}),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

      final repo = UserRepository(dio: dio);
      final fakePlayer = FakeAudioPlayer();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(loggedInState)),
            playerControllerProvider.overrideWith(
              () => PlayerController(engine: fakePlayer),
            ),
            userCollectionsProvider.overrideWith(
              () => UserCollectionsNotifier(
                repository: repo,
                initialState: UserCollectionsState(
                  createdPlaylists: [
                    const PlaylistBrief(
                      id: '2',
                      name: '我喜欢',
                      coverUrl: '',
                      trackCount: 969,
                      isDefault: true,
                      userId: '123456',
                    )
                  ],
                  loaded: true,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: PlaylistDetailPage(
              id: '2',
              userRepository: repo,
              initialBrief: const PlaylistBrief(
                id: '2',
                name: '我喜欢',
                coverUrl: '',
                trackCount: 969,
                isDefault: true,
                userId: '123456',
              ),
            ),
          ),
        ),
      );

      // Settle async loading
      await tester.pumpAndSettle();

      // Verify song from /v4/get_list_all_file_v3 is rendered
      expect(find.text('我喜欢'), findsWidgets);
      expect(find.text('青花瓷'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);
      // No error message
      expect(find.textContaining('加载失败'), findsNothing);
    });
  });
}
