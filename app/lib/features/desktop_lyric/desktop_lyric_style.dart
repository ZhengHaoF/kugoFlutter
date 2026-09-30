import 'package:flutter/material.dart';

/// 桌面歌词外观配置。
///
/// 全部视觉参数集中在这一处：主窗持久化、经 snapshot 推给歌词子窗、
/// 渲染层（`lyric_window_view.dart` / `karaoke_sweep_line.dart`）按它绘制。
/// 任何字段变化都会触发整窗重建——样式改动是低频用户操作，不需要做
/// 帧级优化（与扫光动画的 Ticker 路径互不干扰）。
@immutable
class DesktopLyricStyle {
  const DesktopLyricStyle({
    this.sungColor = 0xFF2CE06B,
    this.unsungColor = 0xFFFFFFFF,
    this.shadowColor = 0xFF000000,
    this.shadowStrength = 1.0,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 0.0,
    this.bgColor = 0xFF000000,
    this.bgOpacity = 0.0,
    this.bgRadius = 14.0,
    this.fontScale = 1.0,
    this.fontWeight = 1.0,
  });

  /// 已唱（扫光已过）部分颜色。默认酷狗系强调绿。
  final int sungColor;

  /// 未唱部分颜色。默认纯白（桌面歌词主流：浅色壁纸靠阴影/描边保证可读）。
  final int unsungColor;

  /// 文字阴影颜色（默认黑）。
  final int shadowColor;

  /// 阴影强度（0 = 无阴影，1 = 默认两层阴影，> 1 更重）。
  final double shadowStrength;

  /// 描边颜色。仅当 [strokeWidth] > 0 时生效。
  final int strokeColor;

  /// 描边宽度（逻辑像素）。0 = 不描边；桌面歌词在浅色壁纸上的可读性兜底。
  final double strokeWidth;

  /// 歌词块背景色（[bgOpacity] > 0 时绘制圆角底）。
  final int bgColor;

  /// 背景不透明度（0 = 完全透明悬浮，1 = 实心底）。默认 0 对齐 P1 的透明形态。
  final double bgOpacity;

  /// 背景圆角半径。
  final double bgRadius;

  /// 字号系数：1.0 = 基准 24px。桌面歌词独立于播放页 lyricFontScale。
  final double fontScale;

  /// 字重系数：1.0 = W700，映射到 W400..W900 区间。
  final double fontWeight;

  Color get sung => Color(sungColor);
  Color get unsung => Color(unsungColor);
  Color get stroke => Color(strokeColor);
  Color get bg => Color(bgColor);

  bool get hasBackground => bgOpacity > 0.004;
  bool get hasShadow => shadowStrength > 0.004;
  bool get hasStroke => strokeWidth > 0.004;

  /// 阴影层数与 [lyric_window_view] 的 `_buildShadows` 一致，这里只给权重。
  List<Shadow> shadowsOf({double strength = 1}) {
    if (!hasShadow) return const [];
    final s = (shadowStrength * strength).clamp(0.0, 3.0);
    final base = Color(shadowColor);
    return [
      Shadow(
        color: base.withValues(alpha: (0.85 * s).clamp(0.0, 1.0)),
        blurRadius: 10 * s,
        offset: const Offset(0, 2),
      ),
      Shadow(
        color: base.withValues(alpha: (0.55 * s).clamp(0.0, 1.0)),
        blurRadius: 3 * s,
        offset: const Offset(0, 1),
      ),
    ];
  }

  FontWeight resolveFontWeight() {
    // 1.0 → 700；线性映射到 400..900 并收敛到 Material 档位。
    final w = (400 + (fontWeight.clamp(0.0, 2.0) - 0.0) * 250)
        .clamp(400.0, 900.0);
    const steps = [400.0, 500.0, 600.0, 700.0, 800.0, 900.0];
    var best = steps.first;
    for (final s in steps) {
      if ((s - w).abs() < (best - w).abs()) best = s;
    }
    return FontWeight.values[steps.indexOf(best)];
  }

  /// 与当前外观完全等价的预设；无匹配时返回 null（自定义）。
  DesktopLyricPreset? get matchingPreset {
    for (final p in kDesktopLyricPresets) {
      if (p.style == this) return p;
    }
    return null;
  }

  Map<String, Object?> toWire() => {
        'sungColor': sungColor,
        'unsungColor': unsungColor,
        'shadowColor': shadowColor,
        'shadowStrength': shadowStrength,
        'strokeColor': strokeColor,
        'strokeWidth': strokeWidth,
        'bgColor': bgColor,
        'bgOpacity': bgOpacity,
        'bgRadius': bgRadius,
        'fontScale': fontScale,
        'fontWeight': fontWeight,
      };

  static DesktopLyricStyle fromWire(Object? raw) {
    final m = (raw as Map?)?.cast<String, Object?>() ?? const {};
    return DesktopLyricStyle(
      sungColor: _readColor(m['sungColor'], 0xFF2CE06B),
      unsungColor: _readColor(m['unsungColor'], 0xFFFFFFFF),
      shadowColor: _readColor(m['shadowColor'], 0xFF000000),
      shadowStrength: clampDouble(m['shadowStrength'], 0, 3, 1),
      strokeColor: _readColor(m['strokeColor'], 0xFF000000),
      strokeWidth: clampDouble(m['strokeWidth'], 0, 6, 0),
      bgColor: _readColor(m['bgColor'], 0xFF000000),
      bgOpacity: clampDouble(m['bgOpacity'], 0, 1, 0),
      bgRadius: clampDouble(m['bgRadius'], 0, 40, 14),
      fontScale: clampDouble(m['fontScale'], 0.6, 2.0, 1),
      fontWeight: clampDouble(m['fontWeight'], 0, 2, 1),
    );
  }

  /// 颜色字段安全读取：脏数据（字符串 / null / 非 num）一律回 [fallback]。
  static int _readColor(Object? v, int fallback) {
    if (v is num) return v.toInt();
    return fallback;
  }

  static double clampDouble(Object? v, double min, double max, double fallback) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (n == null || n < min || n > max) return fallback;
    return n;
  }

  DesktopLyricStyle copyWith({
    int? sungColor,
    int? unsungColor,
    int? shadowColor,
    double? shadowStrength,
    int? strokeColor,
    double? strokeWidth,
    int? bgColor,
    double? bgOpacity,
    double? bgRadius,
    double? fontScale,
    double? fontWeight,
  }) {
    return DesktopLyricStyle(
      sungColor: sungColor ?? this.sungColor,
      unsungColor: unsungColor ?? this.unsungColor,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowStrength: shadowStrength ?? this.shadowStrength,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      bgColor: bgColor ?? this.bgColor,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      bgRadius: bgRadius ?? this.bgRadius,
      fontScale: fontScale ?? this.fontScale,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopLyricStyle &&
          runtimeType == other.runtimeType &&
          sungColor == other.sungColor &&
          unsungColor == other.unsungColor &&
          shadowColor == other.shadowColor &&
          shadowStrength == other.shadowStrength &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth &&
          bgColor == other.bgColor &&
          bgOpacity == other.bgOpacity &&
          bgRadius == other.bgRadius &&
          fontScale == other.fontScale &&
          fontWeight == other.fontWeight;

  @override
  int get hashCode => Object.hash(
        sungColor,
        unsungColor,
        shadowColor,
        shadowStrength,
        strokeColor,
        strokeWidth,
        bgColor,
        bgOpacity,
        bgRadius,
        fontScale,
        fontWeight,
      );
}

/// 一套开箱即用的外观。预设值刻意覆盖几种典型形态：透明悬浮、实底、
/// 描边可读、暖色调，用户改完任一字段即变为「自定义」。
class DesktopLyricPreset {
  const DesktopLyricPreset._({
    required this.name,
    required this.style,
  });

  final String name;
  final DesktopLyricStyle style;

  static const _default = DesktopLyricStyle();

  /// 经典悬浮：白字 + 绿扫光 + 重阴影，无背景（P1 形态）。
  static const classic = DesktopLyricPreset._(
    name: '经典悬浮',
    style: _default,
  );

  static const kugou = DesktopLyricPreset._(
    name: '酷狗绿',
    style: DesktopLyricStyle(
      sungColor: 0xFF2CE06B,
      unsungColor: 0xFFFFFFFF,
      shadowStrength: 1.2,
      strokeWidth: 1.2,
    ),
  );

  static const netease = DesktopLyricPreset._(
    name: '网易云红',
    style: DesktopLyricStyle(
      sungColor: 0xFFE60026,
      unsungColor: 0xFFF2F2F2,
      shadowStrength: 1.1,
      strokeWidth: 1.0,
    ),
  );

  static const sunset = DesktopLyricPreset._(
    name: '日落橘',
    style: DesktopLyricStyle(
      sungColor: 0xFFFFB300,
      unsungColor: 0xFFFFF3E0,
      shadowColor: 0xFF4A1500,
      shadowStrength: 1.3,
      strokeWidth: 1.4,
    ),
  );

  static const neon = DesktopLyricPreset._(
    name: '赛博紫',
    style: DesktopLyricStyle(
      sungColor: 0xFF00E5FF,
      unsungColor: 0xFFE1BEE7,
      shadowColor: 0xFF1A0033,
      shadowStrength: 1.6,
      strokeWidth: 1.2,
    ),
  );

  static const darkCard = DesktopLyricPreset._(
    name: '深色卡片',
    style: DesktopLyricStyle(
      sungColor: 0xFF2CE06B,
      unsungColor: 0xFFFFFFFF,
      bgColor: 0xFF101418,
      bgOpacity: 0.62,
      bgRadius: 18,
      shadowStrength: 0.7,
      strokeWidth: 0.8,
    ),
  );

  static const ink = DesktopLyricPreset._(
    name: '水墨黑',
    style: DesktopLyricStyle(
      sungColor: 0xFFFFFFFF,
      unsungColor: 0xFFBDBDBD,
      shadowStrength: 0.9,
      strokeWidth: 1.6,
      strokeColor: 0xFFFFFFFF,
    ),
  );
}

const List<DesktopLyricPreset> kDesktopLyricPresets = [
  DesktopLyricPreset.classic,
  DesktopLyricPreset.kugou,
  DesktopLyricPreset.netease,
  DesktopLyricPreset.sunset,
  DesktopLyricPreset.neon,
  DesktopLyricPreset.darkCard,
  DesktopLyricPreset.ink,
];
