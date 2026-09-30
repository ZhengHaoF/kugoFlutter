import 'package:flutter/services.dart';

/// 桌面歌词窗口原生操作（`kugo/desktop_lyric_host`）。
///
/// 每个 Flutter 引擎（主窗 / 歌词子窗）各自绑定自己的 HWND，
/// **不要用 window_manager**：多引擎下它会串窗导致主窗假死。
class DesktopLyricHost {
  DesktopLyricHost._();

  static const _channel = MethodChannel('kugo/desktop_lyric_host');

  static Future<int> getHwnd() async {
    final v = await _channel.invokeMethod<int>('getHwnd');
    return v ?? 0;
  }

  static Future<void> setFrameless() => _channel.invokeMethod('setFrameless');

  static Future<void> setSize(double width, double height) =>
      _channel.invokeMethod('setSize', {
        'width': width.round(),
        'height': height.round(),
      });

  static Future<void> centerTop({
    double width = 720,
    double height = 88,
    double top = 56,
  }) =>
      _channel.invokeMethod('centerTop', {
        'width': width.round(),
        'height': height.round(),
        'top': top.round(),
      });

  static Future<void> setPosition(double x, double y) =>
      _channel.invokeMethod('setPosition', {'x': x, 'y': y});

  static Future<({double x, double y, double width, double height})>
      getPosition() async {
    final m = await _channel.invokeMethod<Map>('getPosition');
    return (
      x: (m?['x'] as num?)?.toDouble() ?? 0,
      y: (m?['y'] as num?)?.toDouble() ?? 0,
      width: (m?['width'] as num?)?.toDouble() ?? 0,
      height: (m?['height'] as num?)?.toDouble() ?? 0,
    );
  }

  static Future<void> setAlwaysOnTop(bool on) =>
      _channel.invokeMethod('setAlwaysOnTop', {'on': on});

  static Future<void> setSkipTaskbar(bool skip) =>
      _channel.invokeMethod('setSkipTaskbar', {'skip': skip});

  static Future<void> setIgnoreMouseEvents(bool ignore) =>
      _channel.invokeMethod('setIgnoreMouseEvents', {'ignore': ignore});

  /// 设置可点击热区（逻辑像素，Flutter 坐标）；热区外 WM_NCHITTEST 穿透。
  ///
  /// [passthrough] 为 true 时非热区不收鼠标（歌词窗默认）；
  /// 为 false 时整窗收鼠标（调试）。
  static Future<void> setHitRegions(
    List<({double x, double y, double width, double height})> regions, {
    bool passthrough = true,
  }) {
    return _channel.invokeMethod('setHitRegions', {
      'passthrough': passthrough,
      'regions': [
        for (final r in regions)
          {'x': r.x, 'y': r.y, 'width': r.width, 'height': r.height},
      ],
    });
  }

  static Future<void> startDragging() => _channel.invokeMethod('startDragging');

  static Future<void> show({bool inactive = true}) =>
      _channel.invokeMethod('show', {'inactive': inactive});

  static Future<void> hide() => _channel.invokeMethod('hide');

  static Future<void> destroy() => _channel.invokeMethod('destroy');

  static Future<void> setTransparentBg() =>
      _channel.invokeMethod('setTransparentBg');

  /// 光标屏幕逻辑坐标（用于 hover 穿透时判断是否还在热区内）。
  static Future<({double x, double y})> getCursorPos() async {
    final m = await _channel.invokeMethod<Map>('getCursorPos');
    return (
      x: (m?['x'] as num?)?.toDouble() ?? 0,
      y: (m?['y'] as num?)?.toDouble() ?? 0,
    );
  }
}
