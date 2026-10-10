import 'dart:async';

import 'package:flutter/material.dart';

/// The shell is drawn before any service waits. Timed-out work is not treated
/// as cancelled: retry is enabled only after it actually settles, avoiding
/// overlapping player/container/native service initializations.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.onError,
    this.timeout = const Duration(seconds: 30),
  });

  final Future<Widget> Function() initialize;
  final void Function(Object, StackTrace) onError;
  final Duration timeout;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  Widget? _app;
  bool _running = false;
  bool _timedOut = false;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _timedOut = false;
      _error = null;
    });
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (mounted && _running) setState(() => _timedOut = true);
    });
    try {
      final app = await widget.initialize();
      if (mounted) setState(() => _app = app);
    } catch (error, stack) {
      widget.onError(error, stack);
      if (mounted) setState(() => _error = error);
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return app;
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_running && !_timedOut) const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _error != null
                      ? 'kugo 启动失败（${_error.runtimeType}）。请检查系统权限和运行依赖。'
                      : _timedOut
                      ? '启动服务响应超时。仍在等待当前操作结束，避免重复初始化。'
                      : '正在启动 kugo…',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  const Text('详细记录见应用目录 crash.log。'),
                  TextButton(
                    onPressed: _running ? null : _start,
                    child: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
