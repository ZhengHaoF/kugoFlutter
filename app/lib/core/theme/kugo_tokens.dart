import 'package:flutter/material.dart';

/// Resolved color tokens for the active theme (dark / light).
class KugoPalette {
  const KugoPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceElevated,
    required this.primary,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.overlay,
    required this.playerGradientStops,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceElevated;
  final Color primary;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color overlay;
  final List<Color> playerGradientStops;

  bool get isLight => brightness == Brightness.light;

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, secondary],
      );

  LinearGradient get playerGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: playerGradientStops,
      );

  static const dark = KugoPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0E14),
    surface: Color(0xFF151A24),
    surfaceElevated: Color(0xFF1C2230),
    primary: Color(0xFF5B7CFF),
    secondary: Color(0xFFA855F7),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9AA3B2),
    textTertiary: Color(0xFF5C6575),
    divider: Color(0x14FFFFFF),
    overlay: Color(0x66000000),
    playerGradientStops: [
      Color(0xFF1A1F3A),
      Color(0xFF2A1F4A),
      Color(0xFF0B0E14),
    ],
  );

  static const light = KugoPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF2F4F8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    primary: Color(0xFF3D6AE8),
    secondary: Color(0xFF8B5CF6),
    textPrimary: Color(0xFF12141A),
    textSecondary: Color(0xFF5B6472),
    textTertiary: Color(0xFF9AA3B2),
    divider: Color(0x1A000000),
    overlay: Color(0x22000000),
    playerGradientStops: [
      Color(0xFFDDE7FF),
      Color(0xFFF0EBFF),
      Color(0xFFF2F4F8),
    ],
  );
}

/// Process-wide palette used by [KugoColors]/[KugoTypography] getters so
/// existing call sites pick up light/dark without a context parameter.
/// Also mirrored into [KugoTheme] ThemeExtension via [ThemeData].
abstract final class KugoThemeBinding {
  static KugoPalette palette = KugoPalette.dark;

  static void apply(KugoPalette p) => palette = p;
}

abstract final class KugoRadius {
  static const chip = 999.0;
  static const card = 20.0;
  static const tile = 14.0;
  static const cover = 12.0;
}

abstract final class KugoSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Live color tokens — follow [KugoThemeBinding.palette].
abstract final class KugoColors {
  static Color get bg => KugoThemeBinding.palette.bg;
  static Color get surface => KugoThemeBinding.palette.surface;
  static Color get surfaceElevated =>
      KugoThemeBinding.palette.surfaceElevated;
  static Color get primary => KugoThemeBinding.palette.primary;
  static Color get secondary => KugoThemeBinding.palette.secondary;
  static Color get textPrimary => KugoThemeBinding.palette.textPrimary;
  static Color get textSecondary => KugoThemeBinding.palette.textSecondary;
  static Color get textTertiary => KugoThemeBinding.palette.textTertiary;
  static Color get divider => KugoThemeBinding.palette.divider;
  static Color get overlay => KugoThemeBinding.palette.overlay;
  static LinearGradient get accentGradient =>
      KugoThemeBinding.palette.accentGradient;
  static LinearGradient get playerGradient =>
      KugoThemeBinding.palette.playerGradient;
}

/// Live text styles — colors follow the active palette.
abstract final class KugoTypography {
  static TextStyle get greeting => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: KugoColors.textPrimary,
        height: 1.2,
      );
  static TextStyle get title => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: KugoColors.textPrimary,
      );
  static TextStyle get section => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: KugoColors.textPrimary,
      );
  static TextStyle get body => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: KugoColors.textPrimary,
      );
  static TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: KugoColors.textSecondary,
      );
  static TextStyle get playerTitle => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: KugoColors.textPrimary,
      );
}
