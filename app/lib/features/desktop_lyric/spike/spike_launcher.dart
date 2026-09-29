import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'spike_lyric_window.dart';

File get _logFile =>
    File(r'C:\Users\zheng\kugo_spike.log');

void _spikeLog(String msg) {
  try {
    _logFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $msg\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

/// Spike：主窗口侧启动器。
///
/// 负责：注册主窗通信 handler、创建（或复用）歌词测试窗口。
class SpikeLauncher {
  SpikeLauncher._();

  static const _channel = WindowMethodChannel(kSpikeChannelName);
  static bool _handlerReady = false;

  static Future<void> _ensureHandler() async {
    if (_handlerReady) return;
    await _channel.setMethodCallHandler((call) async {
      debugPrint('[spike] RECV ${call.method} ${call.arguments ?? ''}');
      switch (call.method) {
        case 'hello':
          return '主窗已收到';
        case 'ping':
          return 'pong@${DateTime.now().millisecondsSinceEpoch}';
        case 'mainHwnd':
          // 主窗 window_manager 已在 DesktopShell.boot 中 ensureInitialized。
          return await windowManager.getId();
        default:
          return null;
      }
    });
    _handlerReady = true;
  }

  /// 打开桌面歌词 spike 窗口（已存在则前置显示，不重复创建）。
  static Future<void> open() async {
    _spikeLog('open() called');
    try {
      await _ensureHandler();

      final all = await WindowController.getAll();
      _spikeLog('getAll count=${all.length}');
      for (final c in all) {
        _spikeLog('  win id=${c.windowId} args=${c.arguments}');
        if (c.arguments == kSpikeLyricWindowArg) {
          await c.show();
          _spikeLog('[spike] reuse existing window ${c.windowId}');
          return;
        }
      }

      final win = await WindowController.create(
        const WindowConfiguration(
          arguments: kSpikeLyricWindowArg,
          hiddenAtLaunch: true,
        ),
      );
      _spikeLog('[spike] created window ${win.windowId}');
    } catch (e, st) {
      _spikeLog('!! open() ERROR: $e\n$st');
    }
  }
}
