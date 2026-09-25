import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/catalog_models.dart';
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

/// 只加「发现页」三项能力的离线音源；其余方法走 [FakeMusicSource] 的空实现。
class _DiscoveryFake extends FakeMusicSource
    implements PlaylistCatalogSource, NewSongFeedSource, RankSource {
  _DiscoveryFake({
    required super.platform,
    this.tagGroups = const [],
    this.playlists = const [],
    this.newSongItems = const [],
  });

  final List<PlaylistTagGroup> tagGroups;
  final List<PlaylistBrief> playlists;
  final List<Track> newSongItems;

  int tagCalls = 0;
  int playlistCalls = 0;
  int newSongCalls = 0;

  /// 记录 `categoryPlaylists` 收到的分类值（验证 UI 原样回传 tag id）。
  final List<String> requestedCats = [];

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
    expect(find.text('酷狗'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);

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

  testWidgets('网易源：新碟上架出「暂不支持」空态，不建假入口', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    // 宽屏：五个 Tab 全部可见，免得 tap 落在可滚动 TabBar 的裁剪区外。
    await pumpDiscovery(tester, container, size: const Size(900, 1000));

    await tester.tap(find.text('新碟上架'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('暂不支持「新碟上架」'), findsOneWidget);
    expect(find.text('暂无新碟'), findsNothing);
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
