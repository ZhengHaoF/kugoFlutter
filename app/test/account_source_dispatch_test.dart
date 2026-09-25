import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/data/storage/kugo_db.dart';
import 'package:kugo/data/storage/queue_store.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:kugo/features/profile/netease_collections_controller.dart';
import 'package:kugo/features/profile/profile_detail_page.dart';
import 'package:kugo/features/profile/profile_page.dart';
import 'package:kugo/features/profile/source_account.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';

import 'fakes/fake_device_login_source.dart';
import 'fakes/fake_music_source.dart';

/// 测试用假「用户歌单」源：不碰网络，可注入错误。
class FakeUserPlaylistReadSource implements UserPlaylistReadSource {
  UserPlaylistsPage page = const UserPlaylistsPage();
  Object? error;
  int calls = 0;

  @override
  Future<UserPlaylistsPage> userPlaylists({
    int offset = 0,
    int limit = 1000,
  }) async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return page;
  }
}

PlaylistBrief _playlist(
  String id,
  String name, {
  bool isDefault = false,
  MusicPlatform platform = MusicPlatform.netease,
}) =>
    PlaylistBrief(
      id: id,
      name: name,
      coverUrl: '',
      trackCount: 3,
      isDefault: isDefault,
      platform: platform,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('mapNeteaseUserPlaylists', () {
    test('自建 / 收藏按 subscribed 分流，specialType==5 归自建并打 isDefault', () {
      const raw = '{"code":200,"more":false,"playlist":['
          '{"id":1,"name":"我喜欢的音乐","trackCount":1009,'
          '"specialType":5,"subscribed":true,"coverImgUrl":"http://p/l.jpg"},'
          '{"id":2,"name":"我的自建","trackCount":3,"subscribed":false},'
          '{"id":3,"name":"收藏的歌单","trackCount":10,"subscribed":true}]}';
      final page = mapNeteaseUserPlaylists(raw);

      expect(page.created.map((p) => p.name), ['我喜欢的音乐', '我的自建']);
      expect(page.collected.map((p) => p.name), ['收藏的歌单']);
      expect(page.more, isFalse);

      final liked = page.created.first;
      expect(liked.isDefault, isTrue);
      expect(liked.trackCount, 1009);
      // http → https，与 _pic 同口径。
      expect(liked.coverUrl, 'https://p/l.jpg');
      expect(liked.platform, MusicPlatform.netease);
    });

    test('more=true 透传', () {
      expect(
        mapNeteaseUserPlaylists('{"code":200,"more":true,"playlist":[]}').more,
        isTrue,
      );
    });

    test('playlist 缺失 / 非数组返回空（不抛）', () {
      expect(
        mapNeteaseUserPlaylists('{"code":200}').created,
        isEmpty,
      );
      expect(
        mapNeteaseUserPlaylists('{"code":200,"playlist":"x"}').collected,
        isEmpty,
      );
    });

    test('业务码非 200 抛 SourceFailure', () {
      expect(
        () => mapNeteaseUserPlaylists('{"code":301}'),
        throwsA(isA<SourceFailure>()),
      );
    });
  });

  group('NeteaseCollectionsNotifier', () {
    ProviderContainer makeContainer(
      FakeUserPlaylistReadSource playlists,
      FakeDeviceLoginSource login,
    ) {
      final container = ProviderContainer(
        overrides: [
          neteaseCollectionsSourceProvider.overrideWithValue(playlists),
          neteaseLoginSourceProvider.overrideWithValue(login),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('未登录不发请求，只给「需登录」提示', () async {
      final playlists = FakeUserPlaylistReadSource()
        ..page = UserPlaylistsPage(
          created: [_playlist('1', '我喜欢的音乐', isDefault: true)],
        );
      final c = makeContainer(playlists, FakeDeviceLoginSource());

      await c.read(neteaseCollectionsProvider.notifier).load();

      expect(playlists.calls, 0);
      expect(c.read(neteaseCollectionsProvider).error, '需登录后查看');
      expect(c.read(neteaseCollectionsProvider).created, isEmpty);
    });

    test('登录态回填后自动拉取歌单，并能找到「我喜欢」', () async {
      final playlists = FakeUserPlaylistReadSource()
        ..page = UserPlaylistsPage(
          created: [
            _playlist('1', '我喜欢的音乐', isDefault: true),
            _playlist('2', '我的自建'),
          ],
          collected: [_playlist('3', '收藏的歌单')],
        );
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(playlists, login);

      c.listen(neteaseCollectionsProvider, (_, _) {});
      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await waitFor(() => c.read(neteaseCollectionsProvider).loaded);

      final s = c.read(neteaseCollectionsProvider);
      expect(playlists.calls, 1);
      expect(s.totalPlaylistsCount, 3);
      expect(s.likedPlaylist?.name, '我喜欢的音乐');
      expect(s.error, isEmpty);
    });

    test('失败时保留错误文案且不抛', () async {
      final playlists = FakeUserPlaylistReadSource()
        ..error = const NotFound('取歌单失败');
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(playlists, login);

      // 登录态一变，notifier 会自动发起一次 load（不 await），故等它落地。
      c.listen(neteaseCollectionsProvider, (_, _) {});
      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await waitFor(() => c.read(neteaseCollectionsProvider).loaded);

      final s = c.read(neteaseCollectionsProvider);
      expect(s.loaded, isTrue);
      expect(s.error, contains('取歌单失败'));
      expect(s.totalPlaylistsCount, 0);
    });

    test('登出清空已加载的歌单', () async {
      final playlists = FakeUserPlaylistReadSource()
        ..page = UserPlaylistsPage(created: [_playlist('1', '我的自建')]);
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final c = makeContainer(playlists, login);

      c.listen(neteaseCollectionsProvider, (_, _) {});
      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      await waitFor(() => c.read(neteaseCollectionsProvider).loaded);
      expect(c.read(neteaseCollectionsProvider).totalPlaylistsCount, 1);

      await c.read(neteaseLoginControllerProvider.notifier).logout();

      expect(c.read(neteaseCollectionsProvider).totalPlaylistsCount, 0);
      expect(c.read(neteaseCollectionsProvider).loaded, isFalse);
    });
  });

  group('账号源', () {
    Future<ProviderContainer> containerWith(
      Map<String, Object> prefs, {
      List<Override> overrides = const [],
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      musicSourceRegistry = MusicSourceRegistry([
        FakeMusicSource(platform: MusicPlatform.kugou),
        FakeMusicSource(platform: MusicPlatform.netease),
      ]);
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.notifier).ensureRestored();
      return container;
    }

    test('默认取设置里的默认源，可页面级切换', () async {
      final c = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      expect(c.read(accountSourcePlatformsProvider),
          [MusicPlatform.kugou, MusicPlatform.netease]);
      expect(c.read(effectiveAccountSourceProvider), MusicPlatform.netease);

      c.read(accountSourceProvider.notifier).state = MusicPlatform.kugou;
      expect(c.read(effectiveAccountSourceProvider), MusicPlatform.kugou);
    });

    test('单源启用：账号源只有一个（切源条由组件自行隐藏）', () async {
      final c = await containerWith({
        'settings.enabledSources': ['kugou'],
        'settings.defaultSource': 'kugou',
      });

      expect(c.read(accountSourcePlatformsProvider), [MusicPlatform.kugou]);
      expect(c.read(effectiveAccountSourceProvider), MusicPlatform.kugou);
    });

    test('选择值对应的源被停用：回退默认源', () async {
      final c = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      c.read(accountSourceProvider.notifier).state = MusicPlatform.kugou;
      await c.read(settingsControllerProvider.notifier).setEnabledSources(
            {MusicPlatform.netease},
          );

      expect(c.read(effectiveAccountSourceProvider), MusicPlatform.netease);
    });

    test('网易账号摘要来自登录控制器', () async {
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(
          userId: '42',
          nickname: '小明',
          avatarUrl: 'https://p/a.jpg',
          isVip: true,
        );
      final c = await containerWith(
        {
          'settings.enabledSources': ['kugou', 'netease'],
          'settings.defaultSource': 'netease',
        },
        overrides: [neteaseLoginSourceProvider.overrideWithValue(login)],
      );

      expect(c.read(sourceAccountProvider(MusicPlatform.netease)).isLogged,
          isFalse);

      await c.read(neteaseLoginControllerProvider.notifier).refreshAccount();
      final a = c.read(sourceAccountProvider(MusicPlatform.netease));
      expect(a.isLogged, isTrue);
      expect(a.nickname, '小明');
      expect(a.userId, '42');
      expect(a.isVip, isTrue);
    });

    test('登录路由按源区分', () {
      expect(loginRouteFor(MusicPlatform.kugou), '/login');
      expect(loginRouteFor(MusicPlatform.netease), '/netease-login');
    });
  });

  group('「我的」页按账号源渲染', () {
    // 「我的」页会读本地播放历史条数，给个内存库免得落到真实文件。
    late KugoDb db;
    setUp(() {
      db = KugoDb.forTesting(NativeDatabase.memory());
      QueueStore.setDbForTesting(db);
    });
    tearDown(() {
      QueueStore.setDbForTesting(null);
      db.close();
    });

    ProviderContainer containerWith({
      required List<String> enabledSources,
      required String defaultSource,
      FakeUserPlaylistReadSource? playlists,
      FakeDeviceLoginSource? login,
    }) {
      SharedPreferences.setMockInitialValues({
        'settings.enabledSources': enabledSources,
        'settings.defaultSource': defaultSource,
      });
      musicSourceRegistry = MusicSourceRegistry([
        FakeMusicSource(platform: MusicPlatform.kugou),
        FakeMusicSource(platform: MusicPlatform.netease),
      ]);
      final container = ProviderContainer(
        overrides: [
          neteaseCollectionsSourceProvider
              .overrideWithValue(playlists ?? FakeUserPlaylistReadSource()),
          neteaseLoginSourceProvider
              .overrideWithValue(login ?? FakeDeviceLoginSource()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<void> pumpPage(WidgetTester tester, ProviderContainer container,
        Widget page) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => page),
          GoRoute(
            path: '/profile/detail',
            builder: (_, _) => const Scaffold(body: Text('个人中心页')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('酷狗登录页')),
          ),
          GoRoute(
            path: '/netease-login',
            builder: (_, _) => const Scaffold(body: Text('网易登录页')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('多源启用：出账号切源条，默认源为网易云时走网易口径', (tester) async {
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));

      expect(find.byType(SourceFilterBar), findsOneWidget);
      expect(find.text('全部'), findsNothing);
      expect(find.text('酷狗'), findsOneWidget);
      expect(find.text('网易云'), findsOneWidget);
      // 网易未登录 → 空态文案与登录按钮走网易。
      expect(find.text('登录网易云账号后，即可同步自建与收藏歌单'), findsOneWidget);

      await tester.tap(find.text('立即登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('网易登录页'), findsOneWidget);
    });

    testWidgets('切到酷狗：空态文案与登录按钮改走酷狗', (tester) async {
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));

      await tester.tap(find.text('酷狗'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('登录酷狗账号后，即可同步自建与收藏歌单'), findsOneWidget);
      expect(find.text('登录网易云账号后，即可同步自建与收藏歌单'), findsNothing);

      await tester.tap(find.text('立即登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('酷狗登录页'), findsOneWidget);
    });

    testWidgets('单源启用：不出切源条', (tester) async {
      final container = containerWith(
        enabledSources: ['netease'],
        defaultSource: 'netease',
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));

      expect(find.byType(SourceFilterBar), findsNothing);
      expect(find.text('登录网易云账号后，即可同步自建与收藏歌单'), findsOneWidget);
    });

    testWidgets('网易已登录：展示昵称与云端歌单', (tester) async {
      final playlists = FakeUserPlaylistReadSource()
        ..page = UserPlaylistsPage(
          created: [_playlist('1', '我喜欢的音乐', isDefault: true)],
          collected: [_playlist('3', '收藏的歌单')],
        );
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(
          userId: '42',
          nickname: '小明',
          isVip: true,
        );
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
        playlists: playlists,
        login: login,
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));

      expect(find.text('小明'), findsOneWidget);
      expect(find.text('黑胶会员'), findsOneWidget);
      expect(find.text('我喜欢的音乐'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
    });

    testWidgets('个人中心：网易侧不出酷狗等级块，未登录时提示按源区分', (tester) async {
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );

      await pumpPage(tester, container, const ProfileDetailPage());

      expect(find.text('请先登录网易云账号'), findsOneWidget);
      expect(find.text('升级进度'), findsNothing);
    });

    testWidgets('个人中心：网易已登录时隐藏等级/档案区块', (tester) async {
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
        login: login,
      );

      await pumpPage(tester, container, const ProfileDetailPage());

      expect(find.text('小明'), findsOneWidget);
      expect(find.text('升级进度'), findsNothing);
      expect(find.text('账号档案'), findsNothing);
      expect(find.text('会员状态'), findsNothing);
      expect(find.textContaining('暂不提供等级'), findsOneWidget);
    });
  });
}
