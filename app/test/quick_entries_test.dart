import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/explore/quick_entries.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

/// 不 pump [ExplorePage]：它的 initState 会发起真实网络请求，
/// dio 的超时 Timer 在 FakeAsync 里永远挂起（"A Timer is still pending"）。
/// [QuickEntries] 本身无网络，单独 pump 即可覆盖布局与导航。
class _FakeSearch implements SearchRepository {
  final List<String> calls = [];

  @override
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    calls.add(keyword);
    return List.generate(
      4,
      (i) => Track(
        id: '$keyword-$i',
        name: '$keyword-$i',
        artist: 'artist',
        album: 'album',
        coverUrl: 'http://cover/$keyword',
        durationMs: 10000,
      ),
    );
  }

  @override
  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      SearchPageResult(items: await searchSongs(keyword, pageSize: pageSize));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({GoRouter router, _FakeSearch search})> pump(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final search = _FakeSearch();
    final router = GoRouter(
      initialLocation: '/entries',
      routes: [
        GoRoute(
          path: '/entries',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: QuickEntries(),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('PLAYER_STUB'))),
        ),
        GoRoute(
          path: '/daily',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('DAILY_STUB'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fmControllerProvider.overrideWith(() => FmController(search: search)),
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: FakeAudioPlayer()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return (router: router, search: search);
  }

  testWidgets('FM hero takes its own full-width row above the daily card',
      (tester) async {
    await pump(tester);

    final hero = tester.getRect(find.byKey(const ValueKey('fm_hero_card')));
    final daily = tester.getRect(find.byKey(const ValueKey('daily_entry_card')));

    // 800 视口 - 左右 16 padding = 768：两张卡都吃满整行，FM 不再是半宽格。
    expect(hero.width, 768);
    expect(daily.width, 768);
    // Hero 在上、每日推荐在下。
    expect(hero.bottom, lessThanOrEqualTo(daily.top));
  });

  testWidgets('FM hero starts a session and lands on the player',
      (tester) async {
    final rig = await pump(tester);

    expect(find.byKey(const ValueKey('fm_vinyl')), findsOneWidget);
    expect(find.text('私人 FM'), findsOneWidget);
    expect(find.text('黑胶电台 · 动态歌池'), findsOneWidget);

    await tester.tap(find.text('私人 FM'));
    await tester.pumpAndSettle();

    // 独立 FM 页撤掉后，入口的语义是「开一场会话」：歌池真的取过，
    // 用户落在播放页（FM 控件在那里），而不是某个 /fm 页面。
    expect(rig.search.calls, isNotEmpty);
    expect(find.text('PLAYER_STUB'), findsOneWidget);
  });

  testWidgets('daily recommendation stays reachable as a full-width row',
      (tester) async {
    await pump(tester);

    await tester.tap(find.textContaining('每日推荐'));
    await tester.pumpAndSettle();
    expect(find.text('DAILY_STUB'), findsOneWidget);
  });
}
