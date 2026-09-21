import 'package:flutter/material.dart';

/// Whether the current layout should use desktop wide presentation (>= 800px).
bool isDesktopView(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 800;

/// Centers and limits content width on wide screens to prevent stretched, empty layouts.
class DesktopContentConstraint extends StatelessWidget {
  const DesktopContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = 1120.0,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopView(context)) {
      return Padding(padding: padding, child: child);
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
