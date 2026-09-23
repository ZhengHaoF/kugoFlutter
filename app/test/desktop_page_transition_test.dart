import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/theme/kugo_theme.dart';

void main() {
  ThemeData desktopTheme() =>
      buildKugoTheme(Brightness.dark).copyWith(platform: TargetPlatform.windows);

  Future<void> pumpDesktopApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        home: const _HostPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('windows theme uses DesktopPageTransitionsBuilder', (tester) async {
    await pumpDesktopApp(tester);
    final theme = Theme.of(tester.element(find.byKey(const ValueKey('home'))));
    expect(theme.platform, TargetPlatform.windows);
    final builder = theme.pageTransitionsTheme.builders[TargetPlatform.windows];
    expect(builder, isA<DesktopPageTransitionsBuilder>());
  });

  testWidgets('settled route paints without opacity or translate layer',
      (tester) async {
    await pumpDesktopApp(tester);

    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home')),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('push fades through and drifts horizontally without scaling',
      (tester) async {
    await pumpDesktopApp(tester);

    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail')), findsOneWidget);

    // Entering route is mid-fade (delayed fade-through).
    final enterOpacity = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.byKey(const ValueKey('detail')),
            matching: find.byType(Opacity),
          ),
        )
        .map((w) => w.opacity)
        .fold<double>(1.0, (a, b) => a * b);
    expect(enterOpacity, lessThan(1.0));
    expect(enterOpacity, greaterThan(0.0));

    // Horizontal drift only — any Transform under the route must be pure translate.
    for (final label in const ['home', 'detail']) {
      final transforms = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.byKey(ValueKey(label)),
              matching: find.byType(Transform),
            ),
          )
          .toList();
      expect(transforms, isNotEmpty, reason: '$label should drift mid-flight');
      for (final t in transforms) {
        final m = t.transform.storage;
        expect(m[0], 1.0, reason: 'no scale X on $label');
        expect(m[5], 1.0, reason: 'no scale Y on $label');
        expect(m[1], 0.0);
        expect(m[4], 0.0);
      }
      final dx = transforms
          .map((t) => t.transform.getTranslation().x)
          .fold<double>(0.0, (a, b) => a + b);
      expect(dx.abs(), greaterThan(0.0), reason: '$label should translate');
    }

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail')), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('home')),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}

class _HostPage extends StatelessWidget {
  const _HostPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(key: ValueKey('home'), width: 40, height: 40),
            TextButton(
              key: const ValueKey('open'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _DetailPage(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(key: ValueKey('detail'), width: 40, height: 40),
            TextButton(
              key: const ValueKey('back'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}
