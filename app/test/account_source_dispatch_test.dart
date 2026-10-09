import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/api/netease/netease_account_models.dart';
import 'package:kugo/core/api/netease/netease_account_source.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/models/cloud_models.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/data/storage/kugo_db.dart';
import 'package:kugo/data/storage/queue_store.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:kugo/features/cloud/cloud_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/profile/netease_account_profile.dart';
import 'package:kugo/features/profile/netease_collections_controller.dart';
import 'package:kugo/features/profile/profile_detail_page.dart';
import 'package:kugo/features/profile/profile_page.dart';
import 'package:kugo/features/profile/source_account.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';

import 'fakes/fake_audio_player.dart';
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

/// 带云盘能力的假源：单独子类，不污染 [FakeMusicSource]（否则
/// 「两源都没云盘」用例会永远显示入口——`capability<T>()` 是 `is T` 判定）。
class _FakeCloudMusicSource extends FakeMusicSource
    implements CloudDiskSource {
  _FakeCloudMusicSource(MusicPlatform platform, {required this.page})
      : super(platform: platform);

  final CloudDiskPage page;
  final List<String> requestedPages = [];

  @override
  bool get isCloudDiskLoggedIn => true;

  @override
  Future<CloudDiskPage> fetchCloudDiskPage({
    int page = 1,
    int pageSize = 30,
  }) async {
    requestedPages.add('page=$page,size=$pageSize');
    return this.page;
  }

  @override
  Future<PlayUrlResult> resolveCloudPlayUrl(Track track) async =>
      nextPlayUrl!;

  @override
  Future<void> deleteCloudTracks(List<CloudDeleteTarget> targets) async {}
}

/// 测试用假「账号档案」源（H 组三口）：不碰网络，可注入错误。
///
/// 不 override 的话 `neteaseAccountProfileProvider` 会落到全局
/// `neteaseSource`，widget 测试直接打真实网易云。
class FakeNeteaseAccountSource implements NeteaseAccountSource {
  NeteaseUserDetail detail = NeteaseUserDetail.empty;
  NeteaseVipInfo vip = NeteaseVipInfo.empty;
  NeteaseLevelInfo level = NeteaseLevelInfo.empty;
  Object? error;
  int calls = 0;

  @override
  Future<NeteaseUserDetail> userDetail(int uid) async {
    calls++;
    _throwIfNeeded();
    return detail;
  }

  @override
  Future<NeteaseVipInfo> vipInfo({required int userId}) async {
    _throwIfNeeded();
    return vip;
  }

  @override
  Future<NeteaseLevelInfo> userLevel() async {
    _throwIfNeeded();
    return level;
  }

  void _throwIfNeeded() {
    final e = error;
    if (e != null) throw e;
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
      UserPlaylistsPage? libraryPage,
      FakeNeteaseAccountSource? account,
    }) {
      SharedPreferences.setMockInitialValues({
        'settings.enabledSources': enabledSources,
        'settings.defaultSource': defaultSource,
      });
      final kugou = FakeMusicSource(platform: MusicPlatform.kugou);
      final netease = FakeMusicSource(platform: MusicPlatform.netease)
        ..libraryPage = libraryPage ??
            (playlists != null
                ? UserPlaylistsPage(
                    created: playlists.page.created,
                    collected: playlists.page.collected,
                  )
                : const UserPlaylistsPage());
      if (playlists?.error != null) {
        netease.libraryError = playlists!.error;
      }
      musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
      final container = ProviderContainer(
        overrides: [
          neteaseLoginSourceProvider
              .overrideWithValue(login ?? FakeDeviceLoginSource()),
          // 不 override 会落到全局 neteaseSource → widget 测试打真实网络。
          neteaseAccountSourceProvider
              .overrideWithValue(account ?? FakeNeteaseAccountSource()),
          // 云盘页 build 会 watch 播放器（MediaKit 未初始化会炸），统一顶掉。
          playerControllerProvider
              .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<GoRouter> pumpPage(WidgetTester tester, ProviderContainer container,
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
          GoRoute(path: '/cloud', builder: (_, _) => const CloudPage()),
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
      return router;
    }

    testWidgets('云盘页按账号源取数：网易源出网易的盘', (tester) async {
      final netease = _FakeCloudMusicSource(
        MusicPlatform.netease,
        page: CloudDiskPage(
          tracks: const [
            Track(
              id: '2165810543',
              name: '独庄子（3）',
              artist: '未知艺术家',
              album: '',
              coverUrl: '',
              durationMs: 1370196,
              cloudFileId: '2165810543',
            ),
          ],
          total: 1,
          capacity: const CloudDiskCapacity(
            usedBytes: 20795339420,
            totalBytes: 64424509440,
          ),
        ),
      );
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );
      // 只给网易云盘能力：酷狗源没有（模拟「酷狗侧没实现」）。
      musicSourceRegistry = MusicSourceRegistry([
        FakeMusicSource(platform: MusicPlatform.kugou),
        netease,
      ]);

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));
      await tester.tap(find.text('音乐云盘'));
      await tester.pumpAndSettle();

      expect(find.text('独庄子（3）'), findsOneWidget);
      // 容量条该出现（19.3G / 60G）；多源启用时顶部是切源栏而非只读小字。
      expect(find.textContaining('60'), findsWidgets);
      expect(find.byType(SourceFilterBar), findsOneWidget);
      expect(netease.requestedPages, isNotEmpty);
    });

    testWidgets('云盘页内可直接切源：chips 一点就换盘', (tester) async {
      final kugou = _FakeCloudMusicSource(
        MusicPlatform.kugou,
        page: const CloudDiskPage(
          tracks: [
            Track(
              id: 'hash-k',
              name: '酷狗云盘曲',
              artist: '歌手',
              album: '',
              coverUrl: '',
              durationMs: 1000,
              cloudFileId: '99',
            ),
          ],
          total: 1,
        ),
      );
      final netease = _FakeCloudMusicSource(
        MusicPlatform.netease,
        page: const CloudDiskPage(
          tracks: [
            Track(
              id: '2165810543',
              name: '网易云盘曲',
              artist: '未知艺术家',
              album: '',
              coverUrl: '',
              durationMs: 1370196,
              cloudFileId: '2165810543',
            ),
          ],
          total: 1,
        ),
      );
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );
      musicSourceRegistry = MusicSourceRegistry([kugou, netease]);

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));
      await tester.tap(find.text('音乐云盘'));
      await tester.pumpAndSettle();
      expect(find.text('网易云盘曲'), findsOneWidget);

      // 云盘页内的切源栏（不用回「我的」页）。
      expect(find.byType(SourceFilterBar), findsOneWidget);
      await tester.tap(find.text('酷狗'));
      await tester.pumpAndSettle();
      expect(find.text('酷狗云盘曲'), findsOneWidget);
      expect(find.text('网易云盘曲'), findsNothing);
      // 切源同时同步全局默认源（与其它多源页面同口径）。
      expect(
        container.read(settingsControllerProvider).defaultSource,
        MusicPlatform.kugou,
      );
    });

    testWidgets('单源启用：云盘页只给只读来源小字，不出 chips', (tester) async {
      final container = containerWith(
        enabledSources: ['netease'],
        defaultSource: 'netease',
      );
      musicSourceRegistry = MusicSourceRegistry([
        _FakeCloudMusicSource(
          MusicPlatform.netease,
          page: const CloudDiskPage(
            tracks: [
              Track(
                id: '1',
                name: '网易云盘曲',
                artist: 'a',
                album: '',
                coverUrl: '',
                durationMs: 1,
                cloudFileId: '1',
              ),
            ],
            total: 1,
          ),
        ),
      ]);

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));
      await tester.tap(find.text('音乐云盘'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceFilterBar), findsNothing);
      expect(find.textContaining('来源：网易云'), findsOneWidget);
    });

    testWidgets('账号源切到酷狗：云盘页跟着换（不混源）', (tester) async {
      final kugou = _FakeCloudMusicSource(
        MusicPlatform.kugou,
        page: const CloudDiskPage(
          tracks: [
            Track(
              id: 'hash-k',
              name: '酷狗云盘曲',
              artist: '歌手',
              album: '',
              coverUrl: '',
              durationMs: 1000,
              cloudFileId: '99',
            ),
          ],
          total: 1,
        ),
      );
      final netease = _FakeCloudMusicSource(
        MusicPlatform.netease,
        page: const CloudDiskPage(
          tracks: [
            Track(
              id: '2165810543',
              name: '网易云盘曲',
              artist: '未知艺术家',
              album: '',
              coverUrl: '',
              durationMs: 1370196,
              cloudFileId: '2165810543',
            ),
          ],
          total: 1,
        ),
      );
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );
      musicSourceRegistry = MusicSourceRegistry([kugou, netease]);

      final router = await pumpPage(
        tester,
        container,
        const Scaffold(body: ProfilePage()),
      );
      await tester.tap(find.text('音乐云盘'));
      await tester.pumpAndSettle();
      expect(find.text('网易云盘曲'), findsOneWidget);

      // 回「我的」页切账号源 → 再进云盘，应换成酷狗的盘。
      container.read(accountSourceProvider.notifier).state =
          MusicPlatform.kugou;
      router.go('/profile');
      await tester.pumpAndSettle();
      await tester.tap(find.text('音乐云盘'));
      await tester.pumpAndSettle();
      expect(find.text('酷狗云盘曲'), findsOneWidget);
      expect(find.text('网易云盘曲'), findsNothing);
    });

    testWidgets('入口显隐看能力：只有网易有云盘时仍显示', (tester) async {
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );
      musicSourceRegistry = MusicSourceRegistry([
        FakeMusicSource(platform: MusicPlatform.kugou),
        _FakeCloudMusicSource(
          MusicPlatform.netease,
          page: const CloudDiskPage(
            tracks: [
              Track(
                id: '1',
                name: '网易云盘曲',
                artist: 'a',
                album: '',
                coverUrl: '',
                durationMs: 1,
                cloudFileId: '1',
              ),
            ],
            total: 1,
          ),
        ),
      ]);

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));
      expect(find.text('音乐云盘'), findsOneWidget);
    });

    testWidgets('入口显隐看能力：两源都没云盘时隐藏', (tester) async {
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));
      expect(find.text('音乐云盘'), findsNothing);
    });

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
        libraryPage: playlists.page,
        login: login,
      );

      await pumpPage(tester, container, const Scaffold(body: ProfilePage()));

      expect(find.text('小明'), findsOneWidget);
      expect(find.text('黑胶会员'), findsOneWidget);
      expect(find.text('我喜欢的音乐'), findsOneWidget);
      // 「退出登录」已从「我的」页搬到「个人中心」页尾，本页不再出现。
      expect(find.text('退出登录'), findsNothing);
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

    testWidgets('个人中心：网易已登录时显示等级/档案/会员区块', (tester) async {
      final login = FakeDeviceLoginSource()
        ..account = const LoginAccount(userId: '42', nickname: '小明');
      // 2026-10-09 H 组落地后网易侧不再只有一句「暂不提供」，
      // 等级 / 关注粉丝 / 档案 / 会员状态全部有真数据。
      final account = FakeNeteaseAccountSource()
        ..detail = const NeteaseUserDetail(
          userId: '42',
          nickname: '小明',
          signature: '网易云签名',
          level: 9,
          listenSongs: 10904,
          follows: 16,
          followeds: 1,
          playlistCount: 8,
          cloudBeanBalance: 0,
          createTime: 1536474759615,
          gender: 0,
          provinceCode: '330000',
        )
        ..level = const NeteaseLevelInfo(
          level: 9,
          progress: 0.242,
          nowPlayCount: 2904,
          nextPlayCount: 12000,
          nowLoginCount: 350,
          nextLoginCount: 350,
          privileges: ['60G音乐网盘免费容量', '云贝商城满100减12元优惠券'],
        )
        ..vip = const NeteaseVipInfo(
          level: 7,
          heijiao: NeteaseVipMembership(
            vipCode: 100,
            expireTime: 1786031999000,
            vipLevel: 7,
          ),
          musicPackage: NeteaseVipMembership(
            vipCode: 220,
            expireTime: 1786031999000,
            vipLevel: 7,
          ),
        );
      final container = containerWith(
        enabledSources: ['kugou', 'netease'],
        defaultSource: 'netease',
        login: login,
        account: account,
      );

      await pumpPage(tester, container, const ProfileDetailPage());
      // 等 H 组三个并发请求落地。
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('小明'), findsOneWidget);
      expect(find.text('网易云签名'), findsOneWidget);
      // 等级一行：等级 / 关注 / 粉丝（网易没有访客，那格不出）。
      expect(find.text('升级进度'), findsOneWidget);
      expect(find.text('Lv.9'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      // 档案 + 会员状态。
      expect(find.text('账号档案'), findsOneWidget);
      expect(find.text('会员状态'), findsOneWidget);
      expect(find.text('黑胶VIP'), findsOneWidget);
      expect(find.text('音乐包'), findsOneWidget);
      // 「暂不提供」那句说明应该没了。
      expect(find.textContaining('暂不提供等级'), findsNothing);
      // 档案两列对齐（和酷狗源同一套 _ArchiveRow）：标签左边缘成列、数值贴右。
      for (final label in const [
        '用户 ID',
        '性别',
        '乐龄',
        '累计听歌',
        '所在地区',
        '云贝',
        '自建歌单',
      ]) {
        final rowFinder = find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        ).first;
        expect(
          tester.getRect(
            find.descendant(of: rowFinder, matching: find.byType(Text)).at(1),
          ).right,
          moreOrLessEquals(tester.getRect(rowFinder).right, epsilon: 0.5),
          reason: '「$label」的数值没有贴右',
        );
      }
      // 退出登录入口在页尾红字行，两源通用（登录态才渲染）。
      expect(find.text('退出登录'), findsOneWidget);
    });
  });
}
