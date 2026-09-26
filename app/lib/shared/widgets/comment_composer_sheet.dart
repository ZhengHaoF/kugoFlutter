import 'package:flutter/material.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import 'common.dart';

/// 评论输入弹层。
///
/// 返回**非空字符串** = 用户点了发送（内容已 trim）；`null` = 取消或直接关闭。
/// 只负责收集文本，不碰网络 —— 发送由调用方走 `CommentWriteSource`。
Future<String?> showCommentComposerSheet(
  BuildContext context, {
  String hint = '说说关于这首歌的故事',
  String? replyTo,
  int maxLength = 200,
}) {
  return showKugoBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CommentComposerBody(
      hint: hint,
      replyTo: replyTo,
      maxLength: maxLength,
    ),
  );
}

class _CommentComposerBody extends StatefulWidget {
  const _CommentComposerBody({
    required this.hint,
    required this.maxLength,
    this.replyTo,
  });

  final String hint;
  final int maxLength;
  final String? replyTo;

  @override
  State<_CommentComposerBody> createState() => _CommentComposerBodyState();
}

class _CommentComposerBodyState extends State<_CommentComposerBody> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    // 打开即聚焦，移动端会同时弹出键盘。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  bool get _overLimit => _controller.text.runes.length > widget.maxLength;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    // 键盘顶起来时把内容抬上去（桌面端 viewInsets 为 0，无副作用）。
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final count = _controller.text.runes.length;
    final canSend = _text.isNotEmpty && !_overLimit;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kugo.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: KugoSpacing.md),
              Text(
                widget.replyTo == null ? '发表评论' : '回复 @${widget.replyTo}',
                style: kugo.section,
              ),
              const SizedBox(height: KugoSpacing.sm),
              TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 3,
                maxLines: 6,
                maxLength: widget.maxLength,
                style: kugo.body.copyWith(fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: kugo.caption.copyWith(color: kugo.textTertiary),
                  counterText: '', // 自绘计数，避免默认计数器样式与主题不一致
                  filled: true,
                  fillColor: kugo.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KugoRadius.card),
                    borderSide: BorderSide(color: kugo.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KugoRadius.card),
                    borderSide: BorderSide(color: kugo.divider),
                  ),
                ),
              ),
              const SizedBox(height: KugoSpacing.sm),
              Row(
                children: [
                  Text(
                    '$count/${widget.maxLength}',
                    style: kugo.caption.copyWith(
                      color: _overLimit ? kugo.primary : kugo.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: KugoSpacing.sm),
                  FilledButton(
                    onPressed: canSend
                        ? () => Navigator.of(context).pop(_text)
                        : null,
                    child: const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
