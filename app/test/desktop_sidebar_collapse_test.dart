import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/theme/kugo_theme.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/shell/desktop_sidebar.dart';

import 'fakes/fake_audio_player.dart';

/// 折叠侧栏曾把 SizedBox(width: infinity) 塞进 Row，布局直接崩。
/// 这里钉死：展开/折叠都必须能完整 layout，且折叠后只剩图标。
void main() {
  Widget host({required String location}) {
    final engine = FakeAudioPlayer();
    return ProviderScope(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
      child: MaterialApp(
        theme: buildKugoTheme(Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              DesktopSidebar(
                location: location,
                onNavigate: (_) {},
              ),
              const Expanded(
                child: SizedBox.expand(child: ColoredBox(color: Colors.black)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('展开态：侧栏 220，导航项带文案', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(location: '/explore'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final sidebar = find.byType(DesktopSidebar);
    expect(tester.getSize(sidebar).width, 220);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('系统设置'), findsOneWidget);
  });

  testWidgets('折叠态：侧栏 64，无文案、无布局异常', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(location: '/explore'));
    await tester.pumpAndSettle();

    // 点折叠钮（展开态文案是「折叠侧栏」）。
    await tester.tap(find.byTooltip('折叠侧栏'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final sidebar = find.byType(DesktopSidebar);
    expect(tester.getSize(sidebar).width, 64);
    // 文案不出现；折叠后用 Tooltip 标注图标。
    expect(find.text('发现'), findsNothing);
    expect(find.text('概念版 · Windows'), findsNothing);
    expect(find.byTooltip('发现'), findsOneWidget);

    // 再展开回来。
    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(sidebar).width, 220);
    expect(find.text('发现'), findsOneWidget);
  });
}

