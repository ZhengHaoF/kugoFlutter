import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../../core/platform.dart';

/// 鼠标滚轮在横向滚动容器上的行为（仅桌面端有效；触屏永远走原生拖拽）。
enum KugoHWheelMode {
  /// 不接管：竖向滚轮事件留给外层竖向页面。
  ///
  /// chips/页签行的默认——它们嵌在竖向页面里，溢出是附带情况，
  /// 劫持页面滚动比「滚轮滚不动 chips」更烦。
  none,

  /// 交给 [SilkyScroll]：竖向滚轮滚动横排本身，滚到边缘自动把剩余 delta
  /// 转发给外层竖向页面。
  ///
  /// 不能自己写 `pointerSignalResolver.register` 手搓这套：外层竖向页面的
  /// 滚轮是 silky 用**裸 `Listener`** 接的，不参与 resolver 竞争，内层注册
  /// 得再干净页面也照样滚 → 双重滚动。silky 的 hover-stack
  /// （`SilkyScrollGlobalManager.keyStack`）才是抑制外层的那道闸。
  silky,

  /// 自研 `pointerScroll` 路径：滚轮直接 forcePixels，交给 physics 的
  /// ballistic 收尾。
  ///
  /// 保留给依赖「甩动后吸附」的调用方（FM 黑胶盘阵的 `_OneStepSnapPhysics`）：
  /// silky 的 `SilkyScrollPosition.pointerScroll` 对 mouse 事件直接吞掉，
  /// 吸附链会断。
  raw,
}

/// 横排滚动容器：去滚动条 + 边缘渐隐 + 鼠标拖拽 + 可选滚轮接管。
///
/// 桌面端 Windows 上横向 [ListView] 的短板与对策：
/// 1. **看不出「右边还有内容」** → 不用常显 Scrollbar（它一直是项目里一条
///    4px 灰条，割裂卡片行），改成溢出侧的边缘渐隐（[KugoHScroll.fadeEdges]）；
/// 2. **鼠标拖不动** → 框架默认 `dragDevices` 不含 [PointerDeviceKind.mouse]
///    （Flutter 源码 `scroll_configuration.dart` 的 `_kTouchLikeDeviceTypes`），
///    这里显式放开（[KugoHScroll.draggable]）；
/// 3. **滚轮滚不动横向** → [KugoHWheelMode.silky]，悬停时 hijack、到边缘
///    放行回外层页面。
///
/// 触摸板两指横滑（dx 分量）**不需要任何特殊处理**：框架的 Scrollable 在
/// `PointerSignalResolver` 里自己会处理。这里再动一次就是双倍速——
/// 曾经的 bug，现在 dx 一律不碰。
class KugoHScroll extends StatefulWidget {
  const KugoHScroll({
    super.key,
    required this.builder,
    this.controller,
    this.wheelMode = KugoHWheelMode.none,
    this.fadeEdges = true,
    this.draggable = true,
    this.fadeLength = 24,
  });

  /// 构建横向滚动视图。
  ///
  /// [controller] 是容器注入的（外部传入的，或 silky 托管的那一个），
  /// 调用方必须挂到自己的 ScrollView 上。[physics] 只在
  /// [KugoHWheelMode.silky] 下非空（silky 的动态 physics，需转发给
  /// ScrollView，否则阻断态不生效）；其余模式传 null。
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    ScrollPhysics? physics,
  ) builder;

  /// 外部已经持有 controller 时传入（例如需要监听做吸附）。
  final ScrollController? controller;

  final KugoHWheelMode wheelMode;

  /// 溢出侧的边缘渐隐。卡片行开，chips/页签行关（渐隐会把胶囊圆角
  /// 啃出豁口，且它们本就很少溢出）。
  final bool fadeEdges;

  /// 桌面端允许鼠标按住拖动（框架默认集合不含 mouse）。
  final bool draggable;

  /// 渐隐宽度（逻辑像素）。
  final double fadeLength;

  @override
  State<KugoHScroll> createState() => _KugoHScrollState();
}

/// 框架默认 dragDevices（touch/stylus/invertedStylus/trackpad/unknown）
/// + mouse。只挂在横排容器上，不碰全局——歌单详情等地方的文本选择
/// 不受影响（框架注释明确警告全局放开 mouse 拖拽会毁掉文本选择）。
const Set<PointerDeviceKind> _kDragDevicesWithMouse = <PointerDeviceKind>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.unknown,
  PointerDeviceKind.mouse,
};

class _KugoHScrollState extends State<KugoHScroll> {
  /// 始终创建：外部 controller 可能在生命周期内被替换（didUpdateWidget），
  /// 留一个自己的可以让 getter 永不返回 null，代价只是一条没人 attach 的空
  /// controller。
  late final ScrollController _owned = ScrollController();

  ScrollController get _controller => widget.controller ?? _owned;

  /// 两端是否还有内容（驱动渐隐；只在布尔翻转时 setState，不跟帧）。
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  /// 鼠标是否正按住拖动（驱动 grabbing 光标）。
  bool _dragging = false;

  static const double _kEdgeEpsilon = 0.5;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshEdges);
  }

  @override
  void dispose() {
    _controller.removeListener(_refreshEdges);
    _owned.dispose();
    super.dispose();
  }

  void _refreshEdges() {
    if (!mounted) return;
    var back = false;
    var forward = false;
    final position = _controller.hasClients ? _controller.position : null;
    if (position != null && position.hasContentDimensions) {
      back = position.pixels > position.minScrollExtent + _kEdgeEpsilon;
      forward = position.pixels < position.maxScrollExtent - _kEdgeEpsilon;
    }
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // dragDetails 非空 = 用户发起拖拽（触屏手指 / 桌面按住滑）。
      if (!_dragging) setState(() => _dragging = true);
    } else if (notification is ScrollEndNotification) {
      if (_dragging) setState(() => _dragging = false);
    } else if (notification is ScrollMetricsNotification) {
      // attach / 内容尺寸变化：首帧布局后才有 maxScrollExtent。
      _refreshEdges();
    }
    return false; // 不吞，silky 与调用方自己的监听还要收。
  }

  // ── raw 滚轮路径 ────────────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    // dx 占优 = 触摸板横滑：框架 Scrollable 自己会处理（它的 position 在
    // resolver 里排更前面），这里再动一次就是双倍速 —— 只接管 dy。
    if (event.scrollDelta.dx.abs() > dy.abs()) return;
    if (dy == 0.0) return;
    _scrollBy(dy);
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

  // ── 组装 ────────────────────────────────────────────────────────

  Widget _buildContent() {
    if (widget.wheelMode == KugoHWheelMode.silky && isDesktopPlatform) {
      return SilkyScroll(
        controller: _controller,
        direction: Axis.horizontal,
        // dy 滚轮滚横排；到边缘由 silky 转发给外层竖向页面。
        mouseWheelVerticalDeltaBehavior:
            MouseWheelVerticalDeltaBehavior.always,
        // 与横向 ListView 的默认 physics 对齐（Windows 下 Clamping）。
        physics: ScrollConfiguration.of(context).getScrollPhysics(context),
        builder: (context, controller, physics, _) =>
            widget.builder(context, controller, physics),
      );
    }
    final inner = widget.builder(context, _controller, null);
    if (widget.wheelMode == KugoHWheelMode.raw) {
      return Listener(onPointerSignal: _onPointerSignal, child: inner);
    }
    return inner;
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    // 触屏：拖拽 + 惯性都是系统级的，什么都不用包。
    if (!isDesktopPlatform) return content;

    Widget desktop = content;
    if (widget.draggable) {
      desktop = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: _kDragDevicesWithMouse,
        ),
        child: desktop,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: MouseRegion(
        cursor: _dragging ? SystemMouseCursors.grabbing : MouseCursor.defer,
        child: _buildFade(desktop),
      ),
    );
  }

  /// 溢出侧边缘渐隐（dstIn 透明遮罩）。
  ///
  /// **包装层必须常驻、只让渐变内容变**：曾按需插入/移除 [ShaderMask]，
  /// 结果插入的那一刻 Flutter 把它下面整棵子树（ListView + silky State +
  /// ScrollPosition）卸载重挂——滚轮 tick 一次就被 dispose、offset 归零、
  /// 拖拽失效。现在树形恒定，只有 shaderCallback 的返回值随状态变。
  Widget _buildFade(Widget child) {
    if (!widget.fadeEdges) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        const transparent = Color(0x00000000);
        const opaque = Color(0xFF000000);
        if (!rect.width.isFinite || rect.width <= 0) {
          return const LinearGradient(colors: [opaque, opaque])
              .createShader(rect);
        }
        final len = (widget.fadeLength / rect.width).clamp(0.0, 0.5);
        final colors = <Color>[];
        final stops = <double>[];
        if (_canScrollBack) {
          colors.add(transparent);
          stops.add(0);
        }
        colors.add(opaque);
        stops.add(_canScrollBack ? len : 0);
        colors.add(opaque);
        stops.add(_canScrollForward ? 1 - len : 1);
        if (_canScrollForward) {
          colors.add(transparent);
          stops.add(1);
        }
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
          stops: stops,
        ).createShader(rect);
      },
      child: child,
    );
  }
}
