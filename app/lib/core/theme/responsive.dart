import 'package:flutter/material.dart';

/// Whether the current layout should use desktop wide presentation (>= 800px).
bool isDesktopView(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 800;

/// Preferred cover-card edge on wide layouts — denser than mobile 2-col grids,
/// aligned with the explore rank strip (~168px) and typical desktop music apps.
const double kDesktopCoverExtent = 180;

/// Adaptive cover-grid delegate for playlist / rank board cards.
///
/// Mobile keeps the 2-column layout pages were designed for. Desktop picks
/// column count from available width so cards stay near [preferredExtent]
/// instead of stretching with the window.
SliverGridDelegate coverGridDelegate(
  BuildContext context, {
  double preferredExtent = kDesktopCoverExtent,
  double mobileAspectRatio = 0.78,
  double desktopAspectRatio = 0.82,
  double mainAxisSpacing = 16,
  double crossAxisSpacing = 16,
  int minColumns = 2,
  int maxColumns = 8,
}) {
  // Without a measured content width, assume the common desktop content box
  // after sidebar + DesktopContentConstraint.
  return coverGridDelegateForWidth(
    context,
    1280,
    preferredExtent: preferredExtent,
    mobileAspectRatio: mobileAspectRatio,
    desktopAspectRatio: desktopAspectRatio,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    minColumns: minColumns,
    maxColumns: maxColumns,
  );
}

/// Same as [coverGridDelegate] but uses the actual layout [width] so column
/// count tracks the content box (after sidebar / DesktopContentConstraint).
SliverGridDelegate coverGridDelegateForWidth(
  BuildContext context,
  double width, {
  double preferredExtent = kDesktopCoverExtent,
  double mobileAspectRatio = 0.78,
  double desktopAspectRatio = 0.82,
  double mainAxisSpacing = 16,
  double crossAxisSpacing = 16,
  int minColumns = 2,
  int maxColumns = 8,
}) {
  if (!isDesktopView(context)) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: minColumns,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      childAspectRatio: mobileAspectRatio,
    );
  }
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: coverGridColumnCount(
      context,
      width,
      preferredExtent: preferredExtent,
      crossAxisSpacing: crossAxisSpacing,
      minColumns: minColumns,
      maxColumns: maxColumns,
    ),
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    childAspectRatio: desktopAspectRatio,
  );
}

/// Column count for cover grids given [width].
int coverGridColumnCount(
  BuildContext context,
  double width, {
  double preferredExtent = kDesktopCoverExtent,
  double crossAxisSpacing = 16,
  int minColumns = 2,
  int maxColumns = 8,
}) {
  if (!isDesktopView(context)) return minColumns;
  if (!width.isFinite || width <= 0) return minColumns;
  final cell = preferredExtent + crossAxisSpacing;
  final cols = ((width + crossAxisSpacing) / cell).floor();
  return cols.clamp(minColumns, maxColumns);
}

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
