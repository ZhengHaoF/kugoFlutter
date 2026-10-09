import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/desktop_lyric/lyric_window/karaoke_sweep_line.dart';
import 'package:kugo/features/desktop_lyric/lyric_window/lyric_window_controller.dart';

/// 桌面歌词扫光的回归防线。
///
/// 背景：`KaraokeSweepLine` 的游标与扫光边界原先全是 State 里的私有方法，
/// 而这块在 2026-10 的一周里连吃五个 bugfix——
///   1150b9e 扫光锚点改帧计时 + 位置游标单调（修播放/暂停后歌词跳行）
///   88237e0 snapshot 位置改用实时游标（修暂停时显示的不是当前歌词）
///   fc2c142 / 301cf0b / 2e85c17 控制条避让与对齐
/// 一条测试都没有。这里把两块纯逻辑（帧计时游标、扫光边界）抽出来直接覆盖，
/// 与 `visibleLyricSignature` 同一套路。

const _kTextWidth = 100.0;

/// 四个等宽字：A[0,500) B[500,1000) C[1000,1500) D[1500,2000)。
/// 前缀宽表按 25/字线性铺开，末项 = 整行宽。
List<LyricChar> get _krcChars => const [
      LyricChar(text: 'A', startMs: 0, endMs: 500),
      LyricChar(text: 'B', startMs: 500, endMs: 1000),
      LyricChar(text: 'C', startMs: 1000, endMs: 1500),
      LyricChar(text: 'D', startMs: 1500, endMs: 2000),
    ];

List<double> get _krcPrefix => const [0, 25, 50, 75, 100];

LyricLine _krcLine() => LyricLine(
      timeMs: 0,
      endMs: 2000,
      text: 'ABCD',
      chars: _krcChars,
    );

void main() {
  group('sweepPositionMs — 帧计时游标', () {
    test('暂停时回传主窗快照游标，完全忽略锚点与帧计时', () {
      // 回归 88237e0：暂停瞬间 Ticker 停了，_elapsed 冻结。若仍按
      // 「锚点 + elapsed」算，扫光会停在暂停前最后一帧的位置，而主窗
      // 快照里的 positionMs 才是权威值（用户可能拖过进度条）。
      expect(
        sweepPositionMs(
          isPlaying: false,
          snapshotPositionMs: 7300,
          anchorPosMs: 1000,
          anchorElapsed: const Duration(milliseconds: 200),
          elapsed: const Duration(milliseconds: 99999),
        ),
        7300,
      );
    });

    test('刚锚定（elapsed == anchorElapsed）时游标就是锚点', () {
      expect(
        sweepPositionMs(
          isPlaying: true,
          snapshotPositionMs: 0,
          anchorPosMs: 4200,
          anchorElapsed: const Duration(milliseconds: 800),
          elapsed: const Duration(milliseconds: 800),
        ),
        4200,
      );
    });

    test('播放中 = 锚点 + 自锚点起的帧计时增量', () {
      expect(
        sweepPositionMs(
          isPlaying: true,
          snapshotPositionMs: 999999,
          anchorPosMs: 4200,
          anchorElapsed: const Duration(milliseconds: 800),
          elapsed: const Duration(milliseconds: 1800),
        ),
        5200,
      );
    });

    test('帧计时增量按毫秒取整，不受微秒抖动影响', () {
      expect(
        sweepPositionMs(
          isPlaying: true,
          snapshotPositionMs: 0,
          anchorPosMs: 0,
          anchorElapsed: Duration.zero,
          elapsed: const Duration(milliseconds: 1500, microseconds: 400),
        ),
        1500,
      );
    });

    test('掉帧（elapsed 大幅跳变）时游标跟着跳，不回退', () {
      // 帧计时天然单调：elapsed 只增不减，所以恢复播放后扫光不会冲到底，
      // 也不会因为暂停期间流逝的墙上时间而错位。
      final a = sweepPositionMs(
        isPlaying: true,
        snapshotPositionMs: 0,
        anchorPosMs: 0,
        anchorElapsed: Duration.zero,
        elapsed: const Duration(milliseconds: 16),
      );
      final b = sweepPositionMs(
        isPlaying: true,
        snapshotPositionMs: 0,
        anchorPosMs: 0,
        anchorElapsed: Duration.zero,
        elapsed: const Duration(milliseconds: 480),
      );
      expect(b, greaterThan(a));
    });
  });

  group('sweepBoundaryX — 退化输入', () {
    double x({
      LyricLine? line,
      int posMs = 0,
      double textWidth = _kTextWidth,
      List<double> prefixWidth = const [],
    }) =>
        sweepBoundaryX(
          line: line,
          posMs: posMs,
          textWidth: textWidth,
          prefixWidth: prefixWidth,
        );

    test('无当前行 / 空文本 / 非正宽度一律不扫', () {
      expect(x(line: null), 0);
      expect(x(line: const LyricLine(timeMs: 0, text: ''), posMs: 500), 0);
      expect(x(line: _krcLine(), posMs: 500, textWidth: 0), 0);
      expect(x(line: _krcLine(), posMs: 500, textWidth: -10), 0);
    });
  });

  group('sweepBoundaryX — LRC 整行线性扫', () {
    final line = LyricLine(timeMs: 1000, endMs: 3000, text: '整行歌词');

    test('行首之前不扫', () {
      expect(sweepBoundaryX(
        line: line,
        posMs: 999,
        textWidth: _kTextWidth,
        prefixWidth: const [],
      ), 0);
    });

    test('行中点扫到一半', () {
      expect(sweepBoundaryX(
        line: line,
        posMs: 2000,
        textWidth: _kTextWidth,
        prefixWidth: const [],
      ), closeTo(50, 1e-9));
    });

    test('行尾之后扫满', () {
      expect(sweepBoundaryX(
        line: line,
        posMs: 3001,
        textWidth: _kTextWidth,
        prefixWidth: const [],
      ), _kTextWidth);
    });

    test('LRC 缺 endMs 时按 3 秒默认行宽兜底', () {
      final noEnd = LyricLine(timeMs: 1000, text: '没给结束时间');
      // 1000 → 4000 的默认区间，中点 2500 应扫到一半。
      expect(sweepBoundaryX(
        line: noEnd,
        posMs: 2500,
        textWidth: _kTextWidth,
        prefixWidth: const [],
      ), closeTo(50, 1e-9));
      // 4000 之后扫满。
      expect(sweepBoundaryX(
        line: noEnd,
        posMs: 4000,
        textWidth: _kTextWidth,
        prefixWidth: const [],
      ), _kTextWidth);
    });
  });

  group('sweepBoundaryX — KRC 逐字插值', () {
    double at(int posMs, {List<double>? prefix}) => sweepBoundaryX(
          line: _krcLine(),
          posMs: posMs,
          textWidth: _kTextWidth,
          prefixWidth: prefix ?? _krcPrefix,
        );

    test('第一个字起点之前不扫', () {
      expect(at(-1), 0);
      expect(at(0), 0);
    });

    test('字内线性插值', () {
      // 第 0 字 [0,500) 的一半 → 前缀 0→25 的中点。
      expect(at(250), closeTo(12.5, 1e-9));
      // 第 2 字 [1000,1500) 的 1/4 → 50 + (75-50)*0.25。
      expect(at(1125), closeTo(56.25, 1e-9));
    });

    test('落在某个字起点时停在该字左缘', () {
      expect(at(500), closeTo(25, 1e-9));
      expect(at(1000), closeTo(50, 1e-9));
      expect(at(1500), closeTo(75, 1e-9));
    });

    test('字尾之前逼近下一字左缘', () {
      expect(at(999), closeTo(25 + 25 * 0.998, 1e-9));
    });

    test('末字唱完直接扫满（字间空隙分支的唯一边界）', () {
      // nextStart 取自 chars[idx+1] 时永远 > posMs，所以「字间空隙」分支
      // 只可能在末字生效：posMs >= cur.endMs → 落到整行宽。
      expect(at(2000), _kTextWidth);
      expect(at(99999), _kTextWidth);
    });

    test('二分定位：长行也能找到正确的字', () {
      final many = List.generate(
        40,
        (i) => LyricChar(
          text: 'x',
          startMs: i * 100,
          endMs: (i + 1) * 100,
        ),
      );
      final line = LyricLine(
        timeMs: 0,
        endMs: 4000,
        text: 'x' * 40,
        chars: many,
      );
      final prefix = List<double>.generate(41, (i) => i * 2.5);
      // 第 20 字 [2000,2100) 的一半 → 前缀 50→52.5 的中点 = 51.25。
      expect(
        sweepBoundaryX(
          line: line,
          posMs: 2050,
          textWidth: _kTextWidth,
          prefixWidth: prefix,
        ),
        closeTo(51.25, 1e-9),
      );
    });

    test('前缀表末项缺省时 w1 回退到整行宽', () {
      // 只有 w1（下一字右缘）有兜底；w0 是硬索引，调用方必须保证
      // prefixWidth.length >= 当前字下标 + 1（布局侧由 _rebuildPrefixTable 保证）。
      expect(at(1600, prefix: const [0, 25, 50, 75]), closeTo(80, 1e-9));
    });

    test('零时长字不退化成 NaN，直接推进到右缘', () {
      final zero = LyricLine(
        timeMs: 0,
        endMs: 100,
        text: 'AB',
        chars: const [
          LyricChar(text: 'A', startMs: 0, endMs: 0),
          LyricChar(text: 'B', startMs: 0, endMs: 100),
        ],
      );
      final v = sweepBoundaryX(
        line: zero,
        posMs: 0,
        textWidth: _kTextWidth,
        prefixWidth: const [0, 0, 100],
      );
      expect(v.isNaN, isFalse);
      expect(v, closeTo(0, 1e-9));
    });
  });

  group('KaraokeSweepLine — 挂载与无界约束', () {
    testWidgets('无歌词时渲染标题占位，不抛', (tester) async {
      // DesktopLyricController 不接 IPC 时就是一个干净的 ChangeNotifier。
      final controller = DesktopLyricController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 40,
              child: KaraokeSweepLine(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(KaraokeSweepLine), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KaraokeSweepLine),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('无界宽度约束回落默认窗宽，不炸 layout', (tester) async {
      // 回归：无界约束时若直接把 constraints.maxWidth 传给 TextPainter，
      // 会拿到 double.infinity → Size(infinity) / originDx 算飞。
      final controller = DesktopLyricController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Row(
              children: [
                KaraokeSweepLine(controller: controller),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(KaraokeSweepLine));
      expect(size.width.isFinite, isTrue);
      expect(size.width, greaterThan(0));
    });
  });
}
