import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/search/search_history_controller.dart';
import 'package:kugo/features/search/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 搜索历史的 UI 接线：提交入历史、返回搜索页展示、单条删除。
void main() {
  testWidgets('提交即记录，返回搜索页展示历史，可单条删除', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bootstrapFakeMusicSources();

    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
        GoRoute(
          path: '/other',
          builder: (_, _) => const Scaffold(body: Text('other')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 未搜索时只有热搜，没有历史区块。
    expect(find.text('搜索历史'), findsNothing);

    // 点热门词提交一次搜索 → 记入历史。
    await tester.tap(find.text('周杰伦'));
    await tester.pumpAndSettle();
    expect(container.read(searchHistoryProvider), ['周杰伦']);

    // 离开再回来：结果被清掉，历史区块带着刚才的关键词出现。
    router.go('/other');
    await tester.pumpAndSettle();
    router.go('/search');
    await tester.pumpAndSettle();
    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('周杰伦'), findsNWidgets(2)); // 历史 chip + 热搜 chip

    // 单条删除：历史变空，区块收起。
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(container.read(searchHistoryProvider), isEmpty);
    expect(find.text('搜索历史'), findsNothing);
  });
}