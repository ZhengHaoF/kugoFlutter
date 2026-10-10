import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/diagnostics/startup_gate.dart';

void main() {
  testWidgets('shell appears immediately before initialization completes', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(
      StartupGate(initialize: () => ready.future, onError: (_, _) {}),
    );
    expect(find.text('正在启动 kugo…'), findsOneWidget);
    ready.complete(const MaterialApp(home: Text('ready')));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('timeout stays visible without starting overlapping services', (
    tester,
  ) async {
    var calls = 0;
    final ready = Completer<Widget>();
    await tester.pumpWidget(
      StartupGate(
        timeout: const Duration(seconds: 1),
        initialize: () {
          calls++;
          return ready.future;
        },
        onError: (_, _) {},
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('启动服务响应超时'), findsOneWidget);
    expect(calls, 1);
    expect(find.text('重试'), findsNothing);
    ready.complete(const MaterialApp(home: Text('late ready')));
    await tester.pumpAndSettle();
    expect(find.text('late ready'), findsOneWidget);
  });

  testWidgets('settled failure is logged and can be retried', (tester) async {
    var calls = 0;
    var errors = 0;
    await tester.pumpWidget(
      StartupGate(
        initialize: () async {
          if (++calls == 1) throw StateError('fixture');
          return const MaterialApp(home: Text('retry ready'));
        },
        onError: (_, _) => errors++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('启动失败'), findsOneWidget);
    expect(errors, 1);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('retry ready'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('completion after disposal does not update a dead shell', (
    tester,
  ) async {
    final ready = Completer<Widget>();
    await tester.pumpWidget(
      StartupGate(initialize: () => ready.future, onError: (_, _) {}),
    );
    await tester.pumpWidget(const SizedBox());
    ready.complete(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
