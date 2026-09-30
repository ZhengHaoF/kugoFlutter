import 'package:flutter/services.dart';

/// Android 悬浮歌词原生通道（`kugo/lyric_overlay`）。
///
/// 协议快照格式与 [DesktopLyricSnapshot.toWire] 一致；命令回调见
/// `LyricOverlayPlugin` 的 `command`。
abstract final class AndroidOverlayHost {
  static const _channel = MethodChannel('kugo/lyric_overlay');

  /// 原生 → Dart：`{'m': method, 'd': data?}`。
  static void setCommandHandler(
    void Function(String method, Map<String, Object?> data) handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return null;
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      final method = args?['m'] as String? ?? '';
      final data = (args?['d'] as Map?)?.cast<String, Object?>() ?? const {};
      handler(method, data);
      return null;
    });
  }

  static Future<bool> canDrawOverlays() async {
    final v = await _channel.invokeMethod<bool>('canDrawOverlays');
    return v ?? false;
  }

  static Future<void> openOverlaySettings() =>
      _channel.invokeMethod('openOverlaySettings');

  /// 显示悬浮窗。返回 false = 无权限。
  static Future<bool> show(Map<String, Object?> snapshot) async {
    final v = await _channel.invokeMethod<bool>('show', {'snapshot': snapshot});
    return v ?? false;
  }

  static Future<void> updateSnapshot(Map<String, Object?> snapshot) =>
      _channel.invokeMethod('updateSnapshot', {'snapshot': snapshot});

  static Future<void> hide() => _channel.invokeMethod('hide');

  static Future<Map<String, Object?>> resetPosition() async {
    final m = await _channel.invokeMethod<Map>('resetPosition');
    return m?.cast<String, Object?>() ?? const {};
  }

  static Future<void> applyBounds({required double x, required double y}) =>
      _channel.invokeMethod('applyBounds', {'x': x.round(), 'y': y.round()});

  static Future<Map<String, Object?>> getBounds() async {
    final m = await _channel.invokeMethod<Map>('getBounds');
    return m?.cast<String, Object?>() ?? const {};
  }

  static Future<bool> isShowing() async {
    final v = await _channel.invokeMethod<bool>('isShowing');
    return v ?? false;
  }
}
