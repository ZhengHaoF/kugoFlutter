import 'package:flutter/material.dart';

import '../../core/diagnostics/crash_log.dart';
import '../../core/theme/kugo_theme.dart';

/// 崩溃日志详情（只读 + 清空）。内容为空时给一句明确的「没有崩溃记录」。
Future<void> showCrashLogDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _CrashLogDialog(),
  );
}

class _CrashLogDialog extends StatefulWidget {
  const _CrashLogDialog();

  @override
  State<_CrashLogDialog> createState() => _CrashLogDialogState();
}

class _CrashLogDialogState extends State<_CrashLogDialog> {
  String? _text;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await CrashLog.readText();
    if (!mounted) return;
    setState(() {
      _text = text;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    await CrashLog.clear();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final text = _text ?? '';
    return AlertDialog(
      backgroundColor: kugo.surfaceElevated,
      title: Text('崩溃日志', style: kugo.section),
      content: SizedBox(
        width: 520,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : text.trim().isEmpty
                ? Center(
                    child: Text('没有崩溃记录', style: kugo.caption),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: kugo.caption.copyWith(height: 1.35),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: text.trim().isEmpty ? null : _clear,
          child: const Text('清空'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
