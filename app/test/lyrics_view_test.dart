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
  bool isPlaying = false,
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
          isPlaying: isPlaying,
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

  testWidgets('active line ticker survives play/pause/play without build errors',
      (tester) async {
    // 回归：SingleTickerProviderStateMixin 下 dispose 后再 createTicker 会断言失败，
    // 使活动行 build 抛错 —— 歌词区随之无法重建/滚动（表现为「滚动不了」）。
    Future<void> pump(bool playing) async {
      await tester.pumpWidget(
        _harness(
          translation: false,
          romanization: false,
          positionMs: 1200,
          isPlaying: playing,
        ),
      );
      await tester.pump();
    }

    await pump(true); // 首次 createTicker
    await pump(false); // 暂停
    await pump(true); // 再次播放：旧实现会第二次 createTicker → 断言
    await pump(false); // 收尾：停掉 ticker，避免测试结束时仍有活跃 ticker

    expect(tester.takeException(), isNull);
  });

  testWidgets('sweep does not count the pause gap when resuming',
      (tester) async {
    // 回归：锚点必须基于 Ticker 帧计时。用墙上时钟时，暂停期间流逝的时间会被
    // 算进扫光，恢复播放瞬间扫光直接冲到整行（表现为「逐字滚动失效/跳到某句」）。
    int sungChars() {
      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.textSpan != null);
      final children = (rich.textSpan! as TextSpan).children!;
      return (children.first as TextSpan).text?.length ??
          rich.textSpan!.toPlainText().length;
    }

    Future<void> pump({required bool playing}) async {
      await tester.pumpWidget(
        _harness(
          translation: false,
          romanization: false,
          positionMs: 1000, // 夜(0) 空(500) 中(1000) → 已唱 3 字
          isPlaying: playing,
        ),
      );
    }

    await pump(playing: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(sungChars(), 3);

    // 暂停 30 秒：扫光停在离散位置不动。
    await pump(playing: false);
    await tester.pump(const Duration(seconds: 30));
    expect(sungChars(), 3);

    // 恢复播放，位置仍是 1000（引擎尚未发新样本）：不得把暂停的 30s 算进去。
    await pump(playing: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(sungChars(), lessThanOrEqualTo(4));

    // 收尾：停 ticker，避免测试结束时仍有活跃 ticker。
    await pump(playing: false);
    await tester.pump();
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
        spacingScale: kLyricSpacingScaleMax,
      ),
    );
    expect(_rowExtent(tester), closeTo(56 * kLyricSpacingScaleMax, 0.001));
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
    // 倍率算出的 (56 + 18) × 0.4 = 29.6 会被文字高度 18×1.35 + 12×1.25 = 39.3 顶住。
    expect(_rowExtent(tester), closeTo(39.3, 0.001));
  });
}
