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

/// 无逐字时间轴的普通歌词：便于直接断言 Text.style（卡拉 OK 行的样式在 span 上）。
List<LyricLine> _plainLines() => const [
      LyricLine(timeMs: 0, endMs: 1000, text: '第一行'),
      LyricLine(timeMs: 1000, endMs: 2000, text: '第二行'),
    ];

Widget _harness({
  required bool translation,
  required bool romanization,
  required int positionMs,
  List<LyricLine>? lines,
  double fontScale = 1,
  double spacingScale = 1,
}) {
  return ProviderScope(
    overrides: [
      settingsControllerProvider.overrideWith(
        () => _FixedSettings(
          AppSettings(
            lyricTranslation: translation,
            lyricRomanization: romanization,
            lyricFontScale: fontScale,
            lyricSpacingScale: spacingScale,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LyricsView(
          lines: lines ?? _sample(),
          positionMs: positionMs,
        ),
      ),
    ),
  );
}

/// 列表行盒高度 = 歌词行间距（副行开关关闭时为基准 56 × 两个倍率）。
double _rowExtent(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).itemExtent!;

/// 窄屏（宽 < 800 即 `isDesktopView` 为假），主行字号基准为 18/15 而非 22/16。
/// 测试默认画布 800×600 会被判成桌面，故字号断言前先切到手机尺寸。
void _usePhoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

  testWidgets('default scales keep the base font size and row extent',
      (tester) async {
    _usePhoneView(tester);
    await tester.pumpWidget(
      _harness(
        translation: false,
        romanization: false,
        positionMs: 0,
        lines: _plainLines(),
      ),
    );
    expect(
      tester.widget<Text>(find.text('第一行')).style?.fontSize,
      closeTo(18, 0.001),
    );
    expect(_rowExtent(tester), closeTo(56, 0.001));
  });

  testWidgets('font scale enlarges lyric font size', (tester) async {
    _usePhoneView(tester);
    await tester.pumpWidget(
      _harness(
        translation: false,
        romanization: false,
        positionMs: 0,
        lines: _plainLines(),
        fontScale: 1.5,
      ),
    );
    // 活动行 18 → 27；非活动行 15 → 22.5。
    expect(
      tester.widget<Text>(find.text('第一行')).style?.fontSize,
      closeTo(27, 0.001),
    );
    expect(
      tester.widget<Text>(find.text('第二行')).style?.fontSize,
      closeTo(22.5, 0.001),
    );
  });

  testWidgets('font scale grows the row extent so text is not clipped',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        translation: false,
        romanization: false,
        positionMs: 0,
        lines: _plainLines(),
        fontScale: 1.5,
      ),
    );
    expect(_rowExtent(tester), closeTo(84, 0.001));
  });

  testWidgets('line spacing scale grows the row extent', (tester) async {
    await tester.pumpWidget(
      _harness(
        translation: false,
        romanization: false,
        positionMs: 0,
        lines: _plainLines(),
        spacingScale: 2,
      ),
    );
    expect(_rowExtent(tester), closeTo(112, 0.001));
  });

  testWidgets('row extent never shrinks below the text height', (tester) async {
    _usePhoneView(tester);
    await tester.pumpWidget(
      _harness(
        translation: true,
        romanization: false,
        positionMs: 0,
        lines: _plainLines(),
        spacingScale: kLyricSpacingScaleMin,
      ),
    );
    // 倍率算出的 (56 + 18) × 0.5 = 37 会被文字高度 18×1.35 + 12×1.25 = 39.3 顶住。
    expect(_rowExtent(tester), closeTo(39.3, 0.001));
  });
}
