import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kugo_tokens.dart';

ThemeData buildKugoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: KugoColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: KugoColors.primary,
      secondary: KugoColors.secondary,
      surface: KugoColors.surface,
      onPrimary: KugoColors.textPrimary,
      onSecondary: KugoColors.textPrimary,
      onSurface: KugoColors.textPrimary,
    ),
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: KugoTypography.section,
      iconTheme: IconThemeData(color: KugoColors.textPrimary),
    ),
    dividerTheme: const DividerThemeData(
      color: KugoColors.divider,
      thickness: 0.5,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: KugoColors.textSecondary,
      textColor: KugoColors.textPrimary,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: KugoColors.bg,
      selectedItemColor: KugoColors.primary,
      unselectedItemColor: KugoColors.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: KugoColors.primary,
      inactiveTrackColor: KugoColors.textTertiary,
      thumbColor: KugoColors.textPrimary,
      overlayColor: KugoColors.primary.withValues(alpha: 0.2),
      trackHeight: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KugoColors.primary,
        foregroundColor: KugoColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KugoRadius.chip),
        ),
      ),
    ),
  );
}
