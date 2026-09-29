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
      _channel.invokeMethod('setSize', {'width': width, 'height': height});

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

  static Future<void> startDragging() => _channel.invokeMethod('startDragging');

  static Future<void> show({bool inactive = true}) =>
      _channel.invokeMethod('show', {'inactive': inactive});

  static Future<void> destroy() => _channel.invokeMethod('destroy');

  static Future<void> setTransparentBg() =>
      _channel.invokeMethod('setTransparentBg');
}
