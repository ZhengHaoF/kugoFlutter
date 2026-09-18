import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.positionMs,
    this.onTapLine,
    this.compact = false,
  });

  final List<LyricLine> lines;
  final int positionMs;
  final ValueChanged<int>? onTapLine;

  /// When true, only shows current ± 1 lines (player bottom preview).
  final bool compact;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _controller = ScrollController();
  int _lastActive = -1;

  int get activeIndex {
    var active = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].timeMs <= widget.positionMs) active = i;
    }
    return active;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.compact || widget.lines.isEmpty) return;
      _lastActive = activeIndex;
      _scrollToActive();
    });
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.compact &&
        widget.lines.isNotEmpty &&
        (activeIndex != _lastActive || oldWidget.lines.isEmpty)) {
      _lastActive = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActive();
      });
    }
  }

  void _scrollToActive() {
    if (!_controller.hasClients) return;
    final target = (activeIndex * 56.0 - 120).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return Center(
        child: Text('暂无歌词', style: KugoTypography.caption),
      );
    }

    if (widget.compact) {
      final start = (activeIndex - 1).clamp(0, widget.lines.length - 1);
      final visible = widget.lines.skip(start).take(2).toList();
      return ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < visible.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  visible[i].text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _lineStyle(start + i == activeIndex).copyWith(
                    fontSize: start + i == activeIndex ? 14 : 13,
                    height: 1.25,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(
        horizontal: KugoSpacing.xl,
        vertical: 12,
      ),
      itemCount: widget.lines.length,
      itemBuilder: (context, index) {
        final isActive = index == activeIndex;
        return GestureDetector(
          onTap: widget.onTapLine == null
              ? null
              : () => widget.onTapLine!(widget.lines[index].timeMs),
          behavior: HitTestBehavior.opaque,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: _lineStyle(isActive),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                widget.lines[index].text,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _lineStyle(bool active) {
    return TextStyle(
      fontSize: active ? 18 : 15,
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      color: active ? KugoColors.textPrimary : KugoColors.textSecondary,
      height: 1.35,
    );
  }
}
