import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import 'kugo_tokens.dart';

/// UI font family for the current platform.
///
/// Windows ships 微软雅黑; other platforms keep Flutter/Material defaults so
/// Android is not forced into a missing family name.
String? get kugoFontFamily {
  if (kIsWeb) return null;
  if (Platform.isWindows) return 'Microsoft YaHei';
  return null;
}

/// Latin-first fallbacks when a glyph is missing from [kugoFontFamily].
List<String>? get kugoFontFamilyFallback =>
    kugoFontFamily == null ? null : const ['Segoe UI', 'Microsoft YaHei UI'];

/// ThemeExtension — idiomatic `KugoTheme.of(context)` access.
///
/// Every color/style read goes through here (never a global) so widgets
/// rebuild automatically when the theme flips. `Theme.of(context)` registers
/// the dependency for us, which is why `const` widgets stay correct.
class KugoTheme extends ThemeExtension<KugoTheme> {
  const KugoTheme(this.palette);

  final KugoPalette palette;

  bool get isLight => palette.isLight;
  Color get bg => palette.bg;
  Color get surface => palette.surface;
  Color get surfaceElevated => palette.surfaceElevated;
  Color get primary => palette.primary;
  Color get secondary => palette.secondary;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get textTertiary => palette.textTertiary;
  Color get divider => palette.divider;
  Color get overlay => palette.overlay;
  LinearGradient get accentGradient => palette.accentGradient;
  LinearGradient get playerGradient => palette.playerGradient;

  /// Text drawn on top of [accentGradient] / cover art stays light in both
  /// themes.
  Color get onAccent => Colors.white;
  Color get onCover => Colors.white;
  Color get onCoverMuted => Colors.white70;

  TextStyle get greeting => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.2,
      );
  TextStyle get title => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );
  TextStyle get section => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );
  TextStyle get body => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: textPrimary,
      );
  TextStyle get caption => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );
  TextStyle get playerTitle => TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );

  static KugoTheme of(BuildContext context) =>
      Theme.of(context).extension<KugoTheme>() ?? fallback;

  /// Used by widget tests / previews that build without [buildKugoTheme].
  static const fallback = KugoTheme(KugoPalette.dark);

  @override
  KugoTheme copyWith({KugoPalette? palette}) =>
      KugoTheme(palette ?? this.palette);

  @override
  KugoTheme lerp(ThemeExtension<KugoTheme>? other, double t) {
    if (other is! KugoTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// Elegant, unscaled desktop fade-through + light horizontal drift.
///
/// Unlike [ZoomPageTransitionsBuilder], this does not scale the entering or
/// exiting route and does not snapshot raster images, so [Hero] overlay
/// coordinates and destination geometries land with zero subpixel flicker.
///
/// Rhythm (Material fade-through):
/// - covered route fades out early via [secondaryAnimation]
/// - entering route waits briefly, then fades in
/// - push drifts +16 → 0 (enter) and 0 → -8 (cover); pop mirrors
///
/// [ClipRect] keeps nested-navigator drift from painting over the desktop
/// sidebar. Settled frames paint [child] raw (no opacity/transform layer).
class DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const DesktopPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double>? secondaryAnimation,
    Widget child,
  ) {
    return _DesktopFadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation ?? kAlwaysDismissedAnimation,
      child: child,
    );
  }
}

class _DesktopFadeThroughTransition extends StatelessWidget {
  const _DesktopFadeThroughTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Enter late (0.22–1.0), leave early on pop (0.0–0.62).
    final selfOpacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 0.62, curve: Curves.easeInCubic),
    );

    // 1 = fully visible, 0 = fully hidden while covered.
    // Cover: fade out in the first ~half so pages never sit double-opaque.
    // Reveal: restore almost immediately so pop uncovers cleanly.
    final coverOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0.0, 0.48, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.82, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    // Push enter +16 → 0; pop exits back to +16 via the same tween.
    final enterDx = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.0, 0.7, curve: Curves.easeInCubic),
      ),
    );
    // Covered route nudges left; reveal returns to 0.
    final coverDx = Tween<double>(begin: 0.0, end: -8.0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
        reverseCurve: const Interval(0.7, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) {
        final opacity = (selfOpacity.value * coverOpacity.value).clamp(0.0, 1.0);
        final dx = enterDx.value + coverDx.value;
        // Settled: paint raw child — zero transform/opacity (Hero + pixel grid).
        if (opacity >= 1.0 && dx == 0.0) return child!;
        return ClipRect(
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
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
    fontFamily: kugoFontFamily,
    fontFamilyFallback: kugoFontFamilyFallback,
    scaffoldBackgroundColor: p.bg,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: DesktopPageTransitionsBuilder(),
        TargetPlatform.windows: DesktopPageTransitionsBuilder(),
        TargetPlatform.linux: DesktopPageTransitionsBuilder(),
      },
    ),
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
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surfaceElevated,
      surfaceContainerLow: p.surface,
      surfaceContainerLowest: p.surface,
      outlineVariant: p.divider,
      inverseSurface: isLight ? const Color(0xFF23262E) : p.textPrimary,
      onInverseSurface: isLight ? Colors.white : p.bg,
      scrim: Colors.black,
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
      titleTextStyle: TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
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
    dialogTheme: DialogThemeData(
      backgroundColor: p.surfaceElevated,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceElevated,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surfaceElevated,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isLight ? const Color(0xFF23262E) : p.surfaceElevated,
      contentTextStyle: TextStyle(
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
        color: Colors.white,
        fontSize: 14,
      ),
      actionTextColor: p.primary,
      behavior: SnackBarBehavior.floating,
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
  // 桌面端没有状态栏 / 系统导航栏，SystemChrome 在 Windows 上无实现。
  if (isDesktopPlatform) return;
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
