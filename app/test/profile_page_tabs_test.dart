import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/profile/profile_page.dart';

import 'fakes/fake_audio_player.dart';

/// 「我的」页页头对齐「探索发现」：顶部居中标题 + 页签栏（歌单 / 设置），
/// 身份卡常驻（切页签也不丢账号与乐库统计）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: FakeAudioPlayer()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('页头：居中标题「我的」+ 页签栏，默认落在「歌单」', (tester) async {
    await pumpProfile(tester);

    // 标题在 AppBar 里居中（AppBarTheme.centerTitle），与「探索发现」一致。
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('我的')),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsOneWidget);

    // 默认页签「歌单」：歌单卡片可见，设置项还没渲染。
    expect(find.text('我的歌单'), findsOneWidget);
    expect(find.text('关于'), findsNothing);
  });

  testWidgets('切到「设置」页签：出快捷设置，歌单卡片收起', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('更多设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('我的歌单'), findsNothing);
  });

  testWidgets('身份卡常驻：切到「设置」页签后账号与统计仍在', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('我喜欢'), findsOneWidget);
    expect(find.text('最近播放'), findsOneWidget);
    // 统计标签「歌单」+ 页签「歌单」各一处。
    expect(find.text('歌单'), findsNWidgets(2));
  });
}