import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/rank/rank_list_page.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_music_source.dart';

/// 只加榜单能力的离线音源；其余方法走 [FakeMusicSource] 的空实现。
class _RankFake extends FakeMusicSource implements RankSource {
  _RankFake({required super.platform, this.boards = const []});

  List<PlaylistBrief> boards;
  int boardsCalls = 0;

  @override
  Future<List<PlaylistBrief>> rankBoards() async {
    boardsCalls += 1;
    return boards;
  }

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async =>
      const [];
}

PlaylistBrief _board(String id, String name, MusicPlatform platform) =>
    PlaylistBrief(
      id: id,
      name: name,
      coverUrl: '', // 空封面走渐变占位，避免测试触网。
      isRank: true,
      platform: platform,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  Future<void> pumpRankList(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(
      initialLocation: '/ranks',
      routes: [
        GoRoute(path: '/ranks', builder: (_, _) => const RankListPage()),
        GoRoute(
          path: '/rank/:id',
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

  /// 两源场景：酷狗 / 网易各一片榜。
  ({_RankFake kugou, _RankFake netease}) twoSources() {
    final kugou = _RankFake(
      platform: MusicPlatform.kugou,
      boards: [_board('6666', '酷狗飙升榜', MusicPlatform.kugou)],
    );
    final netease = _RankFake(
      platform: MusicPlatform.netease,
      boards: [_board('3778678', '网易热歌榜', MusicPlatform.netease)],
    );
    musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
    return (kugou: kugou, netease: netease);
  }

  testWidgets('两源启用：显示切源栏（无「全部」），并取默认源榜单', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpRankList(tester, container);

    // 榜单不可混排：单源模式，不出现「全部」。
    expect(find.byType(SourceFilterBar), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    expect(find.text('酷狗'), findsOneWidget);
    expect(find.text('网易云'), findsOneWidget);

    // 默认源是网易云 → 只取网易榜单。
    expect(find.text('网易热歌榜'), findsOneWidget);
    expect(sources.netease.boardsCalls, 1);
    expect(sources.kugou.boardsCalls, 0);
  });

  testWidgets('切到酷狗：重新取数并换成酷狗榜单', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpRankList(tester, container);
    expect(find.text('网易热歌榜'), findsOneWidget);

    await tester.tap(find.text('酷狗'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('酷狗飙升榜'), findsOneWidget);
    expect(find.text('网易热歌榜'), findsNothing);
    expect(sources.kugou.boardsCalls, 1);
  });

  testWidgets('单源启用：隐藏切源栏', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou'],
      'settings.defaultSource': 'kugou',
    });

    await pumpRankList(tester, container);

    expect(find.byType(SourceFilterBar), findsNothing);
    expect(find.text('酷狗飙升榜'), findsOneWidget);
    expect(sources.kugou.boardsCalls, 1);
    expect(sources.netease.boardsCalls, 0);
  });

  testWidgets('点击网易榜单：详情路由带 ?src=netease', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpRankList(tester, container);

    await tester.tap(find.text('网易热歌榜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('detail:3778678:src=netease'), findsOneWidget);
  });

  testWidgets('点击酷狗榜单：详情路由不带 src（默认酷狗）', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
    });

    await pumpRankList(tester, container);

    await tester.tap(find.text('酷狗飙升榜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('detail:6666:src='), findsOneWidget);
  });

  testWidgets('无具备榜单能力的可用源：出停用空态', (tester) async {
    // 只有基类能力、没有 RankSource → 榜单页无源可用。
    musicSourceRegistry = MusicSourceRegistry([FakeMusicSource()]);
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
    });

    await pumpRankList(tester, container);

    expect(find.byType(SourceDisabledView), findsOneWidget);
    expect(find.text('酷狗音源已停用'), findsOneWidget);
  });
}
