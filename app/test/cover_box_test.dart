import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/widgets/cover_box.dart';

void main() {
  // 回归：交叉淡入重构后，AnimatedSwitcher 默认 layoutBuilder 的 Stack 是
  // 松约束且收缩到最大子级——淡入一结束占位层被移走，没给显式宽高的图片
  // 就缩回固有尺寸，出现「封面没占满位置」。fill 模式必须用 StackFit.expand。
  testWidgets('CoverBox(size: 0) fills its parent box', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: CoverBox(seed: 'mock://a', size: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byType(CoverBox),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect(box.size, const Size(200, 120));
  });

  testWidgets('CoverBox(size: 56) keeps its fixed size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: CoverBox(seed: 'mock://a', size: 56)),
        ),
      ),
    );
    await tester.pump();

    final box = tester.renderObject<RenderBox>(
      find.descendant(
        of: find.byType(CoverBox),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect(box.size, const Size(56, 56));
  });

  // 回归：封面原图常 1000–2000px，列表里只显示几十像素。不限制解码尺寸时
  // 每张图都按原尺寸解码 + 上传纹理，滚动/切歌时是主要掉帧来源。
  test('coverDecodeWidth scales by device pixel ratio', () {
    expect(coverDecodeWidth(56, 2), 112);
    expect(coverDecodeWidth(200, 3), 600);
    // 3x 密集屏下播放页封面（~420 逻辑像素）仍远小于常见 2000px 原图。
    expect(coverDecodeWidth(420, 3), 1260);
  });

  test('coverDecodeWidth degrades safely on unknown geometry', () {
    // 约束无界 / 尚未布局 → 不限制解码（交回原尺寸）。
    expect(coverDecodeWidth(double.infinity, 2), isNull);
    expect(coverDecodeWidth(0, 2), isNull);
    expect(coverDecodeWidth(-10, 2), isNull);
    expect(coverDecodeWidth(double.nan, 2), isNull);
    // 非法的 dpr 退回 1.0，而不是算出 0 或 NaN。
    expect(coverDecodeWidth(56, 0), 56);
    expect(coverDecodeWidth(56, double.nan), 56);
    // 极小尺寸至少解出 1px，避免 codec 收到 0。
    expect(coverDecodeWidth(0.1, 1), 1);
  });
}
