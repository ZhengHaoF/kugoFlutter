/// MV 入口（`mv_entry.dart`）的单测 + widget 测试。
///
/// 钉住三件事：
///  · 门控——`mixSongId` + `MvSearchSource` 能力，缺一即不入口；
///  · 缓存——同曲第二次不再打接口，空结果也缓存；
///  · 交互——点击跳 `/mv`，无 MV 时只提示不跳转。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/mv_models.dart';
import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/mv/mv_entry.dart';
import 'package:kugo/shared/widgets/common.dart';

import 'fakes/fake_music_source.dart';

/// MV 源：可控返回 + 记录调用次数（[FakeMusicSource] 本身不实现 MvSearchSource）。
class _MvFakeSource extends FakeMusicSource implements MvSearchSource {
  _MvFakeSource({this.mvs = const []});

  List<MvBrief> mvs;
  int songMvCalls = 0;

  @override
  Future<SearchPageResult<MvBrief>> searchMvs(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async => const SearchPageResult.empty();

  @override
  Future<List<MvBrief>> songMvs(Track track) async {
    songMvCalls++;
    return mvs;
  }

  @override
  Future<SearchPageResult<MvBrief>> fetchArtistMvs(
    String authorId, {
    int page = 1,
    int pageSize = 30,
    String tag = '',
  }) async => const SearchPageResult.empty();
}

Track _track({
  String mixSongId = '32100650',
  MusicPlatform platform = MusicPlatform.kugou,
}) => Track(
  id: mixSongId.isEmpty ? 'x' : mixSongId,
  name: '晴天',
  artist: '周杰伦',
  album: '叶惠美',
  coverUrl: '',
  durationMs: 269000,
  mixSongId: mixSongId,
  platform: platform,
);

MvBrief _mv() => const MvBrief(
  id: '987654',
  hash: 'aabbccdd',
  name: '晴天 MV',
  coverUrl: '',
  artist: '周杰伦',
  mixSongId: '32100650',
);

Future<void> _pumpButton(WidgetTester tester, Track track) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: Center(child: MvEntryButton(track: track))),
      ),
      GoRoute(
        path: '/mv',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('MV-PAGE:${state.uri.queryParameters['id']}'),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    musicSourceRegistry = null;
    clearMvCache();
  });
  tearDown(() {
    musicSourceRegistry = null;
    clearMvCache();
  });

  group('canOpenMv — 宽松门控', () {
    test('registry 未装配 → false', () {
      expect(canOpenMv(_track()), isFalse);
    });

    test('无 mixSongId → false（即便有能力）', () {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource()]);
      expect(canOpenMv(_track(mixSongId: '')), isFalse);
    });

    test('音源未实现 MvSearchSource → false', () {
      musicSourceRegistry = MusicSourceRegistry([
        FakeMusicSource(platform: MusicPlatform.netease),
      ]);
      expect(
        canOpenMv(_track(mixSongId: '1', platform: MusicPlatform.netease)),
        isFalse,
      );
    });

    test('有 mixSongId + 能力 → true', () {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource()]);
      expect(canOpenMv(_track()), isTrue);
    });
  });

  group('loadSongMvs — 短路与缓存', () {
    test('无 mixSongId：空列表且不打网络', () async {
      final src = _MvFakeSource();
      musicSourceRegistry = MusicSourceRegistry([src]);
      expect(await loadSongMvs(_track(mixSongId: '')), isEmpty);
      expect(src.songMvCalls, 0);
    });

    test('无 MvSearchSource 能力：空列表且不打网络', () async {
      musicSourceRegistry = MusicSourceRegistry([FakeMusicSource()]);
      expect(await loadSongMvs(_track()), isEmpty);
    });

    test('首次拉取并缓存：第二次不再调源', () async {
      final src = _MvFakeSource(mvs: [_mv()]);
      musicSourceRegistry = MusicSourceRegistry([src]);

      final first = await loadSongMvs(_track());
      final second = await loadSongMvs(_track());

      expect(first, hasLength(1));
      expect(second.single.id, '987654');
      expect(src.songMvCalls, 1, reason: '缓存命中不应重复请求');
    });

    test('空结果也缓存：不重复请求', () async {
      final src = _MvFakeSource(mvs: const []);
      musicSourceRegistry = MusicSourceRegistry([src]);

      await loadSongMvs(_track());
      await loadSongMvs(_track());

      expect(src.songMvCalls, 1);
    });
  });

  group('MvEntryButton — 显隐与跳转', () {
    testWidgets('有能力且带 mixSongId：露出 MV 图标', (tester) async {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource(mvs: [_mv()])]);
      await _pumpButton(tester, _track());

      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('无 mixSongId：不占位（图标不渲染）', (tester) async {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource(mvs: [_mv()])]);
      await _pumpButton(tester, _track(mixSongId: ''));

      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });

    testWidgets('点图标 → 跳 /mv 并带上 id', (tester) async {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource(mvs: [_mv()])]);
      await _pumpButton(tester, _track());

      await tester.tap(find.byIcon(Icons.videocam_outlined));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('MV-PAGE:987654'), findsOneWidget);
    });

    testWidgets('无 MV：只提示「这首歌暂无 MV」，不跳转', (tester) async {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource(mvs: const [])]);
      await _pumpButton(tester, _track());

      await tester.tap(find.byIcon(Icons.videocam_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('这首歌暂无 MV'), findsOneWidget);
      expect(find.textContaining('MV-PAGE'), findsNothing);
    });
  });

  group('TrackTile — 行级 hover 显隐', () {
    AnimatedOpacity mvOpacity(WidgetTester tester) => tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byIcon(Icons.videocam_outlined),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );

    Future<void> pumpTile(WidgetTester tester) async {
      musicSourceRegistry = MusicSourceRegistry([_MvFakeSource(mvs: [_mv()])]);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackTile(track: _track()))),
      );
      await tester.pump();
    }

    testWidgets('桌面：整行 hover 才显现 MV 图标', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpTile(tester);

      expect(mvOpacity(tester).opacity, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(TrackTile)));
      await tester.pump();

      expect(mvOpacity(tester).opacity, 1);
    });

    testWidgets('移动端：无 hover 也常驻', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpTile(tester);

      expect(mvOpacity(tester).opacity, 1);
    });
  });
}