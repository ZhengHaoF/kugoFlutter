import 'dart:async';

import 'package:flutter/material.dart';

/// Optional native services run only after the usable app has a first frame.
/// A timeout is a degraded state, not proof that native work was cancelled.
class StartupServices extends StatefulWidget {
  const StartupServices({
    super.key,
    required this.child,
    required this.services,
    required this.onError,
    this.timeout = const Duration(seconds: 8),
    this.initialWarnings = const [],
  });

  final Widget child;
  final Map<String, Future<void> Function()> services;
  final void Function(Object, StackTrace) onError;
  final Duration timeout;
  final List<String> initialWarnings;

  @override
  State<StartupServices> createState() => _StartupServicesState();
}

class _StartupServicesState extends State<StartupServices> {
  final List<String> _warnings = [];

  @override
  void initState() {
    super.initState();
    _warnings.addAll(widget.initialWarnings);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    for (final service in widget.services.entries) {
      if (!mounted) return;
      try {
        await service.value().timeout(widget.timeout);
      } catch (error, stack) {
        widget.onError(error, stack);
        if (mounted) setState(() => _warnings.add(service.key));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        widget.child,
        if (_warnings.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            top: MediaQueryData.fromView(View.of(context)).padding.top + 16,
            child: Material(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_warnings.join('、')} 初始化失败或超时，应用已降级运行。',
                        style: const TextStyle(color: Color(0xFF493D08)),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: '关闭提示',
                      child: GestureDetector(
                        onTap: () => setState(_warnings.clear),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.close, color: Color(0xFF493D08)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
