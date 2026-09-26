// go_router 行为备忘 / 回归测试。
//
// 背景：线上曾报
//   'package:flutter/src/widgets/navigator.dart': Failed assertion:
//   '!keyReservation.contains(key)': is not true.
// 出处在 NavigatorState._debugCheckDuplicatedPageKeys —— 同一个 Navigator 的
// `pages` 里出现两个相等的非 null page key。触发形状是：从**顶级路由** push 一个
// 定义在 StatefulShellBranch 里的 route。
//
// 真实修复：把 `/song` 从 branch0 移到**顶级 routes**（见 lib/app.dart 的注释，
// 那里写了为什么不能用 `parentNavigatorKey` 绕）。该修复已由真机验证
// （MuMu 点播放页 ⓘ 能正常进歌曲详情页）。
//
// **为什么这里没有「复现用例」**：上面的形状在 widget test 里被 framework 自身的
// 断言盖住（`_dependents.isEmpty` / `Tried to build dirty widget in the wrong
// build scope`，都出现在 push 后的重建/拆卸阶段），两轮实测都没能稳定拿到
// `keyReservation`。与其留一条靠不住的复现用例（还会让 `flutter test` 变红），
// 不如只守住**能稳定观测**的那几条：
//   ✓ branch 内子路由的 `parentNavigatorKey` 只能为 null 或该 branch 自己的
//     navigatorKey（go_router `route.dart:481`，**构造期**即断言 —— 试过用根
//     navigator key 绕，直接崩在路由表构造，实测过）；
//   ✓ 顶级→顶级 push、同 shell 内 push、跨 branch push 都不触发该断言。
//
// 每个步骤单独 takeException，失败信息会指出崩在哪一步。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// [songOnRoot] = true 时 `/song` 定义在**顶级**（修复后的形状）。
GoRouter _build({required bool songOnRoot}) {
  final songRoute = GoRoute(
    path: '/song',
    pageBuilder: (c, s) => MaterialPage(child: Text('song ${s.uri.query}')),
  );
  return GoRouter(
    // 每个 router 必须有自己的 rootKey：模块级共享会让多个用例复用同一个
    // GlobalKey，pumpWidget 直接报「A GlobalKey was used multiple times」。
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    initialLocation: '/explore',
    routes: [
      GoRoute(
        path: '/player',
        pageBuilder: (c, s) => MaterialPage(child: const Text('player')),
      ),
      if (songOnRoot) songRoute,
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (c, s) => const Text('explore'),
              ),
              if (!songOnRoot) songRoute,
              GoRoute(
                path: '/playlist/:id',
                pageBuilder: (c, s) => MaterialPage(
                  child: Text('playlist ${s.pathParameters['id']}'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (c, s) => const Text('profile'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

/// 取走当前异常并断言为空 —— 失败信息带上 [step]，直接指出崩在哪一步。
void _expectClean(WidgetTester tester, String step) {
  final error = tester.takeException();
  expect(error, isNull, reason: '【$step】这一步出错：$error');
}

Future<void> _go(WidgetTester tester, GoRouter router, String location) async {
  router.push(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A. 顶级 → 顶级 push（/player → /song，修复后的形状）', (tester) async {
    final router = _build(songOnRoot: true);
    await _pump(tester, router);
    _expectClean(tester, 'A-初始 /explore');

    await _go(tester, router, '/player');
    _expectClean(tester, 'A-push /player');

    await _go(tester, router, '/song?id=1');
    _expectClean(tester, 'A-push /song');
    expect(find.textContaining('song'), findsOneWidget);
  });

  testWidgets('B. 对照：/song 留在 branch，从同 shell 内 push', (tester) async {
    final router = _build(songOnRoot: false);
    await _pump(tester, router);

    await _go(tester, router, '/song?id=1');
    _expectClean(tester, 'B-同 shell 内 push /song');
  });

  testWidgets('C. 跨 branch push（/profile → /playlist/:id）', (tester) async {
    // 复刻项目里的真实调用：likes_page（branch1）push `/artist/:id`、`/album/:id`、
    // `/playlist/:id`，而这三条都定义在 branch0 —— 实测这样是安全的，无需改动。
    final router = _build(songOnRoot: true);
    await _pump(tester, router);

    await _go(tester, router, '/profile');
    _expectClean(tester, 'C-push /profile');
    await _go(tester, router, '/playlist/9');
    _expectClean(tester, 'C-跨 branch push /playlist/:id');
  });
}
