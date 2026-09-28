import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/kugo_theme.dart';

/// 统一的可点表面：手型光标 + hover 底纹 + 点击。
///
/// 替换散落的裸 `GestureDetector`（无光标、无 hover）和风格不一的 `InkWell`。
/// 圆角卡片、列表行、封面格都走这里，保证桌面端同一套悬停语言。
class KugoClickable extends StatefulWidget {
  const KugoClickable({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.borderRadius = BorderRadius.zero,
    this.hoverColor,
    this.padding = EdgeInsets.zero,
    this.behavior = HitTestBehavior.opaque,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final BorderRadius borderRadius;

  /// Defaults to a theme-aware black wash, same family as sidebar hover.
  final Color? hoverColor;
  final EdgeInsetsGeometry padding;
  final HitTestBehavior behavior;

  @override
  State<KugoClickable> createState() => _KugoClickableState();
}

class _KugoClickableState extends State<KugoClickable> {
  bool _hovered = false;

  // Stable tear-offs so MouseRegion doesn't see new closures every rebuild.
  void _handleEnter(PointerEnterEvent _) {
    if (_hovered) return;
    setState(() => _hovered = true);
  }

  void _handleExit(PointerExitEvent _) {
    if (!_hovered || !mounted) return;
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final hoverFill =
        widget.hoverColor ?? Colors.black.withValues(alpha: kugo.isLight ? 0.08 : 0.18);
    // Same RGB as the hover fill (black); only alpha animates.
    final idleFill = Colors.black.withValues(alpha: 0);

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null ? hoverFill : idleFill,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Icon button that always carries a tooltip — desktop discoverability floor.
///
/// Wraps Material [IconButton] so call sites cannot forget the tooltip the way
/// bare icon-only buttons used to.
class KugoIconButton extends StatelessWidget {
  const KugoIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize,
    this.color,
    this.visualDensity,
    this.constraints,
    this.style,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double? iconSize;
  final Color? color;
  final VisualDensity? visualDensity;
  final BoxConstraints? constraints;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      color: color,
      visualDensity: visualDensity,
      constraints: constraints,
      style: style,
    );
  }
}

/// Icon-only action with hover wash + mandatory tooltip.
///
/// For toolbar chrome that should not use Material ink (custom toolbars,
/// sidebar trailing actions, player chips).
class KugoIconAction extends StatelessWidget {
  const KugoIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 20,
    this.color,
    this.hoverRadius = 8,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final double hoverRadius;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: KugoClickable(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(hoverRadius),
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
