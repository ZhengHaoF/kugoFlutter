import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';

import '../../core/platform.dart';

/// 与原先页面默认一致：可下拉刷新 + 惯性回弹。
const ScrollPhysics kSmoothDefaultPhysics = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

/// 桌面滚轮平滑（silky_scroll）；移动端保持原生 [CustomScrollView]。
class SmoothCustomScrollView extends StatelessWidget {
  const SmoothCustomScrollView({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.slivers = const <Widget>[],
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return CustomScrollView(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        slivers: slivers,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return CustomScrollView(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          slivers: slivers,
        );
      },
    );
  }
}

/// 桌面滚轮平滑的 [ListView.builder]。
class SmoothListViewBuilder extends StatelessWidget {
  const SmoothListViewBuilder({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.padding,
    this.shrinkWrap = false,
    this.itemCount,
    required this.itemBuilder,
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final int? itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return ListView.builder(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        padding: padding,
        shrinkWrap: shrinkWrap,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return ListView.builder(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          padding: padding,
          shrinkWrap: shrinkWrap,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// 桌面滚轮平滑的 [ListView.separated]。
class SmoothListViewSeparated extends StatelessWidget {
  const SmoothListViewSeparated({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.padding,
    this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final int? itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return ListView.separated(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        padding: padding,
        itemCount: itemCount ?? 0,
        itemBuilder: itemBuilder,
        separatorBuilder: separatorBuilder,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return ListView.separated(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          padding: padding,
          itemCount: itemCount ?? 0,
          itemBuilder: itemBuilder,
          separatorBuilder: separatorBuilder,
        );
      },
    );
  }
}

/// 桌面滚轮平滑的 [GridView.builder]。
class SmoothGridViewBuilder extends StatelessWidget {
  const SmoothGridViewBuilder({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.padding,
    this.shrinkWrap = false,
    required this.gridDelegate,
    this.itemCount,
    required this.itemBuilder,
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final SliverGridDelegate gridDelegate;
  final int? itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return GridView.builder(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        padding: padding,
        shrinkWrap: shrinkWrap,
        gridDelegate: gridDelegate,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return GridView.builder(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          padding: padding,
          shrinkWrap: shrinkWrap,
          gridDelegate: gridDelegate,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// 桌面滚轮平滑的 [SingleChildScrollView]。
class SmoothSingleChildScrollView extends StatelessWidget {
  const SmoothSingleChildScrollView({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.padding,
    required this.child,
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return SingleChildScrollView(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        padding: padding,
        child: child,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return SingleChildScrollView(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          padding: padding,
          child: child,
        );
      },
    );
  }
}


/// 桌面滚轮平滑的 [ListView]（children 列表）。
class SmoothListView extends StatelessWidget {
  const SmoothListView({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.physics,
    this.padding,
    this.children = const <Widget>[],
  });

  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final base = physics ?? kSmoothDefaultPhysics;

    if (!isDesktopPlatform) {
      return ListView(
        controller: controller,
        scrollDirection: scrollDirection,
        physics: base,
        padding: padding,
        children: children,
      );
    }

    return SilkyScroll(
      controller: controller,
      physics: base,
      direction: scrollDirection,
      builder: (context, controller, physics, _) {
        return ListView(
          controller: controller,
          scrollDirection: scrollDirection,
          physics: physics,
          padding: padding,
          children: children,
        );
      },
    );
  }
}
