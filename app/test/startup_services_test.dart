import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/diagnostics/startup_services.dart';

void main() {
  testWidgets(
    'optional failure keeps the app usable and starts later services',
    (tester) async {
      var later = false;
      var errors = 0;
      await tester.pumpWidget(
        StartupServices(
          services: {
            'media': () async => throw StateError('fixture'),
            'tray': () async => later = true,
          },
          onError: (_, _) => errors++,
          child: const MaterialApp(home: Text('usable app')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('usable app'), findsOneWidget);
      expect(find.textContaining('已降级运行'), findsOneWidget);
      expect(later, true);
      expect(errors, 1);
    await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.textContaining('已降级运行'), findsNothing);
    },
  );

  testWidgets('timeout does not cancel or restart the native operation', (
    tester,
  ) async {
    final stalled = Completer<void>();
    var starts = 0;
    var later = false;
    await tester.pumpWidget(
      StartupServices(
        timeout: const Duration(seconds: 1),
        services: {
          'media': () {
            starts++;
            return stalled.future;
          },
          'tray': () async => later = true,
        },
        onError: (_, _) {},
        child: const MaterialApp(home: Text('usable app')),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('usable app'), findsOneWidget);
    expect(later, true);
    expect(starts, 1);
    stalled.complete();
    await tester.pumpAndSettle();
    expect(starts, 1);
  });
}
