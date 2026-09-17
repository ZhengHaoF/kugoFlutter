import 'package:flutter/material.dart';

import 'kugo_tokens.dart';

/// 从封面 seed 确定性取色，驱动播放页/MiniBar 渐变。
abstract final class CoverPalette {
  static List<Color> fromSeed(String seed) {
    final hash = seed.hashCode & 0xffffffff;
    final hue = (210 + (hash % 120)).toDouble() % 360;
    final a = HSLColor.fromAHSL(1, hue, 0.48, 0.46).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 50) % 360, 0.52, 0.24).toColor();
    final c = HSLColor.fromAHSL(1, (hue + 20) % 360, 0.40, 0.16).toColor();
    return [a, b, c];
  }

  /// 播放页全屏背景：封面主色 → 深底。
  static LinearGradient playerBackground(String coverSeed) {
    final colors = fromSeed(coverSeed);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors[0].withValues(alpha: 0.55),
        colors[1].withValues(alpha: 0.35),
        KugoColors.bg,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }

  /// MiniBar 强调色（进度条）。
  static Color accentFromSeed(String seed) => fromSeed(seed).first;
}
