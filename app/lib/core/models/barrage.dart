/// MV 弹幕的领域模型与纯逻辑（不依赖 Flutter 动画层）。
///
/// 对齐 EchoMusic `src/renderer/utils/barrage.ts` 与 `stores/setting.ts`
/// 的 `mvBarrageConfig`：轨道数 / 池上限 / 正文上限 / 飞行时长 / 密度间隔
/// 全部搬过来，保证两端手感一致。
library;

import 'dart:convert';

/// 弹幕池上限（对齐 EchoMusic `BARRAGE_LIMIT`）。超出截断。
const int kBarrageLimit = 100;

/// 弹幕正文上限（对齐 EchoMusic `BARRAGE_MAX_LENGTH`）。
const int kBarrageMaxLength = 100;

/// 同屏飞行的轨道数（对齐 EchoMusic `BARRAGE_LANES`）。
const int kBarrageLanes = 4;

/// 基准飞行速度 px/s（对齐 EchoMusic `BARRAGE_BASE_SPEED`）。
const double kBarrageBaseSpeed = 100;

/// 一条弹幕。
class BarrageItem {
  const BarrageItem({required this.text, this.userId = ''});

  final String text;
  final String userId;

  bool get isEmpty => text.trim().isEmpty;

  /// 身份：同用户同内容 → 同一个 key（用于「自己刚发的」回流去重）。
  String get identity => '$userId\u0000$text';
}

/// 归一化 user id：只保留正整数，匿名 / 非法返回空串。
///
/// 与 [normalizeMvCollectId] 同因：上游按 JS number 处理，保留字符串精度，
/// 且匿名（0 / 空）不参与「是否自己」的判断。
String normalizeBarrageUserId(Object? value) {
  if (value == null) return '';
  final id = '$value'.trim();
  return RegExp(r'^[1-9]\d*$').hasMatch(id) ? id : '';
}

/// 找一条空闲轨道；都占用返回 -1（对齐 EchoMusic `getFreeBarrageLane`）。
int firstFreeBarrageLane(Iterable<int> occupiedLanes) {
  final used = occupiedLanes.toSet();
  for (var lane = 0; lane < kBarrageLanes; lane++) {
    if (!used.contains(lane)) return lane;
  }
  return -1;
}

/// 飞行时长（毫秒）：`(容器宽 + 文本宽) / (基准速度 × 倍速)`。
///
/// [speed] 非法 / <=0 时按 1.0 处理（与 EchoMusic 一致）。
int barrageTravelMs({
  required double containerWidth,
  required double textWidth,
  required double speed,
}) {
  final multiplier = (speed.isFinite && speed > 0) ? speed : 1.0;
  final distance = (containerWidth < 0 ? 0 : containerWidth) +
      (textWidth < 0 ? 0 : textWidth);
  return (distance / (kBarrageBaseSpeed * multiplier) * 1000).round();
}

/// 密度（1 稀疏 / 2 适中 / 3 密集）→ 发射间隔（毫秒）。
int barrageIntervalMs(int density) => switch (density) {
      1 => 4500,
      3 => 1400,
      _ => 2800,
    };

/// 弹幕显示配置（对齐 EchoMusic `mvBarrageConfig`）。
class BarrageConfig {
  const BarrageConfig({
    this.opacity = 100,
    this.fontSize = 17,
    this.speed = 1,
    this.area = 25,
    this.density = 2,
  });

  static const BarrageConfig defaults = BarrageConfig();

  /// 不透明度百分比（20–100）。
  final int opacity;

  /// 字号 px（12–28）。
  final double fontSize;

  /// 速度倍率（0.5–2）。
  final double speed;

  /// 显示区域：占画面高度的百分比（25 顶部 / 50 上半屏 / 100 全屏）。
  final int area;

  /// 密度 1–3。
  final int density;

  BarrageConfig copyWith({
    int? opacity,
    double? fontSize,
    double? speed,
    int? area,
    int? density,
  }) {
    return BarrageConfig(
      opacity: opacity ?? this.opacity,
      fontSize: fontSize ?? this.fontSize,
      speed: speed ?? this.speed,
      area: area ?? this.area,
      density: density ?? this.density,
    );
  }

  /// 归一化到合法区间（读盘 / setter 共用）。
  BarrageConfig normalized() => BarrageConfig(
        opacity: opacity.clamp(20, 100),
        fontSize: fontSize.clamp(12, 28),
        speed: speed.clamp(0.5, 2),
        area: (area == 25 || area == 50 || area == 100) ? area : 25,
        density: density.clamp(1, 3),
      );

  Map<String, Object?> toJson() => {
        'opacity': opacity,
        'fontSize': fontSize,
        'speed': speed,
        'area': area,
        'density': density,
      };

  static BarrageConfig fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    double numOf(Object? value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallback;
    }

    return BarrageConfig(
      opacity: numOf(raw['opacity'], 100).round(),
      fontSize: numOf(raw['fontSize'], 17),
      speed: numOf(raw['speed'], 1),
      area: numOf(raw['area'], 25).round(),
      density: numOf(raw['density'], 2).round(),
    ).normalized();
  }

  /// 落盘字符串。
  String encode() => jsonEncode(toJson());

  /// 读盘；脏数据 / 缺省一律回落默认。
  static BarrageConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return defaults;
    }
  }
}