import 'package:shared_preferences/shared_preferences.dart';

/// 桌面歌词窗口位置/尺寸持久化（独立于 [AppSettings]，避免设置对象膨胀）。
class DesktopLyricBounds {
  const DesktopLyricBounds({
    this.x,
    this.y,
    this.width = 720,
    this.height = 88,
  });

  final double? x;
  final double? y;
  final double width;
  final double height;

  /// 有坐标才可恢复；首次启动走默认 topCenter。
  bool get hasPosition => x != null && y != null;

  Map<String, Object?> toWire() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static DesktopLyricBounds fromWire(Object? raw) {
    final m = (raw as Map?)?.cast<String, Object?>() ?? const {};
    final x = (m['x'] as num?)?.toDouble();
    final y = (m['y'] as num?)?.toDouble();
    return DesktopLyricBounds(
      x: x,
      y: y,
      width: ((m['width'] as num?)?.toDouble() ?? 720).clamp(320, 1600),
      height: ((m['height'] as num?)?.toDouble() ?? 88).clamp(60, 600),
    );
  }
}

/// 窗口 bounds 读写。主窗在歌词窗关闭/移动结束时写入。
class DesktopLyricBoundsStore {
  DesktopLyricBoundsStore._();

  static const _kX = 'desktopLyric.bounds.x';
  static const _kY = 'desktopLyric.bounds.y';
  static const _kW = 'desktopLyric.bounds.w';
  static const _kH = 'desktopLyric.bounds.h';

  static Future<DesktopLyricBounds> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_kX);
      final y = prefs.getDouble(_kY);
      return DesktopLyricBounds(
        x: (x != null && x.isFinite) ? x : null,
        y: (y != null && y.isFinite) ? y : null,
        width: (prefs.getDouble(_kW) ?? 720).clamp(320, 1600),
        height: (prefs.getDouble(_kH) ?? 88).clamp(60, 600),
      );
    } catch (_) {
      return const DesktopLyricBounds();
    }
  }

  static Future<void> save(DesktopLyricBounds b) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (b.x != null) await prefs.setDouble(_kX, b.x!);
      if (b.y != null) await prefs.setDouble(_kY, b.y!);
      await prefs.setDouble(_kW, b.width);
      await prefs.setDouble(_kH, b.height);
    } catch (_) {}
  }

  /// 清掉坐标，下次启动走「工作区顶部居中」默认位。
  static Future<void> clearPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kX);
      await prefs.remove(_kY);
    } catch (_) {}
  }
}
