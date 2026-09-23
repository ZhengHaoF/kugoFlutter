import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/lyrics_view.dart';

List<LyricLine> _sample() => const [
      LyricLine(
        timeMs: 0,
        endMs: 4000,
        text: '夜空中最亮的星',
        chars: [
          LyricChar(text: '夜', startMs: 0, endMs: 500),
          LyricChar(text: '空', startMs: 500, endMs: 1000),
          LyricChar(text: '中', startMs: 1000, endMs: 1500),
          LyricChar(text: '最', startMs: 1500, endMs: 2000),
          LyricChar(text: '亮', startMs: 2000, endMs: 2500),
          LyricChar(text: '的', startMs: 2500, endMs: 3000),
          LyricChar(text: '星', startMs: 3000, endMs: 3500),
        ],
        translated: 'The brightest star in the night sky',
        romanized: 'ye kong zhong zui liang de xing',
      ),
    ];

Widget _harness({
  required bool translation,
  required bool romanization,
  required int positionMs,
}) {
  return ProviderScope(
    overrides: [
      settingsControllerProvider.overrideWith(
        () => _FixedSettings(
          AppSettings(
            lyricTranslation: translation,
            lyricRomanization: romanization,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LyricsView(lines: _sample(), positionMs: positionMs),
      ),
    ),
  );
}

class _FixedSettings extends SettingsController {
  _FixedSettings(this._initial);
  final AppSettings _initial;

  @override
  AppSettings build() => _initial;
}

void main() {
  testWidgets('shows translation and romanization when both enabled',
      (tester) async {
    await tester.pumpWidget(
      _harness(translation: true, romanization: true, positionMs: 0),
    );
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('The brightest star in the night sky'), findsOneWidget);
    expect(find.text('ye kong zhong zui liang de xing'), findsOneWidget);
  });

  testWidgets('hides secondary lines when toggles are off', (tester) async {
    await tester.pumpWidget(
      _harness(translation: false, romanization: false, positionMs: 0),
    );
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('The brightest star in the night sky'), findsNothing);
    expect(find.text('ye kong zhong zui liang de xing'), findsNothing);
  });

  testWidgets('shows only translation when romanization is off',
      (tester) async {
    await tester.pumpWidget(
      _harness(translation: true, romanization: false, positionMs: 0),
    );
    expect(find.text('The brightest star in the night sky'), findsOneWidget);
    expect(find.text('ye kong zhong zui liang de xing'), findsNothing);
  });

  testWidgets('karaoke paints sung prefix via Text.rich', (tester) async {
    await tester.pumpWidget(
      _harness(translation: false, romanization: false, positionMs: 1200),
    );
    // Active line with char timing uses Text.rich, not plain Text.
    final rich = tester.widget<Text>(find.byType(Text).first);
    // The primary line is the first Text in the column; it should be rich.
    // Find specifically the karaoke Text.
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final karaoke = texts.where((t) => t.textSpan != null).toList();
    expect(karaoke, isNotEmpty);
    expect(rich.textSpan ?? karaoke.first.textSpan, isNotNull);
    final span = karaoke.first.textSpan!;
    final sung = span.toPlainText().substring(0, 2); // 夜空 by 1200ms
    expect(span.toPlainText(), '夜空中最亮的星');
    expect(span.toPlainText().startsWith(sung), isTrue);
  });
}
