import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/theme/responsive.dart';

/// 一行铺满的折算规则：先定张数，再等分拉伸到整行。
void main() {
  // 发现页排行榜的实参：最小 168、上限 260、间距 12。
  ({int visible, double width}) fit(double available, int count) => fitStripRow(
        available: available,
        count: count,
        minWidth: 168,
        maxWidth: 260,
        gap: 12,
      );

  double rowWidth(({int visible, double width}) fit) =>
      fit.visible * fit.width + (fit.visible - 1) * 12;

  group('fitStripRow：一行铺满', () {
    test('超宽窗口（2560 屏，12 个榜单）整行刚好铺满', () {
      final f = fit(2308, 12);
      expect(f.visible, 12);
      expect(f.width, closeTo(181.33, 0.01));
      expect(rowWidth(f), closeTo(2308, 0.01));
    });

    test('中等窗口：只放得下 7 张，这 7 张拉伸铺满，其余横滚', () {
      final f = fit(1368, 12);
      expect(f.visible, 7);
      expect(f.visible, lessThan(12));
      expect(f.width, greaterThan(168));
      expect(rowWidth(f), closeTo(1368, 0.01));
    });

    test('窄窗口：放得下 4 张，仍不小于最小宽度', () {
      final f = fit(768, 12);
      expect(f.visible, 4);
      expect(f.width, greaterThanOrEqualTo(168));
      expect(rowWidth(f), closeTo(768, 0.01));
    });

    test('窗口极窄：只放得下 1 张，且不小于最小宽度', () {
      final f = fit(200, 12);
      expect(f.visible, 1);
      expect(f.width, 200);
      expect(f.width, greaterThanOrEqualTo(168));
    });

    test('条目很少：封顶在 maxWidth，不把一张卡拉成一整行', () {
      final f = fit(2300, 2);
      expect(f.visible, 2);
      expect(f.width, 260);
      // 封顶后一行铺不满，由调用方居中处理。
      expect(rowWidth(f), lessThan(2300));
    });

    test('退化输入不抛异常', () {
      expect(fit(2308, 0).visible, 0);
      expect(fit(2308, 0).width, 168);
      expect(fit(double.infinity, 5).visible, 5);
      expect(fit(double.infinity, 5).width, 168);
      expect(fit(0, 5).visible, 5);
      expect(fit(-10, 5).width, 168);
    });
  });

  group('DesktopContentConstraint：表单类页面仍按固定上限收边', () {
    Future<double> childWidth(WidgetTester tester, Size surface,
        {double maxWidth = 1120}) async {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopContentConstraint(
              maxWidth: maxWidth,
              child: SizedBox.expand(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byKey(key)).width;
    }

    testWidgets('宽屏收边到 maxWidth', (tester) async {
      expect(await childWidth(tester, const Size(2000, 800)), 1120);
      expect(
        await childWidth(tester, const Size(2000, 800), maxWidth: 800),
        800,
      );
    });

    testWidgets('手机宽度不下发约束，内容铺满', (tester) async {
      expect(await childWidth(tester, const Size(400, 800)), 400);
    });
  });
}
