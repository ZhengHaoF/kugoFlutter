import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.positionMs,
    this.status = LyricsStatus.idle,
    this.onTapLine,
    this.compact = false,
  });

  final List<LyricLine> lines;
  final int positionMs;

  /// 用于区分「加载中」与「暂无歌词」；有 lines 时忽略。
  final LyricsStatus status;

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
  static const double _itemExtent = 56.0;

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
  void _scrollToActive({bool animated = true}) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final viewport = pos.viewportDimension;
    final padTop = _verticalPad(viewport);
    final lineCenter = padTop + activeIndex * _itemExtent + _itemExtent / 2;
    final target =
        (lineCenter - viewport / 2).clamp(0.0, pos.maxScrollExtent);
    if (!animated || (target - pos.pixels).abs() < 0.5) {
      _controller.jumpTo(target);
      return;
    }
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _lineOpacity(int index, int active) {
    final distance = (index - active).abs();
    if (distance == 0) return 1;
    if (distance == 1) return 0.55;
    if (distance == 2) return 0.32;
    return 0.18;
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    if (widget.lines.isEmpty) {
      final loading = widget.status == LyricsStatus.loading ||
          widget.status == LyricsStatus.idle;
      return Center(
        child: loading
            ? Text('歌词加载中…', style: kugo.caption)
            : Text('暂无歌词', style: kugo.caption),
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
                  style: _lineStyle(kugo, start + i == activeIndex).copyWith(
                    fontSize: start + i == activeIndex ? 14 : 13,
                    height: 1.25,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final desktop = isDesktopView(context);

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

        final listView = ListView.builder(
          controller: _controller,
          // Desktop: no rubber-band; mobile keeps platform feel.
          physics: desktop
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? KugoSpacing.xl : KugoSpacing.lg,
            vertical: vPad,
          ),
          itemExtent: _itemExtent,
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final isActive = index == activeIndex;
            final opacity = _lineOpacity(index, activeIndex);
            return GestureDetector(
              onTap: widget.onTapLine == null
                  ? null
                  : () => widget.onTapLine!(widget.lines[index].timeMs),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: _itemExtent,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: opacity,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: _lineStyle(kugo, isActive, desktop: desktop),
                      child: Text(
                        widget.lines[index].text,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );

        // Constrain lyric column so wide desktop windows don't leave text
        // floating in a huge empty gradient.
        final content = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 720 : double.infinity,
            ),
            child: listView,
          ),
        );

        // Hide desktop scrollbar / overscroll glow — auto-follow is the UX.
        final noBars = ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          overscroll: false,
          physics: desktop
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
        );
        return ScrollConfiguration(
          behavior: noBars,
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) => true,
            child: desktop
                ? ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0xFF000000),
                          Color(0xFF000000),
                          Color(0x00000000),
                        ],
                        stops: [0.0, 0.12, 0.88, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: content,
                  )
                : content,
          ),
        );
      },
    );
  }

  TextStyle _lineStyle(KugoTheme kugo, bool active, {bool desktop = false}) {
    return TextStyle(
      fontSize: active
          ? (desktop ? 22 : 18)
          : (desktop ? 16 : 15),
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      color: active ? kugo.textPrimary : kugo.textSecondary,
      height: 1.35,
      letterSpacing: active ? 0.2 : 0,
    );
  }
}
