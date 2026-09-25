import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/catalog_models.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/explore/explore_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/recommend/recommend_hub_page.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 只加「推荐聚合」相关能力的离线音源；其余方法走 [FakeMusicSource] 的空实现。
class _FeedFake extends FakeMusicSource
    implements
        RankSource,
        PlaylistCatalogSource,
        NewSongFeedSource,
        RecommendFeedSource {
  _FeedFake({
    required super.platform,
    this.rankItems = const [],
    this.rankTrackItems = const [],
    this.tagGroups = const [],
    this.catalogPlaylists = const [],
    this.newSongItems = const [],
    this.recommendItems = const [],
    this.editorialItems = const [],
  });

  final List<PlaylistBrief> rankItems;
  final List<Track> rankTrackItems;
  final List<PlaylistTagGroup> tagGroups;
  final List<PlaylistBrief> catalogPlaylists;
  final List<Track> newSongItems;
  final List<PlaylistBrief> recommendItems;
  final List<PlaylistBrief> editorialItems;

  int rankBoardCalls = 0;
  int rankTrackCalls = 0;
  int tagCalls = 0;
  int catalogCalls = 0;
  int newSongCalls = 0;
  int recommendCalls = 0;
  int editorialCalls = 0;

  /// 记录收到的分类值（验证 UI 原样回传 tag id / 首页传空串）。
  final List<String> requestedCats = [];

  /// 记录「推荐歌单」收到的分类值（酷狗专属 categoryid）。
  final List<String> requestedRecommendCats = [];

  @override
  Future<List<PlaylistBrief>> rankBoards() async {
    rankBoardCalls += 1;
    return rankItems;
  }

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async {
    rankTrackCalls += 1;
    return rankTrackItems;
  }

  @override
  Future<List<PlaylistTagGroup>> playlistTagGroups() async {
    tagCalls += 1;
    return tagGroups;
  }

  @override
  Future<List<PlaylistBrief>> categoryPlaylists({
    required String cat,
    int pageSize = 30,
  }) async {
    catalogCalls += 1;
    requestedCats.add(cat);
    return catalogPlaylists;
  }

  @override
  Future<List<Track>> newSongs({int pageSize = 30}) async {
    newSongCalls += 1;
    return newSongItems;
  }

  @override
  Future<List<PlaylistBrief>> recommendPlaylists({
    String cat = '',
    int pageSize = 12,
  }) async {
    recommendCalls += 1;
    requestedRecommendCats.add(cat);
    return recommendItems;
  }

  @override
  Future<List<PlaylistBrief>> editorialPlaylists({int pageSize = 12}) async {
    editorialCalls += 1;
    return editorialItems;
  }
}

PlaylistBrief _pl(String id, String name, MusicPlatform platform) =>
    PlaylistBrief(id: id, name: name, coverUrl: '', platform: platform);

Track _track(String id, String name, MusicPlatform platform) => Track(
      id: id,
      name: name,
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
      durationMs: 200000,
      platform: platform,
    );

PlaylistTagGroup _group(String name, [List<String> more = const []]) =>
    PlaylistTagGroup(
      name: '推荐',
      child: [
        PlaylistTag(id: name, name: name, group: '推荐'),
        for (final m in more) PlaylistTag(id: m, name: m, group: '推荐'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 风格标签 chip（点文字命中的是 label，会触发 hit-test 警告，故点 chip 本体）。
  Finder styleChip(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(ChoiceChip),
      );

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        // 页面会渲染 TrackTile，进而 watch 播放器；不换假引擎会去加载
        // media_kit 原生库（测试环境不可用）。
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container,
    Widget page, {
    // 高视口：页面是懒加载 sliver，矮视口会让折叠线以下的内容不 build，
    // 断言便找不到文本。这里一次性铺开，省去逐个 scrollUntilVisible。
    Size size = const Size(420, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(
      initialLocation: '/page',
      routes: [
        GoRoute(path: '/page', builder: (_, _) => page),
        GoRoute(
          path: '/playlist/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'detail:${state.pathParameters['id']}'
              ':src=${state.uri.queryParameters['src'] ?? ''}',
            ),
          ),
        ),
        GoRoute(
          path: '/rank/:id',
          builder: (_, state) => Scaffold(
            body: Text('rank:${state.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/ranks',
          builder: (_, _) => const Scaffold(body: Text('RANKS_STUB')),
        ),
        GoRoute(
          path: '/discovery',
          builder: (_, _) => const Scaffold(body: Text('DISCOVERY_STUB')),
        ),
        GoRoute(
          path: '/daily',
          builder: (_, _) => const Scaffold(body: Text('DAILY_STUB')),
        ),
        GoRoute(
          path: '/player',
          builder: (_, _) => const Scaffold(body: Text('PLAYER_STUB')),
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
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 两源场景：酷狗 / 网易各一份数据（名字不同，便于断言切源是否真的换源）。
  ({_FeedFake kugou, _FeedFake netease}) twoSources() {
    final kugou = _FeedFake(
      platform: MusicPlatform.kugou,
      rankItems: [_pl('kg-hot', '酷狗热歌榜', MusicPlatform.kugou)],
      rankTrackItems: [_track('kg-s1', '酷狗热歌1', MusicPlatform.kugou)],
      tagGroups: [_group('流派')],
      catalogPlaylists: [_pl('kg-c1', '酷狗分类歌单', MusicPlatform.kugou)],
      newSongItems: [_track('kg-n1', '酷狗新歌1', MusicPlatform.kugou)],
      recommendItems: [_pl('kg-r1', '酷狗推荐歌单', MusicPlatform.kugou)],
      editorialItems: [_pl('kg-e1', '酷狗编辑精选', MusicPlatform.kugou)],
    );
    final netease = _FeedFake(
      platform: MusicPlatform.netease,
      rankItems: [_pl('163-hot', '网易热歌榜', MusicPlatform.netease)],
      rankTrackItems: [_track('163-s1', '网易热歌1', MusicPlatform.netease)],
      tagGroups: [_group('华语', ['欧美'])],
      catalogPlaylists: [_pl('163-c1', '网易风格歌单', MusicPlatform.netease)],
      newSongItems: [_track('163-n1', '网易新歌1', MusicPlatform.netease)],
      recommendItems: [_pl('163-r1', '网易推荐歌单', MusicPlatform.netease)],
      editorialItems: [_pl('163-e1', '网易编辑精选', MusicPlatform.netease)],
    );
    musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
    return (kugou: kugou, netease: netease);
  }

  Widget explorePage() =>
      const Scaffold(body: ExplorePage());

  Widget recommendHub() => const RecommendHubPage();

  group('发现页（首页）按源取数', () {
    testWidgets('默认源网易：四块内容都用网易数据，不带切源栏', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, explorePage());

      // 排行榜（RankSource）
      expect(find.text('排行榜'), findsOneWidget);
      expect(find.text('网易热歌榜'), findsOneWidget);
      expect(find.text('酷狗热歌榜'), findsNothing);
      // 今日热歌（热歌榜 Top）
      expect(find.text('今日热歌'), findsOneWidget);
      expect(find.text('网易热歌1'), findsOneWidget);
      // 新增横排：推荐歌单（PlaylistCatalogSource，空串 = 默认分类）
      expect(find.text('推荐歌单'), findsOneWidget);
      expect(find.text('网易风格歌单'), findsOneWidget);
      // 新增列表：新歌速递（NewSongFeedSource）
      expect(find.text('新歌速递'), findsOneWidget);
      expect(find.text('网易新歌1'), findsOneWidget);

      // 请求全部落在网易，酷狗零请求。
      expect(sources.netease.rankBoardCalls, 1);
      expect(sources.netease.rankTrackCalls, 1);
      expect(sources.netease.catalogCalls, 1);
      expect(sources.netease.requestedCats, ['']);
      expect(sources.netease.newSongCalls, 1);
      expect(sources.kugou.rankBoardCalls, 0);
      expect(sources.kugou.catalogCalls, 0);
      expect(sources.kugou.newSongCalls, 0);

      // 首页是浏览落地页，不做单源切换栏。
      expect(find.byType(SourceFilterBar), findsNothing);
    });

    testWidgets('默认源酷狗：内容回落到酷狗，网易零请求', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'kugou',
      });

      await pumpPage(tester, container, explorePage());

      expect(find.text('酷狗热歌榜'), findsOneWidget);
      expect(find.text('酷狗分类歌单'), findsOneWidget);
      expect(find.text('酷狗新歌1'), findsOneWidget);
      expect(find.text('网易热歌榜'), findsNothing);
      expect(sources.kugou.rankBoardCalls, 1);
      expect(sources.kugou.newSongCalls, 1);
      expect(sources.netease.rankBoardCalls, 0);
      expect(sources.netease.catalogCalls, 0);
      expect(sources.netease.newSongCalls, 0);
    });

    testWidgets('歌单卡片深链带 ?src=（非酷狗源）', (tester) async {
      twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, explorePage());
      await tester.tap(find.text('网易风格歌单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('detail:163-c1:src=netease'), findsOneWidget);
    });

    testWidgets('可用源为 0：内容区出停用空态，不再整页报错', (tester) async {
      // 只注册一个没有任何本页能力的源 → 可用源为 0。
      musicSourceRegistry =
          MusicSourceRegistry([FakeMusicSource(platform: MusicPlatform.netease)]);
      final container = await containerWith({
        'settings.enabledSources': ['netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, explorePage());

      expect(find.byType(SourceDisabledView), findsOneWidget);
      expect(find.textContaining('网易云音源已停用'), findsOneWidget);
    });

    testWidgets('关闭酷狗的「发现」功能：首页回落到网易取数', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'kugou',
        'settings.disabledFeatures': ['kugou:discovery'],
      });

      await pumpPage(tester, container, explorePage());

      expect(find.text('网易热歌榜'), findsOneWidget);
      expect(find.text('酷狗热歌榜'), findsNothing);
      expect(sources.kugou.rankBoardCalls, 0);
      expect(sources.netease.rankBoardCalls, 1);
    });

    testWidgets('两源的「发现」功能都关掉：整页停用且文案归因到功能', (tester) async {
      musicSourceRegistry =
          MusicSourceRegistry([FakeMusicSource(platform: MusicPlatform.netease)]);
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.disabledFeatures': [
          'kugou:discovery',
          'netease:discovery',
        ],
      });

      await pumpPage(tester, container, explorePage());

      expect(find.byType(SourceDisabledView), findsOneWidget);
      // 源都还启用着，锅在功能子开关 → 不能提示「音源已停用」。
      expect(find.text('酷狗的「发现」已关闭'), findsOneWidget);
      expect(find.textContaining('音源已停用'), findsNothing);
    });
  });

  group('为你推荐页按源分发', () {
    testWidgets('两源启用：切源栏（无「全部」）+ 网易形态三板块', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, recommendHub());

      expect(find.byType(SourceFilterBar), findsOneWidget);
      expect(find.text('全部'), findsNothing);
      // 卡片封面角标也会写源名，故只断言切源栏里的 chip。
      final bar = find.byType(SourceFilterBar);
      expect(
        find.descendant(of: bar, matching: find.text('酷狗')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.text('网易云')),
        findsOneWidget,
      );

      // 网易没有风格歌曲流 → 「风格」退化为「风格歌单」（标签 chips + 歌单网格）。
      expect(find.text('风格歌单'), findsOneWidget);
      expect(find.text('风格推荐'), findsNothing);
      expect(find.text('华语'), findsOneWidget);
      expect(find.text('网易风格歌单'), findsOneWidget);
      expect(sources.netease.tagCalls, 1);
      expect(sources.netease.requestedCats, ['华语']);

      // 推荐歌单 / 编辑精选：网易个性推荐 + 精品歌单。
      expect(find.text('网易推荐歌单'), findsOneWidget);
      expect(find.text('网易编辑精选'), findsOneWidget);
      expect(sources.netease.recommendCalls, 1);
      expect(sources.netease.editorialCalls, 1);

      // 分类 chips 是酷狗口径，网易下不显示；酷狗侧零请求。
      expect(find.text('Hi-Res'), findsNothing);
      expect(sources.kugou.recommendCalls, 0);
      expect(sources.kugou.editorialCalls, 0);
    });

    testWidgets('切换风格标签：只重取歌单，不重取标签，重复点当前标签忽略', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, recommendHub());
      // 首屏取标签 + 用首个标签取歌单。
      expect(sources.netease.tagCalls, 1);
      expect(sources.netease.catalogCalls, 1);
      expect(sources.netease.requestedCats, ['华语']);

      // 切到另一个标签 → 只按新分类重取歌单，标签不重取。
      await tester.tap(styleChip('欧美'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(sources.netease.catalogCalls, 2);
      expect(sources.netease.requestedCats, ['华语', '欧美']);
      expect(sources.netease.tagCalls, 1);

      // 重复点当前标签 → 直接忽略，不再发请求。
      await tester.tap(styleChip('欧美'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(sources.netease.catalogCalls, 2);
      expect(sources.netease.tagCalls, 1);
    });

    testWidgets('单源启用：隐藏切源栏', (tester) async {
      final sources = twoSources();
      final container = await containerWith({
        'settings.enabledSources': ['netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, recommendHub());

      expect(find.byType(SourceFilterBar), findsNothing);
      expect(find.text('网易推荐歌单'), findsOneWidget);
      expect(sources.kugou.recommendCalls, 0);
    });

    testWidgets('可用源为 0：整页停用空态', (tester) async {
      musicSourceRegistry =
          MusicSourceRegistry([FakeMusicSource(platform: MusicPlatform.netease)]);
      final container = await containerWith({
        'settings.enabledSources': ['netease'],
        'settings.defaultSource': 'netease',
      });

      await pumpPage(tester, container, recommendHub());

      expect(find.byType(SourceDisabledView), findsOneWidget);
    });
  });
}
