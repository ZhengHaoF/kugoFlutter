import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/platform.dart';
import '../../core/theme/kugo_theme.dart';

/// 横向滚动容器：桌面端常显细滚动条 + 触摸板横滑 / 鼠标滚轮支持。
///
/// Windows 上横向 [ListView] 有两个先天短板：
/// 1. 鼠标滚轮默认只作用于竖向 [Scrollable]，横向内容除了拖拽基本滚不动；
/// 2. 全项目没有一条 Scrollbar，用户看不出「右边还有内容」。
///
/// 本组件两件事一起解决，调用方只需要把横向列表交给 [builder]，
/// 并用回调给出的 controller（外部已有则用 [controller]，不再重复创建）。
///
/// 滚轮策略分两档，避免把页面的竖向滚动劫走：
/// * 横向分量占优时（触摸板两指横滑）→ 一定转成横向位移；
/// * 竖向分量占优时（鼠标滚轮）→ 只有 [wheelToHorizontal] 为 true 才接管，
///   否则事件留给外层竖向页面，这是 Windows 端的默认预期。
///
/// 内容没溢出时不画任何东西（ScrollbarPainter 自带该判断），移动端也不画
/// （触屏靠拖拽，桌面才需要滚动条）。
class KugoHScroll extends StatefulWidget {
  const KugoHScroll({
    super.key,
    required this.builder,
    this.controller,
    this.wheelToHorizontal = false,
    this.thickness = 4,
    this.crossAxisMargin = 2,
  });

  /// 构建横向滚动视图，并把 controller 装到它的 ScrollView 上。
  final Widget Function(BuildContext context, ScrollController controller) builder;

  /// 外部已经持有 controller 时传入（例如需要监听做吸附）。
  final ScrollController? controller;

  /// 是否把鼠标滚轮的竖向分量转成横向滚动。
  ///
  /// 只对「整屏独占的横向容器」开（FM 黑胶盘阵等）；嵌在竖向滚动页面里的
  /// 筛选条/chip 行不要开，否则用户滚页面时会被卡在横条里。
  final bool wheelToHorizontal;

  final double thickness;
  final double crossAxisMargin;

  @override
  State<KugoHScroll> createState() => _KugoHScrollState();
}

class _KugoHScrollState extends State<KugoHScroll> {
  /// 始终创建：外部 controller 可能在生命周期内被替换（didUpdateWidget），
  /// 留一个自己的可以让 getter 永不返回 null，代价只是一条没人 attach 的空
  /// controller。
  late final ScrollController _owned = ScrollController();

  ScrollController get _controller => widget.controller ?? _owned;

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = _horizontalDelta(event);
    if (delta == 0.0) return;
    _scrollBy(delta);
  }

  /// 归一化为「横向应该走的位移」，0 表示本次事件不该由横向容器处理。
  double _horizontalDelta(PointerScrollEvent event) {
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (dx.abs() > dy.abs()) return dx;
    return widget.wheelToHorizontal ? dy : 0.0;
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    final max = position.maxScrollExtent;
    if (max - position.minScrollExtent <= 0.5) return;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, max);
    if ((target - position.pixels).abs() < 0.5) return;
    // 走 position 自己的 pointerScroll 而不是 animateTo：它 forcePixels 之后会
    // goBallistic，交给 physics 收尾——FM 黑胶盘阵的吸附（_OneStepSnapPhysics）
    // 才能把 CD 摆正，也不会出现「动画结束时停在两盘之间」。
    position.pointerScroll(target - position.pixels);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _controller);
    // 触屏拖拽已经够直观，滚动条只在桌面出现。
    if (!isDesktopPlatform) {
      return Listener(onPointerSignal: _onPointerSignal, child: content);
    }
    final kugo = KugoTheme.of(context);
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: ScrollbarTheme(
        data: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            kugo.textTertiary.withValues(alpha: 0.5),
          ),
          trackColor: const WidgetStatePropertyAll(Colors.transparent),
          trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
          thickness: WidgetStateProperty.all(widget.thickness),
          radius: const Radius.circular(3),
          minThumbLength: 28,
          crossAxisMargin: widget.crossAxisMargin,
        ),
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: content,
        ),
      ),
    );
  }
}
