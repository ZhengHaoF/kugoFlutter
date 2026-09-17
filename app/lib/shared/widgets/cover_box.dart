import 'package:flutter/material.dart';

import '../../core/theme/cover_palette.dart';
import '../../core/theme/kugo_tokens.dart';

/// 封面占位：用 seed 生成与歌曲相关的渐变色块。
class CoverBox extends StatelessWidget {
  const CoverBox({
    super.key,
    required this.seed,
    this.size = 56,
    this.radius = KugoRadius.cover,
    this.child,
  });

  final String seed;
  final double size;
  final double radius;
  final Widget? child;

  bool get _fillsParent => size <= 0;

  @override
  Widget build(BuildContext context) {
    final colors = CoverPalette.fromSeed(seed);
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0.0, 0.55, 1.0],
      ),
    );
    if (_fillsParent) {
      return DecoratedBox(decoration: decoration, child: child);
    }
    return Container(
      width: size,
      height: size,
      decoration: decoration,
      alignment: Alignment.center,
      child: child,
    );
  }
}
