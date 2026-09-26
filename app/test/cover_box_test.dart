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
}
