import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/theme/overtone_theme.dart';
import 'package:overtone/shared/widgets/common.dart';

void main() {
  testWidgets('showOvertoneBottomSheet renders bottom sheet on small/mobile screen',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOvertoneTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showOvertoneBottomSheet<void>(
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

    expect(find.byType(OvertoneSheetChrome), findsOneWidget);
    expect(find.text('Mobile Content'), findsOneWidget);
  });

  testWidgets(
      'showOvertoneBottomSheet renders OvertoneDesktopSideSheetChrome on desktop screen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildOvertoneTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showOvertoneBottomSheet<void>(
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
    // it should render OvertoneDesktopSideSheetChrome aligned to right
    expect(find.byType(OvertoneDesktopSideSheetChrome), findsOneWidget);
    expect(find.text('Desktop Content'), findsOneWidget);

    // Test close button
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(OvertoneDesktopSideSheetChrome), findsNothing);
  });
}
