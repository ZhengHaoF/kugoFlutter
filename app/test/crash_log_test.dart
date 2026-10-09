import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/diagnostics/crash_log.dart';

import 'fakes/fake_path_provider.dart';

/// 崩溃日志：三类错误汇到同一份文件，超限后从头重写。
///
/// 这条链路在 f7fec6f 引入（崩溃捕获），此前零测试。这里用假
/// PathProviderPlatform 把落盘指到临时目录，从而覆盖**真实文件逻辑**：
/// 追加 / 512KB 上限重写 / 摘要计数 / 尾部截断。
void main() {
  late Directory tmp;
  late File logFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kugo_crashlog_test');
    installFakePathProvider(tmp);
    logFile = File('${tmp.path}${Platform.pathSeparator}crash.log');
  });

  tearDown(() {
    // Windows 上异步 write 可能还没释放句柄；删不掉不影响用例结果。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('onPlatformError', () {
    test('吞掉异常并返回 true（阻止继续往上抛）', () {
      expect(CrashLog.onPlatformError(StateError('boom'), StackTrace.current),
          isTrue);
    });
  });

  group('write / summary', () {
    test('空日志时 summary 为 null', () async {
      expect(await CrashLog.summary(), isNull);
    });

    test('写一条后 summary 报条数与时间戳', () async {
      await CrashLog.write('uncaught', StateError('boom'), StackTrace.current);
      final s = await CrashLog.summary();
      expect(s, isNotNull);
      expect(s, contains('1 条'));
    });

    test('多条累加计数', () async {
      for (var i = 0; i < 3; i++) {
        await CrashLog.write('uncaught', StateError('e$i'), null);
      }
      final s = await CrashLog.summary();
      expect(s, contains('3 条'));
    });

    test('写进去的内容包含 kind 与错误串', () async {
      await CrashLog.write('FlutterError', StateError('layout exploded'), null);
      final text = await logFile.readAsString();
      expect(text, contains('FlutterError'));
      expect(text, contains('layout exploded'));
    });

    test('空白文件（只有换行）summary 仍为 null', () async {
      await logFile.writeAsString('   \n\n');
      expect(await CrashLog.summary(), isNull);
    });
  });

  group('readText', () {
    test('无文件时返回空串', () async {
      expect(await CrashLog.readText(), '');
    });

    test('短文件原样返回', () async {
      await CrashLog.write('uncaught', StateError('x'), null);
      final text = await CrashLog.readText();
      expect(text, isNotEmpty);
      expect(text.length, lessThanOrEqualTo(8000));
    });

    test('超长只返回尾部 8000 字符', () async {
      // 写一条远超 8000 的（error 串里塞 20000 个字符）。
      await CrashLog.write('uncaught', StateError('x' * 20000), null);
      final text = await CrashLog.readText();
      expect(text.length, 8000);
    });
  });

  group('512KB 上限', () {
    test('超限后从头重写，不再无限追加', () async {
      // 第一条就超过 512KB。
      await CrashLog.write('uncaught', StateError('y' * (600 * 1024)), null);
      expect(await logFile.length(), greaterThan(512 * 1024));

      await CrashLog.write('uncaught', StateError('second'), null);

      // 第二条触发 overflow → write 模式（截断），文件只剩第二条。
      final text = await logFile.readAsString();
      expect(text.contains('second'), isTrue);
      expect(text.length, lessThan(512 * 1024));
      final s = await CrashLog.summary();
      expect(s, contains('1 条'));
    });

    test('未超限时是追加，不丢历史', () async {
      await CrashLog.write('uncaught', StateError('first'), null);
      final after1 = await logFile.length();
      await CrashLog.write('uncaught', StateError('second'), null);
      final after2 = await logFile.length();
      expect(after2, greaterThan(after1));

      final text = await logFile.readAsString();
      expect(text.contains('first'), isTrue);
      expect(text.contains('second'), isTrue);
    });
  });

  group('clear', () {
    test('删除日志文件', () async {
      await CrashLog.write('uncaught', StateError('x'), null);
      expect(await logFile.exists(), isTrue);

      await CrashLog.clear();
      expect(await logFile.exists(), isFalse);
      expect(await CrashLog.summary(), isNull);
    });

    test('文件不存在时 clear 不抛', () async {
      await CrashLog.clear();
    });
  });

  group('install', () {
    test('装上后 FlutterError.onError 被替换，原 handler 仍被调用', () async {
      var previousCalled = false;
      FlutterError.onError = (details) {
        previousCalled = true;
      };
      addTearDown(() => FlutterError.onError = FlutterError.dumpErrorToConsole);

      await CrashLog.install();

      final installed = FlutterError.onError;
      expect(installed, isNotNull);
      // 替换后的 handler 先把 details 透传给原 handler（debug 下控制台行为不变）。
      installed!(FlutterErrorDetails(exception: StateError('from onError')));
      expect(previousCalled, isTrue);

      // zone 级错误也接到同一个落盘函数上。
      expect(PlatformDispatcher.instance.onError, CrashLog.onPlatformError);
      // 落盘本身由上面 write / summary / readText 那几组覆盖；这里不重复断言
      // 文件内容——install 里的 write 是 unawaited 的，等它要靠真实延时，
      // 并行跑全量测试时会把这条变成偶发失败。
    });
  });
}
