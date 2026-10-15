/// 播放页倍速 chip 与倍速弹层。
///
/// 钉住交互口径：静息 1.0x 只显示图标、无角标；非 1.0 高亮 + 当前值角标；
/// 弹层选档即生效并写引擎 / 落盘（`player_speed_test.dart` 覆盖状态与
/// 持久化，这里只覆盖 UI 接线）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/settings/settings_controller.dart';
import 'package:overtone/shared/widgets/speed_sheet.dart';

import 'fakes/fake_audio_player.dart';

void main() {
  Future<(ProviderContainer, FakeAudioPlayer)> pumpChip(
    WidgetTester tester,
  ) async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SpeedChip())),
      ),
    );
    await tester.pump();
    return (container, engine);
  }

  testWidgets('rest state shows icon only; tap opens the sheet', (
    tester,
  ) async {
    await pumpChip(tester);

    // 1.0x 静息：无角标文案。
    expect(find.text('1x'), findsNothing);
    expect(find.text('正常'), findsNothing);

    await tester.tap(find.byType(SpeedChip));
    await tester.pumpAndSettle();

    expect(find.text('播放倍速'), findsOneWidget);
    // 档位表与 MV 一致：0.5–2.0 六档。
    for (final label in const ['0.5x', '0.75x', '正常', '1.25x', '1.5x', '2x']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('picking a preset applies speed and the chip shows it', (
    tester,
  ) async {
    final (container, engine) = await pumpChip(tester);

    await tester.tap(find.byType(SpeedChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();

    // 弹层关闭、状态与引擎生效、角标出现。
    expect(find.text('播放倍速'), findsNothing);
    expect(container.read(playerControllerProvider).speed, 1.5);
    expect(engine.lastSpeed, 1.5);
    expect(find.text('1.5x'), findsOneWidget);
    expect(container.read(settingsControllerProvider).speed, 1.5);
  });

  testWidgets('chip reflects a non-default speed from player state', (
    tester,
  ) async {
    final (container, _) = await pumpChip(tester);

    container.read(playerControllerProvider.notifier).setSpeed(0.75);
    await tester.pump();

    expect(find.text('0.75x'), findsOneWidget);

    // 再开弹层：当前档高亮（check 图标只有一个，落在 0.75x 行）。
    await tester.tap(find.byType(SpeedChip));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
