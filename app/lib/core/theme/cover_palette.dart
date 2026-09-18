import 'package:flutter/material.dart';

import 'kugo_tokens.dart';

/// Cover palette adapts to the active [KugoThemeBinding] brightness.
class CoverPalette {
  static List<Color> fromSeed(String seed) {
    final hash = seed.hashCode & 0xffffffff;
    final hue = (210 + (hash % 120)).toDouble() % 360;
    final light = KugoThemeBinding.palette.isLight;
    if (light) {
      // Clean cool tints — avoid muddy browns on light UI.
      final a = HSLColor.fromAHSL(1, hue, 0.35, 0.86).toColor();
      final b = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.30, 0.92).toColor();
      final c = HSLColor.fromAHSL(1, (hue + 20) % 360, 0.20, 0.96).toColor();
      return [a, b, c];
    }
    final a = HSLColor.fromAHSL(1, hue, 0.48, 0.46).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 50) % 360, 0.52, 0.24).toColor();
    final c = HSLColor.fromAHSL(1, (hue + 20) % 360, 0.40, 0.16).toColor();
    return [a, b, c];
  }

  static LinearGradient playerBackground(String coverSeed) {
    final p = KugoThemeBinding.palette;
    if (p.isLight) {
      // Soft brand wash → page bg (no heavy cover tint).
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          p.primary.withValues(alpha: 0.12),
          p.secondary.withValues(alpha: 0.06),
          p.bg,
        ],
        stops: const [0.0, 0.4, 1.0],
      );
    }
    final colors = fromSeed(coverSeed);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        colors[0].withValues(alpha: 0.55),
        colors[1].withValues(alpha: 0.35),
        p.bg,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }

  static Color accentFromSeed(String seed) {
    final hash = seed.hashCode & 0xffffffff;
    final hue = (210 + (hash % 120)).toDouble() % 360;
    final light = KugoThemeBinding.palette.isLight;
    return HSLColor.fromAHSL(
      1,
      hue,
      light ? 0.55 : 0.48,
      light ? 0.48 : 0.46,
    ).toColor();
  }
}
