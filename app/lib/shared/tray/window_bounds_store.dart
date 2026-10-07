import 'package:shared_preferences/shared_preferences.dart';

/// 主窗尺寸 / 位置持久化。
///
/// window_manager 在 Windows 上**不会**自己记住窗口（`desktop_shell` 里
/// 「保留用户上次调过的窗口尺寸」只是注释里的假设），所以自己存一份，
/// 做法与桌面歌词子窗的 [DesktopLyricBoundsStore] 一致。
class DesktopWindowBoundsStore {
  DesktopWindowBoundsStore._();

  static const _kX = 'window.bounds.x';
  static const _kY = 'window.bounds.y';
  static const _kW = 'window.bounds.w';
  static const _kH = 'window.bounds.h';
  static const _kMaximized = 'window.bounds.maximized';

  static Future<DesktopWindowBounds> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_kX);
      final y = prefs.getDouble(_kY);
      return DesktopWindowBounds(
        x: x,
        y: y,
        width: prefs.getDouble(_kW) ?? 1200,
        height: prefs.getDouble(_kH) ?? 820,
        maximized: prefs.getBool(_kMaximized) ?? false,
      );
    } catch (_) {
      return const DesktopWindowBounds();
    }
  }

  static Future<void> save(DesktopWindowBounds b) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (b.x != null) await prefs.setDouble(_kX, b.x!);
      if (b.y != null) await prefs.setDouble(_kY, b.y!);
      await prefs.setDouble(_kW, b.width);
      await prefs.setDouble(_kH, b.height);
      await prefs.setBool(_kMaximized, b.maximized);
    } catch (_) {}
  }

  /// 只清坐标，尺寸与最大化标记保留。
  static Future<void> clearPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kX);
      await prefs.remove(_kY);
    } catch (_) {}
  }
}

/// 主窗 bounds。物理像素（`window_manager.getBounds()` 的口径）。
class DesktopWindowBounds {
  const DesktopWindowBounds({
    this.x,
    this.y,
    this.width = 1200,
    this.height = 820,
    this.maximized = false,
  });

  final double? x;
  final double? y;
  final double width;
  final double height;

  /// 关闭时处于最大化：恢复时只需 maximize，bounds 用上一次的非最大化值。
  final bool maximized;

  bool get hasPosition => x != null && y != null;
}
