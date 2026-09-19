import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/features/explore/quick_entries.dart';

/// 不 pump [ExplorePage]：它的 initState 会发起真实网络请求，
/// dio 的超时 Timer 在 FakeAsync 里永远挂起（"A Timer is still pending"）。
/// [QuickEntries] 本身无状态、无网络，单独 pump 即可覆盖布局与导航。
void main() {
  Future<GoRouter> pump(WidgetTester tester) async {
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
          path: '/fm',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('FM_STUB'))),
        ),
        GoRoute(
          path: '/daily',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('DAILY_STUB'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    return router;
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

  testWidgets('FM hero opens /fm and keeps its vinyl decoration',
      (tester) async {
    await pump(tester);

    expect(find.byKey(const ValueKey('fm_vinyl')), findsOneWidget);
    expect(find.text('私人 FM'), findsOneWidget);
    expect(find.text('黑胶电台 · 动态歌池'), findsOneWidget);

    await tester.tap(find.text('私人 FM'));
    await tester.pumpAndSettle();
    expect(find.text('FM_STUB'), findsOneWidget);
  });

  testWidgets('daily recommendation stays reachable as a full-width row',
      (tester) async {
    await pump(tester);

    await tester.tap(find.textContaining('每日推荐'));
    await tester.pumpAndSettle();
    expect(find.text('DAILY_STUB'), findsOneWidget);
  });
}
