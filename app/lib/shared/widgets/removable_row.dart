import 'dart:async';

import 'package:flutter/material.dart';

/// 一行的「退场动画 + 撤销」。
///
/// 列表里删一项原本是瞬间消失 + 1 秒 SnackBar，既没有退场也没有反悔的机会。
/// 这里把流程收成一条：
///
/// 1. 调用 [RemovableRowBuilder] 给的 `remove`；
/// 2. 行先淡出（160ms），再把高度收起（200ms）；
/// 3. 才回调 [onRemove] 提交真正的删除；
/// 4. 弹一条 4 秒的 SnackBar，点「撤销」走 [onUndo]。
///
/// 删除动作因此**只在动画后才发生**，动画期间数据还在，撤销不需要回滚写口。
class RemovableRow extends StatefulWidget {
  const RemovableRow({
    super.key,
    required this.builder,
    required this.onRemove,
    required this.onUndo,
    required this.message,
  });

  /// 第二个参数是「请求删除」，接到行的删除按钮上。
  final Widget Function(BuildContext context, VoidCallback remove) builder;

  /// 退场动画结束后才调用（真正生效）。返回 Future 便于异步写口。
  final Future<void> Function() onRemove;

  final Future<void> Function() onUndo;

  /// SnackBar 走完且**没点撤销**时调用。
  ///
  /// 给「先只动内存、等确认了再落库」的删除用（播放历史：撤销要能按原位置
  /// 放回，重新 append 会把 playedAt 改成现在，破坏听歌统计）。
  final Future<void> Function()? onCommit;

  /// SnackBar 文案，例如「已从播放历史中移除」。
  final String message;

  @override
  State<RemovableRow> createState() => _RemovableRowState();
}

class _RemovableRowState extends State<RemovableRow> {
  static const _fade = Duration(milliseconds: 160);
  static const _collapse = Duration(milliseconds: 200);

  bool _fading = false;
  bool _collapsing = false;

  Future<void> _requestRemove() async {
    if (_fading) return;
    if (!mounted) return;
    setState(() => _fading = true);
    await Future<void>.delayed(_fade);
    if (!mounted) return;
    setState(() => _collapsing = true);
    await Future<void>.delayed(_collapse);
    if (!mounted) return;
    await widget.onRemove();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final closed = messenger.showSnackBar(
      SnackBar(
        content: Text(widget.message),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => widget.onUndo(),
        ),
      ),
    ).closed;
    final commit = widget.onCommit;
    if (commit == null) return;
    // action = 用户点了撤销；超时/滑掉/被下一条顶掉都算确认删除。
    unawaited(closed.then((reason) async {
      if (reason == SnackBarClosedReason.action) return;
      await commit();
    }));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _collapse,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: _fade,
        curve: Curves.easeOut,
        opacity: _fading ? 0 : 1,
        child: _collapsing
            ? const SizedBox(width: double.infinity)
            : widget.builder(context, _requestRemove),
      ),
    );
  }
}
