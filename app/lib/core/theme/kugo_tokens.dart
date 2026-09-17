import 'package:flutter/material.dart';

/// Design tokens — aligned with docs/design mockups.
abstract final class KugoColors {
  static const bg = Color(0xFF0B0E14);
  static const surface = Color(0xFF151A24);
  static const surfaceElevated = Color(0xFF1C2230);
  static const primary = Color(0xFF5B7CFF);
  static const secondary = Color(0xFFA855F7);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9AA3B2);
  static const textTertiary = Color(0xFF5C6575);
  static const divider = Color(0x14FFFFFF);
  static const overlay = Color(0x66000000);

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const playerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1F3A), Color(0xFF2A1F4A), bg],
  );
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

abstract final class KugoTypography {
  static const greeting = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: KugoColors.textPrimary,
    height: 1.2,
  );
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: KugoColors.textPrimary,
  );
  static const section = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: KugoColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: KugoColors.textPrimary,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: KugoColors.textSecondary,
  );
  static const playerTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: KugoColors.textPrimary,
  );
}
