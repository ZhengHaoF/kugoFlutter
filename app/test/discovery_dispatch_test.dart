import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/catalog_models.dart';
import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/discovery/discovery_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 只加「发现页」各项能力的离线音源；其余方法走 [FakeMusicSource] 的空实现。
class _DiscoveryFake extends FakeMusicSource
    implements
        PlaylistCatalogSource,
        NewSongFeedSource,
        NewAlbumFeedSource,
        ArtistListSource,
        RankSource {
  _DiscoveryFake({
    required super.platform,
    this.tagGroups = const [],
    this.playlists = const [],
    this.newSongItems = const [],
    this.albumItems = const [],
    this.artistItems = const [],
    this.albumRegions = const [
      (id: 'all', label: '全部'),
      (id: 'chn', label: '华语'),
    ],
    this.artistGenderOptions = const [
      (id: '-1', label: '全部'),
      (id: '1', label: '男'),
    ],
    this.artistStyleOptions = const [
      (id: '0:0', label: '全部'),
      (id: '1:0', label: '流行'),
    ],
    this.artistInitialOptions = const [
      (id: '', label: '全部'),
      (id: 'A', label: 'A'),
    ],
  });

  final List<PlaylistTagGroup> tagGroups;
  final List<PlaylistBrief> playlists;
  final List<Track> newSongItems;
  final List<AlbumBrief> albumItems;
  final List<ArtistBrief> artistItems;

  @override
  final List<({String id, String label})> albumRegions;

  @override
  final List<({String id, String label})> artistGenderOptions;

  @override
  final List<({String id, String label})> artistStyleOptions;

  @override
  final List<({String id, String label})> artistInitialOptions;

  int tagCalls = 0;
  int playlistCalls = 0;
  int newSongCalls = 0;
  int newAlbumCalls = 0;
  int artistListCalls = 0;

  /// 记录 `categoryPlaylists` 收到的分类值（验证 UI 原样回传 tag id）。
  final List<String> requestedCats = [];

  /// 记录 `newAlbums` 收到的地区值（验证 UI 原样回传能力给的 id）。
  final List<String> requestedRegions = [];

  /// 记录 `artistList` 收到的三项筛选值。
  final List<({String gender, String style, String initial})>
      requestedArtistFilters = [];

  @override
  Future<List<AlbumBrief>> newAlbums({
    required String region,
    int pageSize = 30,
  }) async {
    newAlbumCalls += 1;
    requestedRegions.add(region);
    return albumItems;
  }

  @override
  Future<List<ArtistBrief>> artistList({
    required String gender,
    required String style,
    required String initial,
    int pageSize = 30,
  }) async {
    artistListCalls += 1;
    requestedArtistFilters.add(
      (gender: gender, style: style, initial: initial),
    );
    return artistItems;
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
    playlistCalls += 1;
    requestedCats.add(cat);
    return playlists;
  }

  @override
  Future<List<Track>> newSongs({int pageSize = 30}) async {
    newSongCalls += 1;
    return newSongItems;
  }

  @override
  Future<List<PlaylistBrief>> rankBoards() async => const [];

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async =>
      const [];
}

/// 只有榜单能力的音源：用来验证「能力缺失 → 该 Tab 出暂不支持空态」。
class _RankOnlyFake extends FakeMusicSource implements RankSource {
  @override
  Future<List<PlaylistBrief>> rankBoards() async => const [];

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async =>
      const [];
}

PlaylistTagGroup _group(String name) => PlaylistTagGroup(
      name: '推荐',
      child: [PlaylistTag(id: name, name: name, group: '推荐')],
    );

PlaylistBrief _playlist(String id, String name, MusicPlatform platform) =>
    PlaylistBrief(
      id: id,
      name: name,
      coverUrl: '', // 空封面走渐变占位，避免测试触网。
      platform: platform,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        // 新歌速递 / 榜单 Tab 会渲染 TrackTile，进而 watch 播放器；
        // 不换假引擎会去加载 media_kit 原生库（测试环境不可用）。
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  Future<void> pumpDiscovery(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(
      initialLocation: '/discovery',
      routes: [
        GoRoute(path: '/discovery', builder: (_, _) => const DiscoveryPage()),
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
          path: '/album/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'album:${state.pathParameters['id']}'
              ':src=${state.uri.queryParameters['src'] ?? ''}',
            ),
          ),
        ),
        GoRoute(
          path: '/artist/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'artist:${state.pathParameters['id']}'
              ':src=${state.uri.queryParameters['src'] ?? ''}',
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('设置页')),
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

  /// 两源场景：酷狗 / 网易各一份歌单（名字不同，便于断言切源是否真的换源）。
  ({_DiscoveryFake kugou, _DiscoveryFake netease}) twoSources({
    List<Track> neteaseNewSongs = const [],
    List<AlbumBrief> neteaseAlbums = const [],
    List<ArtistBrief> neteaseArtists = const [],
  }) {
    final kugou = _DiscoveryFake(
      platform: MusicPlatform.kugou,
      tagGroups: [_group('流派')],
      playlists: [_playlist('kg-1', '酷狗歌单', MusicPlatform.kugou)],
    );
    final netease = _DiscoveryFake(
      platform: MusicPlatform.netease,
      tagGroups: [_group('华语')],
      playlists: [_playlist('163-1', '网易歌单', MusicPlatform.netease)],
      newSongItems: neteaseNewSongs,
      albumItems: neteaseAlbums,
      artistItems: neteaseArtists,
      // 各源原生筛选值（网易口径），验证 UI 只渲染并原样回传。
      albumRegions: const [
        (id: 'ALL', label: '全部'),
        (id: 'ZH', label: '华语'),
      ],
      artistGenderOptions: const [
        (id: '-1', label: '全部'),
        (id: '1', label: '男'),
        (id: '2', label: '女'),
      ],
      artistStyleOptions: const [
        (id: '-1', label: '全部'),
        (id: '7', label: '华语'),
        (id: '96', label: '欧美'),
      ],
      artistInitialOptions: const [
        (id: '', label: '全部'),
        (id: 'A', label: 'A'),
        (id: 'B', label: 'B'),
      ],
    );
    musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
    return (kugou: kugou, netease: netease);
  }

  testWidgets('两源启用：显示切源栏（无「全部」），并取默认源歌单', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container);

    // 歌单不可混排：单源模式，不出现「全部」。
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

    // 默认源是网易云 → 只取网易歌单与网易分类。
    expect(find.text('网易歌单'), findsOneWidget);
    expect(sources.netease.playlistCalls, 1);
    expect(sources.netease.tagCalls, 1);
    // 分类值原样回传标签 id（网易即标签名）。
    expect(sources.netease.requestedCats, ['华语']);
    expect(sources.kugou.playlistCalls, 0);
    expect(sources.kugou.tagCalls, 0);
  });

  testWidgets('切到酷狗：清缓存重取，换成酷狗标签与歌单', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container);
    expect(find.text('网易歌单'), findsOneWidget);
    expect(find.text('华语'), findsOneWidget);

    await tester.tap(find.text('酷狗'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('酷狗歌单'), findsOneWidget);
    expect(find.text('网易歌单'), findsNothing);
    // 旧源的标签也必须清掉，否则会串源。
    expect(find.text('流派'), findsOneWidget);
    expect(find.text('华语'), findsNothing);
    expect(sources.kugou.playlistCalls, 1);
    expect(sources.kugou.requestedCats, ['流派']);
  });

  testWidgets('单源启用：隐藏切源栏', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou'],
      'settings.defaultSource': 'kugou',
    });

    await pumpDiscovery(tester, container);

    expect(find.byType(SourceFilterBar), findsNothing);
    expect(find.text('酷狗歌单'), findsOneWidget);
    expect(sources.kugou.playlistCalls, 1);
    expect(sources.netease.playlistCalls, 0);
  });

  testWidgets('网易源：新碟上架走 NewAlbumFeedSource，地区取值来自能力并原样回传', (tester) async {
    final sources = twoSources(
      neteaseAlbums: const [
        AlbumBrief(
          id: '163-al-1',
          name: '网易新碟',
          coverUrl: '',
          artist: '周杰伦',
          platform: MusicPlatform.netease,
        ),
      ],
    );
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    // 宽屏：五个 Tab 全部可见，免得 tap 落在可滚动 TabBar 的裁剪区外。
    await pumpDiscovery(tester, container, size: const Size(900, 1000));

    await tester.tap(find.text('新碟上架'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('网易新碟'), findsOneWidget);
    expect(find.textContaining('暂不支持「新碟上架」'), findsNothing);
    expect(sources.netease.newAlbumCalls, 1);
    // 首次取地区默认项 = 能力给出的首项。
    expect(sources.netease.requestedRegions, ['ALL']);
    expect(sources.kugou.newAlbumCalls, 0);

    // 点第二个地区 chip（本 Tab 只有一行 chips）→ 原样回传该能力项的 id。
    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(sources.netease.requestedRegions, ['ALL', 'ZH']);
  });

  testWidgets('点击网易新碟：详情路由带 ?src=netease', (tester) async {
    twoSources(
      neteaseAlbums: const [
        AlbumBrief(
          id: '163-al-1',
          name: '网易新碟',
          coverUrl: '',
          platform: MusicPlatform.netease,
        ),
      ],
    );
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container, size: const Size(900, 1000));
    await tester.tap(find.text('新碟上架'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('网易新碟'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('album:163-al-1:src=netease'), findsOneWidget);
  });

  testWidgets('网易源：歌手 Tab 走 ArtistListSource，三项筛选取自能力并原样回传', (tester) async {
    final sources = twoSources(
      neteaseArtists: const [
        ArtistBrief(
          id: '163-ar-1',
          name: '网易歌手',
          avatarUrl: '',
          platform: MusicPlatform.netease,
        ),
      ],
    );
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container, size: const Size(900, 1000));
    await tester.tap(find.text('歌手'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('网易歌手'), findsOneWidget);
    expect(find.textContaining('暂不支持「歌手」'), findsNothing);
    expect(sources.netease.artistListCalls, 1);
    // 首帧三项都取能力给的首项（不筛）。
    expect(
      sources.netease.requestedArtistFilters,
      [(gender: '-1', style: '-1', initial: '')],
    );
    expect(sources.kugou.artistListCalls, 0);

    await tester.tap(find.widgetWithText(ChoiceChip, '男'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, '欧美'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ChoiceChip, 'A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      sources.netease.requestedArtistFilters.last,
      (gender: '1', style: '96', initial: 'A'),
    );
  });

  testWidgets('点击网易歌手：详情路由带 ?src=netease', (tester) async {
    twoSources(
      neteaseArtists: const [
        ArtistBrief(
          id: '163-ar-1',
          name: '网易歌手',
          avatarUrl: '',
          platform: MusicPlatform.netease,
        ),
      ],
    );
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container, size: const Size(900, 1000));
    await tester.tap(find.text('歌手'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('网易歌手'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('artist:163-ar-1:src=netease'), findsOneWidget);
  });

  testWidgets('源缺能力：新碟上架 / 歌手 Tab 出「暂不支持」空态，不建假入口', (tester) async {
    // 只有榜单能力的源 → 新碟上架与歌手都无能力，但本页仍有可用源（不出整页停用）。
    musicSourceRegistry = MusicSourceRegistry([_RankOnlyFake()]);
    final container = await containerWith({
      'settings.enabledSources': ['kugou'],
      'settings.defaultSource': 'kugou',
    });

    await pumpDiscovery(tester, container, size: const Size(900, 1000));
    expect(find.byType(SourceDisabledView), findsNothing);

    await tester.tap(find.text('新碟上架'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('暂不支持「新碟上架」'), findsOneWidget);
    expect(find.text('暂无新碟'), findsNothing);

    await tester.tap(find.text('歌手'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('暂不支持「歌手」'), findsOneWidget);
    expect(find.text('暂无歌手'), findsNothing);
  });

  testWidgets('网易源：新歌速递 Tab 走 NewSongFeedSource 取曲目', (tester) async {
    final sources = twoSources(
      neteaseNewSongs: const [
        Track(
          id: '186016',
          name: '网易新歌',
          artist: '周杰伦',
          album: '叶惠美',
          coverUrl: '',
          durationMs: 269000,
          platform: MusicPlatform.netease,
        ),
      ],
    );
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container, size: const Size(900, 1000));

    await tester.tap(find.text('新歌速递'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('网易新歌'), findsOneWidget);
    expect(sources.netease.newSongCalls, 1);
    expect(sources.kugou.newSongCalls, 0);
  });

  testWidgets('点击网易歌单：详情路由带 ?src=netease', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpDiscovery(tester, container);

    await tester.tap(find.text('网易歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('detail:163-1:src=netease'), findsOneWidget);
  });

  testWidgets('点击酷狗歌单：详情路由不带 src（默认酷狗）', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
    });

    await pumpDiscovery(tester, container);

    await tester.tap(find.text('酷狗歌单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('detail:kg-1:src='), findsOneWidget);
  });

  testWidgets('无具备发现页能力的可用源：出整页停用空态', (tester) async {
    // 只有基类能力、没有歌单/榜单/新歌能力 → 发现页无源可用。
    musicSourceRegistry = MusicSourceRegistry([FakeMusicSource()]);
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
    });

    await pumpDiscovery(tester, container);

    expect(find.byType(SourceDisabledView), findsOneWidget);
    expect(find.text('酷狗音源已停用'), findsOneWidget);
  });

  testWidgets('关闭酷狗的「发现」功能：该源从本页可用源中移除', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
      'settings.disabledFeatures': ['kugou:discovery'],
    });

    await pumpDiscovery(tester, container);

    // 只剩网易一个可用源 → 隐藏切源栏，直接取网易数据。
    expect(find.byType(SourceFilterBar), findsNothing);
    expect(find.text('网易歌单'), findsOneWidget);
    expect(sources.netease.playlistCalls, 1);
    expect(sources.kugou.playlistCalls, 0);
  });

  testWidgets('两源的「发现」功能都关掉：整页停用且文案归因到功能', (tester) async {
    musicSourceRegistry = MusicSourceRegistry([FakeMusicSource()]);
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.disabledFeatures': [
        'kugou:discovery',
        'netease:discovery',
      ],
    });

    await pumpDiscovery(tester, container);

    expect(find.byType(SourceDisabledView), findsOneWidget);
    // 源都还启用着，锅在功能子开关 → 不能提示「音源已停用」。
    expect(find.text('酷狗的「发现」已关闭'), findsOneWidget);
    expect(find.text('酷狗音源已停用'), findsNothing);
  });
}
