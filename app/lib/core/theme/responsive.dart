import 'package:flutter/material.dart';

/// Whether the current layout should use desktop wide presentation (>= 800px).
bool isDesktopView(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 800;

/// Preferred cover-card edge on wide layouts — denser than mobile 2-col grids,
/// aligned with the explore rank strip (~168px) and typical desktop music apps.
const double kDesktopCoverExtent = 180;

/// 把一行条目按 [available] 宽度铺满：[minWidth] 是卡片最小宽度，
/// 先算出「至少还能放下几张」，再把这几张等分拉伸到整行宽度。
///
/// 返回 `(visible, width)`：`visible` 是铺满一行需要的张数（不超过 [count]），
/// `width` 是每张卡的宽度（不超过 [maxWidth]）。
///
/// 例：可用 2308、12 张、最小 168、间距 12 → 12 张每张 181，刚好铺满；
/// 窗口变窄到 768 时 → 4 张每张 183，剩余的可横向滚动。
({int visible, double width}) fitStripRow({
  required double available,
  required int count,
  required double minWidth,
  required double maxWidth,
  double gap = 0,
}) {
  if (count <= 0) return (visible: 0, width: minWidth);
  if (!available.isFinite || available <= 0) {
    return (visible: count, width: minWidth);
  }
  final visible = ((available + gap) / (minWidth + gap)).floor().clamp(1, count);
  final width = (available - gap * (visible - 1)) / visible;
  return (visible: visible, width: width > maxWidth ? maxWidth : width);
}

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

/// Content-width tiers for wide layouts.
///
/// 内容页**一律满宽**：「我的」/「个人中心」/「播放历史」/「我喜欢」/「搜索」
/// 之间会互相跳转，左右边缘必须落在同一条线上——给其中一部分限宽、另一部分
/// 满宽，切页时左边缘会横跳，看起来「没对齐」（见
/// `docs/UI评审与优化清单.md` §7）。所以这里只剩两类真正需要收边的例外：
/// 阅读型 [kDesktopReadingWidth] 与表单型 [kDesktopFormWidth]。
///
/// 需要「列表限宽」那档（原 960）时不要凭记忆加回来——先确认它不会跟内容页
/// 的左边缘约定打架。
const double kDesktopReadingWidth = 720;
const double kDesktopFormWidth = 800;

/// Centers and limits content width on wide screens to prevent stretched, empty
/// layouts. 只给「阅读型 / 表单型」页面用；内容页（列表 / 卡片库）不禁宽。
class DesktopContentConstraint extends StatelessWidget {
  const DesktopContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = 1120.0,
    this.padding = EdgeInsets.zero,
  });

  /// 阅读型：歌曲详情 —— 720。
  const DesktopContentConstraint.reading({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  }) : maxWidth = kDesktopReadingWidth;

  /// 表单型：设置页 —— 800。
  const DesktopContentConstraint.form({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  }) : maxWidth = kDesktopFormWidth;

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
