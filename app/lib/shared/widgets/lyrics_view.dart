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
  double _lastViewport = 0;

  /// Uniform row height so scroll offset math stays exact.
  static const double _itemExtent = 52.0;

  int get activeIndex {
    var active = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].timeMs <= widget.positionMs) active = i;
    }
    return active;
  }

  /// Half-viewport top/bottom padding so first/last lines can sit on center.
  static double _verticalPad(double viewport) => viewport / 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.compact || widget.lines.isEmpty) return;
      _lastActive = activeIndex;
      _scrollToActive(animated: false);
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

  /// Scroll so the **active line is vertically centered** in the viewport.
  ///
  /// ListView padding is part of scrollable content, so item `i` center sits
  /// at `padTop + i * extent + extent/2` from content origin. Viewport center
  /// shows content at `offset + viewport/2`.
  void _scrollToActive({bool animated = true}) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final viewport = pos.viewportDimension;
    final padTop = _verticalPad(viewport);
    final lineCenter = padTop + activeIndex * _itemExtent + _itemExtent / 2;
    final target =
        (lineCenter - viewport / 2).clamp(0.0, pos.maxScrollExtent);
    if (!animated) {
      _controller.jumpTo(target);
      return;
    }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        if (viewport.isFinite && viewport > 0) {
          if ((viewport - _lastViewport).abs() > 0.5) {
            _lastViewport = viewport;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || widget.compact || widget.lines.isEmpty) return;
              _scrollToActive(animated: false);
            });
          }
        }
        final vPad = viewport.isFinite && viewport > 0
            ? _verticalPad(viewport)
            : _verticalPad(400);

        return NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView.builder(
            controller: _controller,
            // Half viewport padding: first/last lines can land on center.
            padding: EdgeInsets.symmetric(
              horizontal: KugoSpacing.xl,
              vertical: vPad,
            ),
            itemExtent: _itemExtent,
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final isActive = index == activeIndex;
              return GestureDetector(
                onTap: widget.onTapLine == null
                    ? null
                    : () => widget.onTapLine!(widget.lines[index].timeMs),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: _itemExtent,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: _lineStyle(isActive),
                      child: Text(
                        widget.lines[index].text,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              );
            },
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
