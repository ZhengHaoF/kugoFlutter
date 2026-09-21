import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/user_repository.dart';
import 'package:kugo/features/auth/auth_controller.dart';
import 'package:kugo/features/likes/likes_controller.dart';
import 'package:kugo/features/likes/likes_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/profile/profile_page.dart';
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
    userId: '8888',
    nickname: '测试达人',
    token: 'test_token',
  );
  final loggedInState = AuthState(
    status: LoginStatus.logged,
    user: testUser,
  );

  group('UserRepository', () {
    test('parses created playlists, collected playlists, and albums correctly',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        final payload = {
          'status': 1,
          'data': {
            'info': [
              {
                'listid': '101',
                'name': '我的自建歌单',
                'pic': 'http://img.kugou.com/cover1.jpg',
                'source': 1,
                'count': 15,
                'list_create_userid': '12345',
              },
              {
                'listid': '102',
                'name': '收藏的他人的歌单',
                'pic': 'http://img.kugou.com/cover2.jpg',
                'source': 1,
                'count': 28,
                'list_create_userid': '99999',
              },
              {
                'listid': '201',
                'list_create_listid': '3001',
                'name': '周杰伦经典专辑',
                'pic': 'http://img.kugou.com/album.jpg',
                'source': 2,
                'count': 10,
                'nickname': '周杰伦',
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
      final res = await repo.fetchUserPlaylists(userId: '12345', token: 'fake_token');

      expect(res.error, isEmpty);
      expect(res.created.length, 1);
      expect(res.created.first.id, '101');
      expect(res.created.first.name, '我的自建歌单');
      expect(res.created.first.trackCount, 15);

      expect(res.collected.length, 1);
      expect(res.collected.first.id, '102');
      expect(res.collected.first.name, '收藏的他人的歌单');
      expect(res.collected.first.trackCount, 28);

      expect(res.albums.length, 1);
      expect(res.albums.first.id, '3001');
      expect(res.albums.first.name, '周杰伦经典专辑');
      expect(res.albums.first.artist, '周杰伦');
      expect(res.albums.first.trackCount, 10);
    });

    test('parses followed singers correctly', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        final payload = {
          'status': 1,
          'data': {
            'lists': [
              {
                'singerid': '1001',
                'nickname': '周杰伦',
                'pic': 'http://img.kugou.com/jay.jpg',
                'source_desc': '华语流行天王',
                'fans_count': 50000000,
                'songcount': 400,
              },
              {
                'singerid': '1002',
                'nickname': '陈奕迅',
                'pic': 'http://img.kugou.com/eason.jpg',
                'source_desc': '香港著名歌手',
                'fans_count': 30000000,
                'songcount': 350,
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
      final res = await repo.fetchUserFollow(userId: '12345', token: 'fake_token');

      expect(res.error, isEmpty);
      expect(res.singers.length, 2);
      expect(res.singers.first.id, '1001');
      expect(res.singers.first.name, '周杰伦');
      expect(res.singers.first.sourceDesc, '华语流行天王');
      expect(res.singers.first.fansCount, 50000000);
      expect(res.singers.first.songCount, 400);

      expect(res.singers.last.name, '陈奕迅');
    });
  });

  group('ProfilePage User Playlists Tabs', () {
    testWidgets('shows playlists when logged in with collections', (tester) async {
      final engine = FakeAudioPlayer();
      const seededState = UserCollectionsState(
        createdPlaylists: [
          PlaylistBrief(
            id: 'p1',
            name: '我的私人珍藏',
            coverUrl: '',
            trackCount: 22,
          ),
        ],
        collectedPlaylists: [
          PlaylistBrief(
            id: 'p2',
            name: '经典摇滚精选',
            coverUrl: '',
            creator: '摇滚迷',
            trackCount: 50,
          ),
        ],
        loaded: true,
      );

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(loggedInState),
          ),
          userCollectionsProvider.overrideWith(() {
            return UserCollectionsNotifier(initialState: seededState);
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Stat tile for 歌单 should show 2 (1 created + 1 collected)
      expect(find.text('2'), findsOneWidget);

      // Scroll to "我的歌单" section
      await tester.scrollUntilVisible(
        find.text('我的歌单'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('我的歌单'), findsOneWidget);
      expect(find.text('自建 (1)'), findsOneWidget);
      expect(find.text('收藏 (1)'), findsOneWidget);

      // First tab (自建)
      expect(find.text('我的私人珍藏'), findsOneWidget);
      expect(find.text('22 首'), findsOneWidget);

      // Switch to 收藏 tab
      await tester.tap(find.text('收藏 (1)'));
      await tester.pumpAndSettle();

      expect(find.text('经典摇滚精选'), findsOneWidget);
      expect(find.text('50 首 · 摇滚迷'), findsOneWidget);
    });

    testWidgets('shows dedicated covers for 我喜欢 and 默认收藏', (tester) async {
      final engine = FakeAudioPlayer();
      const seededState = UserCollectionsState(
        createdPlaylists: [
          PlaylistBrief(
            id: '1',
            name: '默认收藏',
            coverUrl: '',
            isDefault: true,
            trackCount: 0,
          ),
          PlaylistBrief(
            id: '2',
            name: '我喜欢',
            coverUrl: '',
            isDefault: true,
            trackCount: 969,
          ),
        ],
        loaded: true,
      );

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(loggedInState),
          ),
          userCollectionsProvider.overrideWith(() {
            return UserCollectionsNotifier(initialState: seededState);
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('我的歌单'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('默认收藏'), findsOneWidget);
      expect(find.text('我喜欢'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });

  group('LikesPage Multi-dimensional Tabs', () {
    testWidgets('can switch between songs, singers, and albums tabs',
        (tester) async {
      final engine = FakeAudioPlayer();
      const seededState = UserCollectionsState(
        followedSingers: [
          ArtistBrief(
            id: 'a1',
            name: '周杰伦',
            sourceDesc: '华语流行天王',
            songCount: 380,
          ),
          ArtistBrief(
            id: 'a2',
            name: '林俊杰',
            sourceDesc: '金曲歌王',
            songCount: 260,
          ),
        ],
        favoritedAlbums: [
          AlbumBrief(
            id: 'alb1',
            name: '范特西',
            coverUrl: '',
            artist: '周杰伦',
            trackCount: 10,
          ),
          AlbumBrief(
            id: 'alb2',
            name: '江南',
            coverUrl: '',
            artist: '林俊杰',
            trackCount: 12,
          ),
        ],
        loaded: true,
      );

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(loggedInState),
          ),
          userCollectionsProvider.overrideWith(() {
            return UserCollectionsNotifier(initialState: seededState);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Add a like song
      await container.read(likesProvider.notifier).toggle(
            const Track(
              id: 's1',
              name: '半岛铁盒',
              artist: '周杰伦',
              album: '八度空间',
              coverUrl: '',
              durationMs: 240000,
              hash: 'h_s1',
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LikesPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Tab 1: 歌曲 (1)
      expect(find.text('歌曲 (1)'), findsOneWidget);
      expect(find.text('歌手 (2)'), findsOneWidget);
      expect(find.text('专辑 (2)'), findsOneWidget);
      expect(find.text('半岛铁盒'), findsOneWidget);

      // Switch to 歌手 (2)
      await tester.tap(find.text('歌手 (2)'));
      await tester.pumpAndSettle();

      expect(find.text('周杰伦'), findsOneWidget);
      expect(find.text('林俊杰'), findsOneWidget);
      expect(find.text('华语流行天王 · 380 首单曲'), findsOneWidget);

      // Search in 歌手 tab
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '林俊杰');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, '林俊杰'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '周杰伦'), findsNothing);

      // Close search
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Switch to 专辑 (2)
      await tester.tap(find.text('专辑 (2)'));
      await tester.pumpAndSettle();

      expect(find.text('范特西'), findsOneWidget);
      expect(find.text('江南'), findsOneWidget);
      expect(find.text('周杰伦 · 10首'), findsOneWidget);
    });
  });
}
