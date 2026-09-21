import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/theme/kugo_theme.dart';
import 'package:kugo/shared/widgets/common.dart';

void main() {
  testWidgets('showKugoBottomSheet renders bottom sheet on small/mobile screen',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKugoTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showKugoBottomSheet<void>(
                  context: context,
                  builder: (ctx) => const Text('Mobile Content'),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.byType(KugoSheetChrome), findsOneWidget);
    expect(find.text('Mobile Content'), findsOneWidget);
  });

  testWidgets(
      'showKugoBottomSheet renders KugoDesktopSideSheetChrome on desktop screen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKugoTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showKugoBottomSheet<void>(
                  context: context,
                  builder: (ctx) => const Text('Desktop Content'),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // On Windows test environment (desktop platform + width >= 800),
    // it should render KugoDesktopSideSheetChrome aligned to right
    expect(find.byType(KugoDesktopSideSheetChrome), findsOneWidget);
    expect(find.text('Desktop Content'), findsOneWidget);

    // Test close button
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(KugoDesktopSideSheetChrome), findsNothing);
  });
}
