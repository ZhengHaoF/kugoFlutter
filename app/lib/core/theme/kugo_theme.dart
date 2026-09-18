import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kugo_tokens.dart';

/// ThemeExtension (Plan A) — idiomatic `KugoTheme.of(context)` access.
class KugoTheme extends ThemeExtension<KugoTheme> {
  const KugoTheme(this.palette);

  final KugoPalette palette;

  Color get bg => palette.bg;
  Color get surface => palette.surface;
  Color get surfaceElevated => palette.surfaceElevated;
  Color get primary => palette.primary;
  Color get secondary => palette.secondary;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textTertiary => palette.textTertiary;
  Color get divider => palette.divider;
  LinearGradient get accentGradient => palette.accentGradient;
  LinearGradient get playerGradient => palette.playerGradient;

  TextStyle get greeting => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.2,
      );
  TextStyle get title => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );
  TextStyle get section => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );
  TextStyle get body => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      );
  TextStyle get caption => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );
  TextStyle get playerTitle => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static KugoTheme of(BuildContext context) =>
      Theme.of(context).extension<KugoTheme>() ??
      KugoTheme(KugoThemeBinding.palette);

  @override
  KugoTheme copyWith({KugoPalette? palette}) =>
      KugoTheme(palette ?? this.palette);

  @override
  KugoTheme lerp(ThemeExtension<KugoTheme>? other, double t) {
    if (other is! KugoTheme) return this;
    return t < 0.5 ? this : other;
  }
}

KugoPalette kugoPaletteFor(Brightness brightness) =>
    brightness == Brightness.light ? KugoPalette.light : KugoPalette.dark;

ThemeData buildKugoTheme(Brightness brightness) {
  final p = kugoPaletteFor(brightness);
  final isLight = brightness == Brightness.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: Colors.white,
      secondary: p.secondary,
      onSecondary: Colors.white,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: const Color(0xFFE5484D),
      onError: Colors.white,
      onSurfaceVariant: p.textSecondary,
      outline: p.textTertiary,
    ),
    extensions: [KugoTheme(p)],
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle:
          isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      titleTextStyle: p.isLight
          ? TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            )
          : const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
      iconTheme: IconThemeData(color: p.textPrimary),
    ),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 0.5),
    listTileTheme: ListTileThemeData(
      iconColor: p.textSecondary,
      textColor: p.textPrimary,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.bg,
      selectedItemColor: p.primary,
      unselectedItemColor: p.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.textTertiary,
      thumbColor: p.textPrimary,
      overlayColor: p.primary.withValues(alpha: 0.2),
      trackHeight: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KugoRadius.chip),
        ),
      ),
    ),
  );
}

void applyKugoSystemUi(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final p = kugoPaletteFor(brightness);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: p.bg,
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
    ),
  );
}
