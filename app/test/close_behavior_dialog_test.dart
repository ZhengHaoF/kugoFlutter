import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/theme/kugo_theme.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/tray/close_behavior_dialog.dart';

class _Harness {
  CloseBehaviorChoice? result;
}

Future<void> _openDialog(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildKugoTheme(Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              harness.result = await showCloseBehaviorDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('选择「退出应用」并勾选记住', (tester) async {
    final harness = _Harness();
    await _openDialog(tester, harness);

    expect(find.text('关闭 kugo'), findsOneWidget);
    expect(find.text('最小化到托盘'), findsOneWidget);
    expect(find.text('退出应用'), findsOneWidget);
    expect(find.text('记住我的选择'), findsOneWidget);

    await tester.tap(find.text('记住我的选择'));
    await tester.pump();
    await tester.tap(find.text('退出应用'));
    await tester.pumpAndSettle();

    expect(harness.result?.behavior, CloseBehavior.quit);
    expect(harness.result?.remember, isTrue);
    expect(find.text('关闭 kugo'), findsNothing);
  });

  testWidgets('不勾记住时 remember 为 false', (tester) async {
    final harness = _Harness();
    await _openDialog(tester, harness);

    await tester.tap(find.text('最小化到托盘'));
    await tester.pumpAndSettle();

    expect(harness.result?.behavior, CloseBehavior.tray);
    expect(harness.result?.remember, isFalse);
  });

  testWidgets('取消返回 null', (tester) async {
    final harness = _Harness();
    await _openDialog(tester, harness);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(harness.result, isNull);
    expect(find.text('关闭 kugo'), findsNothing);
  });
}