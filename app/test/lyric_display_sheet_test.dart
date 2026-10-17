import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/features/settings/settings_controller.dart';
import 'package:overtone/shared/widgets/lyric_display_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // 字号 / 行间距滑块（默认 100%）。
    expect(find.text('歌词字号'), findsOneWidget);
    expect(find.text('歌词行间距'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('100%'), findsNWidgets(2));
    // 已是默认 → 「恢复默认」置灰。
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '恢复默认'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();

    final after = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(after.last.value, isTrue);

    // Button highlights when any secondary toggle is on.
    final settings = captured.read(settingsControllerProvider);
    expect(settings.lyricTranslation, isTrue);
    expect(settings.lyricRomanization, isTrue);
  });

  testWidgets('reset button restores default font and spacing scale',
      (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsControllerProvider.overrideWith(
            () => _FixedSettings(
              const AppSettings(lyricFontScale: 1.4, lyricSpacingScale: 1.3),
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
    expect(find.text('140%'), findsOneWidget);
    expect(find.text('130%'), findsOneWidget);

    final reset = find.widgetWithText(TextButton, '恢复默认');
    expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

    await tester.tap(reset);
    await tester.pumpAndSettle();

    final settings = captured.read(settingsControllerProvider);
    expect(settings.lyricFontScale, 1);
    expect(settings.lyricSpacingScale, 1);
    expect(find.text('100%'), findsNWidgets(2));
    // 已回到默认 → 按钮置灰。
    expect(tester.widget<TextButton>(reset).onPressed, isNull);
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

  testWidgets('offset sheet微调当前曲并从全局值叠加', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    captured = ref;
                    return TextButton(
                      onPressed: () => showLyricOffsetSheet(
                        context,
                        ref,
                        trackKey: 'kugou:a',
                      ),
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
    expect(find.text('歌词偏移（当前歌曲）'), findsOneWidget);
    // 未微调过 → 「重置本曲微调」置灰。
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '重置本曲微调'))
          .onPressed,
      isNull,
    );

    // 全局先偏 0.5s，再给本曲补 0.5s → 合计 1.0s。
    await captured
        .read(settingsControllerProvider.notifier)
        .setLyricOffsetMs(500);
    await tester.tap(find.text('+0.5s'));
    await tester.pumpAndSettle();

    final settings = captured.read(settingsControllerProvider);
    expect(settings.lyricOffsetOverrides['kugou:a'], 500);
    expect(settings.lyricOffsetFor('kugou:a'), 1000);
    expect(find.textContaining('合计生效 +1.0s'), findsOneWidget);

    await tester.tap(find.text('重置本曲微调'));
    await tester.pumpAndSettle();
    expect(
      captured.read(settingsControllerProvider).lyricOffsetOverrides,
      isEmpty,
    );
    expect(find.textContaining('本曲微调 0.0s'), findsOneWidget);
  });
}
