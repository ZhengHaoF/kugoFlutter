import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 崩溃 / 未捕获错误日志 —— 把三类错误汇到同一份文件：
/// 1. 框架报错（`FlutterError.onError`，build/layout/paint 异常）；
/// 2. 原生派发的错误（`PlatformDispatcher.onError`，框架之外的异步错误）；
/// 3. zone 级未捕获错误（`runZonedGuarded` 的 onError，即 [onPlatformError]）。
///
/// 目的很朴素：真机 / 用户反馈时**有文件可看、可分享**。debug 下仍照旧打到
/// 控制台（[install] 会保留原 handler）。
class CrashLog {
  CrashLog._();

  /// 我们之前安装的 handler；debug 下继续往下抛，保持原有控制台行为。
  static FlutterExceptionHandler? _previousOnError;

  /// 建议在 `main()` 最前面调用，保证后续初始化里的报错也能落盘。
  static Future<void> install() async {
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _previousOnError?.call(details);
      unawaited(write('FlutterError', details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = onPlatformError;
  }

  /// zone 级未捕获错误（也可直接塞给 `PlatformDispatcher.onError`）。
  static bool onPlatformError(Object error, StackTrace stack) {
    unawaited(write('uncaught', error, stack));
    return true;
  }

  /// 单份日志上限。超限后从头重写——崩溃日志的价值在「最近一次」。
  static const _maxBytes = 512 * 1024;

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}${Platform.pathSeparator}crash.log');
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    String kind,
    Object error,
    StackTrace? stack,
  ) async {
    try {
      final file = await _file();
      if (file == null) return;
      final existing = await file.exists() ? await file.length() : 0;
      final overflow = existing > _maxBytes;
      await file.writeAsString(
        '===== ${DateTime.now().toIso8601String()} $kind =====\n'
        '$error\n${stack ?? ''}\n\n',
        mode: overflow ? FileMode.write : FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  /// 设置页摘要（null = 无日志）。
  static Future<String?> summary() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final count = _entryRe.allMatches(text).length;
      final last = _entryRe.allMatches(text).lastOrNull?.group(1);
      if (last == null || count == 0) return null;
      return '$count 条 · 最近 $last';
    } catch (_) {
      return null;
    }
  }

  static final _entryRe = RegExp(r'=====\s+(\S+)');

  /// 只返回尾部内容——弹窗不需要整段历史。
  static Future<String> readText() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return '';
      final text = await file.readAsString();
      return text.length <= 8000 ? text : text.substring(text.length - 8000);
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}
