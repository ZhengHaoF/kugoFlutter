import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/widgets/kugo_h_scroll.dart';
import 'package:silky_scroll/silky_scroll.dart';

/// KugoHScroll 行为回归：滚轮 hijack / 边缘放行 / 鼠标拖拽 / 点击不误触 /
/// 触控板横滑单份 / chips 行不劫持页面 / 渐隐层不引发子树重挂。
///
/// 跑在 Windows 宿主机上，`isDesktopPlatform` 为 true，桌面路径全部生效。

const _kCardCount = 10;
const _kCardWidth = 100.0;
const _kRowHeight = 120.0;
const _kRowTop = 300.0; // 外层 ListView 头部 SizedBox 的高度
const _kHoverPoint = Offset(160, _kRowTop + 10);

ScrollController? _rowController;
ScrollController? _pageController;
final List<int> _taps = <int>[];

Widget _buildRow({
  KugoHWheelMode mode = KugoHWheelMode.silky,
  bool fadeEdges = true,
}) {
  return KugoHScroll(
    controller: _rowController,
    wheelMode: mode,
    fadeEdges: fadeEdges,
    builder: (context, controller, physics) => SizedBox(
      height: _kRowHeight,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: physics,
        itemExtent: _kCardWidth,
        itemCount: _kCardCount,
        itemBuilder: (context, index) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _taps.add(index),
          child: ColoredBox(
            color: Colors.primaries[index % Colors.primaries.length],
            child: Center(child: Text('$index')),
          ),
        ),
      ),
    ),
  );
}

Widget _buildPage(Widget row) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 320,
        height: 600,
        child: ListView(
          controller: _pageController,
          children: [
            const SizedBox(height: _kRowTop),
            row,
            const SizedBox(height: 300),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpRow(
  WidgetTester tester, {
  KugoHWheelMode mode = KugoHWheelMode.silky,
  bool fadeEdges = true,
}) async {
  await tester.pumpWidget(
    _buildPage(_buildRow(mode: mode, fadeEdges: fadeEdges)),
  );
  await tester.pump();
}

double get _rowOffset => _rowController!.offset;
double get _pageOffset => _pageController!.offset;

/// silky 的滚轮是 Ticker 驱动的指数收敛动画，pumpAndSettle 默认 100ms/帧
/// 正好卡着它 `dt > 0.1` 的守卫边界，统一按 16ms 步进驱动。
Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 16));

void main() {
  setUp(() {
    SilkyScrollGlobalManager.instance.resetForTesting();
    _rowController = ScrollController();
    _pageController = ScrollController();
    _taps.clear();
  });

  tearDown(() {
    _rowController?.dispose();
    _pageController?.dispose();
    _rowController = null;
    _pageController = null;
    SilkyScrollGlobalManager.instance.resetForTesting();
  });

  testWidgets('dy 滚轮滚动横排，外层页面不动（悬停 hijack）', (tester) async {
    await _pumpRow(tester);
    expect(_rowOffset, 0);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_kHoverPoint));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await _settle(tester);

    expect(_rowOffset, greaterThan(50));
    expect(_pageOffset, 0);
  });

  testWidgets('横排滚到边缘再给滚轮，delta 放行给外层页面', (tester) async {
    await _pumpRow(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_kHoverPoint));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 2000)));
    await _settle(tester);

    final atEnd = _rowOffset;
    expect(atEnd, greaterThan(600)); // 10×100 - 320 视口 = 680

    await tester.pump(const Duration(milliseconds: 700)); // 越过 silky edgeLockingDelay
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await _settle(tester);

    expect(_rowOffset, atEnd); // 行不再动
    expect(_pageOffset, greaterThan(0)); // 页面接管
  });

  testWidgets('鼠标按住拖动滚动横排；点击卡片不误判为拖拽', (tester) async {
    await _pumpRow(tester);

    // 注意：widget test 里鼠标拖拽必须**分两次 move**——第一次建立手势
    // 基线，第二次越过 touchSlop 才被 DragGestureRecognizer 接受
    // （单次大 moveBy 无效，这是 flutter_test 的手势切分行为）。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(_kHoverPoint);
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-170, 0));
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    expect(_rowOffset, greaterThanOrEqualTo(150));
    expect(_taps, isEmpty);

    // 轻点（不移动）应命中卡片 onTap。此时已向左滚了约 170px，
    // 卡片 0 已出视口，点屏幕内的卡片 3（中心 ≈ x=180）。
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(_taps, [3]);
    expect(_rowOffset, greaterThanOrEqualTo(150));
  });

  testWidgets('触摸板横滑 dx 只滚一份（不双倍、不与其它通道抵消）', (tester) async {
    await _pumpRow(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_kHoverPoint));
    await tester.sendEventToBinding(pointer.scroll(const Offset(80, 0)));
    await _settle(tester);

    final first = _rowOffset;
    expect(first, greaterThan(40), reason: '应约等于 80，而不是 0（被抵消）');
    expect(first, lessThan(120), reason: '不应翻倍到 160');

    await tester.sendEventToBinding(pointer.scroll(const Offset(80, 0)));
    await _settle(tester);
    expect(_rowOffset, greaterThan(first + 40), reason: '第二次横滑应继续前进');
  });

  testWidgets('none 模式（chips 行）滚轮只滚页面，不动横排', (tester) async {
    await _pumpRow(tester, mode: KugoHWheelMode.none);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_kHoverPoint));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await _settle(tester);

    expect(_rowOffset, 0);
    expect(_pageOffset, greaterThan(50));
  });

  testWidgets('渐隐层常驻：滚动连续不重置（回归：子树被重挂）', (tester) async {
    // 曾经按需插入 ShaderMask → 整棵子树卸载重挂 → position 归零、
    // silky ticker 被 dispose。这里用连续两次滚轮钉死「位移单调递增」。
    await _pumpRow(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(_kHoverPoint));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await _settle(tester);
    final first = _rowOffset;
    expect(first, greaterThan(0));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await _settle(tester);
    expect(
      _rowOffset,
      greaterThan(first + 20),
      reason: '第二次滚轮应在第一次的基础上继续，而不是被重置回 0',
    );

    // fadeEdges: true 有渐隐层，false 没有。
    expect(find.byType(ShaderMask), findsOneWidget);
    await _pumpRow(tester, mode: KugoHWheelMode.none, fadeEdges: false);
    expect(find.byType(ShaderMask), findsNothing);
  });
}
