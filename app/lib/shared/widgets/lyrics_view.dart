import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../features/settings/settings_controller.dart';

class LyricsView extends ConsumerStatefulWidget {
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
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final _controller = ScrollController();
  int _lastActive = -1;
  double _lastViewport = 0;

  /// 上次渲染时的行盒高度。字号/行间距倍率或副行开关变化都会改变它，
  /// 此时需重新居中当前行——否则滚动偏移仍按旧行高算，当前行会跑偏。
  double _lastExtent = 0;

  int get activeIndex {
    var active = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].timeMs <= widget.positionMs) active = i;
    }
    return active;
  }

  /// Half-viewport top/bottom padding so first/last lines can sit on center.
  static double _verticalPad(double viewport) => viewport / 2;

  bool _showTr(AppSettings s) => s.lyricTranslation;
  bool _showRo(AppSettings s) => s.lyricRomanization;

  /// 行盒高度 = 基准 56（+ 副行加成）× 字号倍率 × 行间距倍率。
  ///
  /// 行间距下限（0.5）可能把行盒压到比文字本身还矮，故取「文字实际高度」
  /// 兜底——否则 ListView 会连同文字一起裁掉上下边缘。
  double _itemExtent({required bool desktop}) {
    final s = ref.read(settingsControllerProvider);
    var base = 56.0;
    if (_showTr(s)) base += 18;
    if (_showRo(s)) base += 16;
    final scaled = base * s.lyricFontScale * s.lyricSpacingScale;
    return math.max(scaled, _contentHeight(s, desktop: desktop));
  }

  /// 单行（活动行 + 开启的副行）文字实际占位高度，按最大字号的档位算。
  double _contentHeight(AppSettings s, {required bool desktop}) {
    var h = (desktop ? 22.0 : 18.0) * 1.35 * s.lyricFontScale;
    if (_showTr(s)) h += 12 * 1.25 * s.lyricFontScale;
    if (_showRo(s)) h += 11 * 1.25 * s.lyricFontScale;
    return h;
  }

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
    // 用上次布局的行盒高度（桌面/移动基准不同），保证与 ListView 实际一致。
    final extent = _lastExtent;
    final lineCenter = padTop + activeIndex * extent + extent / 2;
    final target = (lineCenter - viewport / 2).clamp(0.0, pos.maxScrollExtent);
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
    final settings = ref.watch(settingsControllerProvider);
    final showTr = _showTr(settings);
    final showRo = _showRo(settings);

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
      return _buildCompact(kugo, showTr, showRo, settings);
    }

    final desktop = isDesktopView(context);
    final extent = _itemExtent(desktop: desktop);

    // 此处已排除 lines 为空的情况（上方提前返回）。
    if ((extent - _lastExtent).abs() > 0.01) {
      _lastExtent = extent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.compact || widget.lines.isEmpty) return;
        _scrollToActive(animated: false);
      });
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

        final listView = ListView.builder(
          controller: _controller,
          physics: desktop
              ? const ClampingScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          padding: EdgeInsets.symmetric(
            horizontal: desktop ? KugoSpacing.xl : KugoSpacing.lg,
            vertical: vPad,
          ),
          itemExtent: extent,
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final isActive = index == activeIndex;
            final opacity = _lineOpacity(index, activeIndex);
            final line = widget.lines[index];
            return GestureDetector(
              onTap: widget.onTapLine == null
                  ? null
                  : () => widget.onTapLine!(line.timeMs),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: extent,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    opacity: opacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PrimaryLine(
                          line: line,
                          positionMs: widget.positionMs,
                          isActive: isActive,
                          desktop: desktop,
                          style: _lineStyle(
                            kugo,
                            isActive,
                            desktop: desktop,
                            scale: settings.lyricFontScale,
                          ),
                          accent: kugo.primary,
                        ),
                        if (showTr && line.translated != null)
                          _SecondaryLine(
                            text: line.translated!,
                            style: _secondaryStyle(
                              kugo,
                              isActive,
                              scale: settings.lyricFontScale,
                            ),
                          ),
                        if (showRo && line.romanized != null)
                          _SecondaryLine(
                            text: line.romanized!,
                            style: _secondaryStyle(
                              kugo,
                              isActive,
                              roman: true,
                              scale: settings.lyricFontScale,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );

        final content = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 720 : double.infinity,
            ),
            child: listView,
          ),
        );

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

  Widget _buildCompact(
    KugoTheme kugo,
    bool showTr,
    bool showRo,
    AppSettings settings,
  ) {
    final start = (activeIndex - 1).clamp(0, widget.lines.length - 1);
    final visible = widget.lines.skip(start).take(2).toList();
    // 迷你条 / FM 卡的高度是算出来的（可能只剩 48px），字号倍率在这里收敛，
    // 避免用户把字号调大后在窄条里被 ClipRect 裁掉。
    final scale = settings.lyricFontScale.clamp(0.85, 1.25);
    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < visible.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: 1 * settings.lyricSpacingScale,
              ),
              child: Column(
                children: [
                  Text(
                    visible[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _lineStyle(kugo, start + i == activeIndex).copyWith(
                      fontSize:
                          (start + i == activeIndex ? 14 : 13) * scale,
                      height: 1.25,
                    ),
                  ),
                  if (start + i == activeIndex) ...[
                    if (showTr && visible[i].translated != null)
                      Text(
                        visible[i].translated!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(fontSize: 11 * scale),
                      ),
                    if (showRo && visible[i].romanized != null)
                      Text(
                        visible[i].romanized!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(
                          fontSize: 10 * scale,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 主行样式。[scale] 为歌词字号倍率（设置里「歌词字号」）。
  TextStyle _lineStyle(
    KugoTheme kugo,
    bool active, {
    bool desktop = false,
    double scale = 1,
  }) {
    final base = active ? (desktop ? 22.0 : 18.0) : (desktop ? 16.0 : 15.0);
    return TextStyle(
      fontSize: base * scale,
      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      color: active ? kugo.textPrimary : kugo.textSecondary,
      height: 1.35,
      letterSpacing: active ? 0.2 : 0,
    );
  }

  /// 副行样式。[scale] 为歌词字号倍率。
  TextStyle _secondaryStyle(
    KugoTheme kugo,
    bool active, {
    bool roman = false,
    double scale = 1,
  }) {
    return kugo.caption.copyWith(
      fontSize: (roman ? 11.0 : 12.0) * scale,
      fontStyle: roman ? FontStyle.italic : FontStyle.normal,
      color: active
          ? kugo.textSecondary
          : kugo.textSecondary.withValues(alpha: 0.7),
      height: 1.25,
    );
  }
}

/// 当前行：有逐字时间轴时做卡拉 OK 已唱/未唱着色。
class _PrimaryLine extends StatelessWidget {
  const _PrimaryLine({
    required this.line,
    required this.positionMs,
    required this.isActive,
    required this.desktop,
    required this.style,
    required this.accent,
  });

  final LyricLine line;
  final int positionMs;
  final bool isActive;
  final bool desktop;
  final TextStyle style;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = line.text;
    if (text.isEmpty) return const SizedBox.shrink();

    if (!isActive || !line.hasCharTiming) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final sung = line.sungCharCount(positionMs).clamp(0, text.length);
    final played = style.copyWith(
      color: accent,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (sung > 0) TextSpan(text: text.substring(0, sung), style: played),
          if (sung < text.length)
            TextSpan(text: text.substring(sung), style: style),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SecondaryLine extends StatelessWidget {
  const _SecondaryLine({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
