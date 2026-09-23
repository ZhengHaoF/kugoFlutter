import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/lyric_display_sheet.dart';

class _FixedSettings extends SettingsController {
  _FixedSettings(this._initial);
  final AppSettings _initial;

  @override
  AppSettings build() => _initial;
}

void main() {
  testWidgets('lyric display sheet toggles translation and romanization',
      (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _FixedSettings(
              const AppSettings(
                lyricTranslation: true,
                lyricRomanization: false,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    captured = ref;
                    return TextButton(
                      onPressed: () => showLyricDisplaySheet(context, ref),
                      child: const Text('open'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('歌词显示'), findsOneWidget);
    expect(find.text('显示翻译'), findsOneWidget);
    expect(find.text('显示罗马音'), findsOneWidget);

    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches.length, 2);
    expect(switches.first.value, isTrue);
    expect(switches.last.value, isFalse);

    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();

    final after = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(after.last.value, isTrue);

    // Button highlights when any secondary toggle is on.
    final settings = captured.read(settingsControllerProvider);
    expect(settings.lyricTranslation, isTrue);
    expect(settings.lyricRomanization, isTrue);
  });

  testWidgets('LyricDisplayButton opens the sheet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _FixedSettings(const AppSettings()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LyricDisplayButton()),
        ),
      ),
    );

    await tester.tap(find.byType(LyricDisplayButton));
    await tester.pumpAndSettle();
    expect(find.text('歌词显示'), findsOneWidget);
  });
}
