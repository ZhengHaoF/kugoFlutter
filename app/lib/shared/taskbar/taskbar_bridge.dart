import 'package:flutter/services.dart';

/// Windows 任务栏集成：Thumbar 播控钮 + 进度条。
///
/// 对端是 `windows/runner/taskbar_host.cpp`（ITaskbarList3）。仅 Windows 有意义；
/// 其他平台调用会 no-op（MethodChannel 无实现）。
class TaskbarBridge {
  static const MethodChannel _channel = MethodChannel('kugo/taskbar');

  static bool _listening = false;

  /// Thumbar 按钮点击：previous / playPause / next / favorite。
  static void Function(String command)? onThumbarCommand;
  static void Function(Map<Object?, Object?> event)? onMediaEvent;

  static void ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'thumbarEvent') {
        final name = call.arguments;
        if (name is String) onThumbarCommand?.call(name);
      }
      if (call.method == 'mediaEvent' && call.arguments is Map) {
        onMediaEvent?.call(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
  }

  static Future<void> updateButtons({
    required bool hasTrack,
    required bool isPlaying,
    bool isFavorite = false,
    bool canStepBack = true,
  }) {
    return _channel.invokeMethod('updateButtons', {
      'hasTrack': hasTrack,
      'isPlaying': isPlaying,
      'isFavorite': isFavorite,
      'canStepBack': canStepBack,
    });
  }

  /// [mode]: none | normal | paused | indeterminate（对齐 Echo taskbarProgress）。
  static Future<void> updateProgress({
    required String mode,
    required int positionMs,
    required int durationMs,
  }) {
    return _channel.invokeMethod('updateProgress', {
      'mode': mode,
      'positionMs': positionMs,
      'durationMs': durationMs,
    });
  }

  /// 窗口 show/restore 后重放按钮与进度（只 Update，不重新 Add）。
  static Future<void> refresh() => _channel.invokeMethod('refresh');

  static Future<void> configureMedia({
    required bool preview,
    required bool bar,
    int? x,
    int? y,
  }) => _channel.invokeMethod('configureMedia', {
    'preview': preview,
    'bar': bar,
    'x': ?x,
    'y': ?y,
  });

  static Future<void> mediaState(Map<String, Object?> state) =>
      _channel.invokeMethod('mediaState', state);

  static Future<void> mediaArtwork({
    required String trackKey,
    required int revision,
    required int width,
    required int height,
    required Uint8List rgba,
  }) => _channel.invokeMethod('mediaArtwork', {
    'trackKey': trackKey,
    'revision': revision,
    'width': width,
    'height': height,
    'rgba': rgba,
  });
}

/// 任务栏进度模式。与 `TaskbarHost::ProgressMode` 一一对应。
enum TaskbarProgressMode { none, normal, paused, indeterminate }

extension TaskbarProgressModeWire on TaskbarProgressMode {
  String get wireName => switch (this) {
    TaskbarProgressMode.none => 'none',
    TaskbarProgressMode.normal => 'normal',
    TaskbarProgressMode.paused => 'paused',
    TaskbarProgressMode.indeterminate => 'indeterminate',
  };
}

/// 由播放快照推导进度模式（Echo `resolveMode`）。
TaskbarProgressMode taskbarModeFor({
  required bool hasTrack,
  required bool isPlaying,
  required int durationMs,
}) {
  if (!hasTrack) return TaskbarProgressMode.none;
  if (durationMs <= 0) return TaskbarProgressMode.indeterminate;
  return isPlaying ? TaskbarProgressMode.normal : TaskbarProgressMode.paused;
}
