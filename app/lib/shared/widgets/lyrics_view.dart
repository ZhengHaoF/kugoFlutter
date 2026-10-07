import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/lrc_parser.dart';
import '../../features/settings/settings_controller.dart';

class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({
    super.key,
    required this.lines,
    required this.positionMs,
    this.status = LyricsStatus.idle,
    this.onTapLine,
    this.compact = false,
    this.isPlaying = false,
  });

  final List<LyricLine> lines;
  final int positionMs;

  /// 用于区分「加载中」与「暂无歌词」；有 lines 时忽略。
  final LyricsStatus status;

  final ValueChanged<int>? onTapLine;

  /// When true, only shows current ± 1 lines (player bottom preview).
  final bool compact;

  /// 是否正在播放。true 时活动行的逐字扫光由内部 Ticker 按帧插值（平滑）；
  /// false（暂停 / 无逐字时间轴）时退回离散的位置流。
  final bool isPlaying;

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

  /// 用户手动翻看的宽限期计时器。非空 = 处于手动态。
  Timer? _manualTimer;

  /// 手动态期间不跟随播放进度，否则下一次 tick 会把用户拽回当前行。
  bool get _isManual => _manualTimer != null;

  /// 配置变化触发的重新居中只需要排一帧就够了，重复排队会连续抢滚动。
  bool _recenterQueued = false;

  /// 手动介入后停留多久自动恢复跟随。
  static const _resumeDelay = Duration(seconds: 4);

  /// Cache for [activeIndex] so the per-row lookups inside `itemBuilder` do not
  /// repeat the search. Keyed on the line list identity plus the position, which
  /// is exactly the pair the result depends on.
  List<LyricLine>? _activeCacheLines;
  int _activeCachePosition = -1 << 31;
  int _activeCacheValue = 0;

  /// Index of the line currently highlighted. Binary search + memoised: this is
  /// read once per visible row per build, and used to be an O(n) scan each time.
  int get activeIndex {
    final lines = widget.lines;
    if (identical(lines, _activeCacheLines) &&
        widget.positionMs == _activeCachePosition) {
      return _activeCacheValue;
    }
    _activeCacheLines = lines;
    _activeCachePosition = widget.positionMs;
    _activeCacheValue = activeLyricIndex(lines, widget.positionMs);
    return _activeCacheValue;
  }

  /// Half-viewport top/bottom padding so first/last lines can sit on center.
  static double _verticalPad(double viewport) => viewport / 2;

  bool _showTr(AppSettings s) => s.lyricTranslation;
  bool _showRo(AppSettings s) => s.lyricRomanization;

  /// 行盒高度 = 基准 56（+ 副行加成）× 字号倍率 × 行间距倍率。
  ///
  /// 行间距下限（0.4）可能把行盒压到比文字本身还矮，故取「文字实际高度」
  /// 兜底——否则 ListView 会连同文字一起裁掉上下边缘。
  double _itemExtent({required bool desktop}) {
    final s = ref.read(settingsControllerProvider);
    var base = 56.0;
    if (_showTr(s)) base += 18;
    if (_showRo(s)) base += 16;
    final scaled = base * s.lyricFontScale * s.lyricSpacingScale;
    return math.max(scaled, _contentHeight(s, desktop: desktop));
  }

  /// 单行（活动行 + 开启的副行）文字实际占位高度，按最大字号的档位算——
  /// 活动行字号最大（18/22 w700），这就是行盒的物理下限。
  ///
  /// 不要改成按非活动行（15/16）算：行盒高度固定（ListView `itemExtent` +
  /// `SizedBox`），活动行 24.3 的文字塞进更矮的盒子会 RenderFlex overflow。
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
      // 手动态下只更新「认准的行」，不动滚动位置。
      if (_isManual) return;
      _queueRecenter(animated: true);
    }
  }

  /// 排一帧后重新居中去重调用者——行高/视口变化时 build 里可能会连着算好几帧。
  void _queueRecenter({bool animated = false}) {
    if (_recenterQueued) return;
    _recenterQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recenterQueued = false;
      if (!mounted || widget.compact || widget.lines.isEmpty) return;
      _scrollToActive(animated: animated);
    });
  }

  /// 进入「用户手动态」：[_resumeDelay] 内暂停自动跟随。
  ///
  /// 桌面端用滚轮/触摸板翻歌词、移动端拖拽都一样处理：没有这段宽限期的话，
  /// 下一次进度 tick 会立刻把视图拽回当前行，用户看起来像「歌词滚不动」。
  void _enterManualMode() {
    _manualTimer?.cancel();
    final wasManual = _manualTimer != null;
    _manualTimer = Timer(_resumeDelay, () {
      _manualTimer = null;
      if (!mounted) return;
      setState(() {});
      _scrollToActive();
    });
    // 第一次进入时要重建一份手动态 UI（「回到当前行」按钮）。
    if (!wasManual && mounted) setState(() {});
  }

  /// 点「回到当前行」：立刻恢复跟随，不等宽限期。
  void _resumeFollow() {
    _manualTimer?.cancel();
    _manualTimer = null;
    if (mounted) setState(() {});
    _scrollToActive();
  }

  /// Scroll so the **active line is vertically centered** in the viewport.
  void _scrollToActive({bool animated = true}) {
    if (!_controller.hasClients) return;
    if (_isManual && animated) return;
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
    _manualTimer?.cancel();
    _manualTimer = null;
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

  /// Non-active rows are cached between position ticks.
  ///
  /// The view is rebuilt on every tick, but a row's rendering only depends on
  /// its opacity (a function of the distance to the active row) plus layout
  /// settings. Returning the *identical* widget instance lets Flutter
  /// short-circuit `updateChild` and skip the whole subtree — so a tick now
  /// costs one row instead of every visible row.
  ///
  /// The cached opacity is stored alongside the widget: scrolling or advancing
  /// the active line changes a row's distance, and a naive `index -> widget`
  /// map would then keep painting the old (stale) fade.
  final Map<int, _CachedRow> _rowCache = {};
  Object? _rowCacheKey;

  /// Invalidate [_rowCache] when anything a row's appearance depends on changes.
  void _syncRowCache(Object key) {
    if (_rowCacheKey == key) return;
    _rowCacheKey = key;
    _rowCache.clear();
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
      _queueRecenter();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        if (viewport.isFinite && viewport > 0) {
          if ((viewport - _lastViewport).abs() > 0.5) {
            _lastViewport = viewport;
            _queueRecenter();
          }
        }
        final vPad = viewport.isFinite && viewport > 0
            ? _verticalPad(viewport)
            : _verticalPad(400);

        final active = activeIndex;
        // Rows depend on layout settings; drop the cache when those change.
        _syncRowCache(Object.hashAll([
          // Identity, not length: a different song can have the same line count
          // and would otherwise reuse the previous song's rows.
          identityHashCode(widget.lines),
          settings.lyricFontScale,
          settings.lyricSpacingScale,
          showTr,
          showRo,
          extent,
        ]));

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
            final opacity = _lineOpacity(index, active);
            if (index != active) {
              final cached = _rowCache[index];
              if (cached != null && cached.opacity == opacity) {
                return cached.widget;
              }
              final built = _buildRow(
                index: index,
                opacity: opacity,
                isActive: false,
                desktop: desktop,
                settings: settings,
                showTr: showTr,
                showRo: showRo,
                kugo: kugo,
                extent: extent,
              );
              _rowCache[index] = _CachedRow(opacity, built);
              return built;
            }
            // The active row is rebuilt every tick: its karaoke highlight and
            // opacity follow the live cursor. Everything else is skipped.
            _rowCache.remove(index);
            return _buildRow(
              index: index,
              opacity: opacity,
              isActive: true,
              desktop: desktop,
              settings: settings,
              showTr: showTr,
              showRo: showRo,
              kugo: kugo,
              extent: extent,
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
        final masked = desktop
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
            : content;

        return Listener(
          // 桌面滚轮/触摸板不会带 dragDetails，只能从 pointer signal 认出来。
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _enterManualMode();
          },
          child: ScrollConfiguration(
            behavior: noBars,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // 拖拽（移动端手指 / 桌面按住滑）只有用户发起时才带 dragDetails。
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _enterManualMode();
                }
                return true;
              },
              child: Stack(
                children: [
                  masked,
                  // 「回到当前行」放在遮罩之外，否则会被上下渐隐吃掉透明度。
                  if (_isManual)
                    Positioned(
                      right: desktop ? 24 : 12,
                      bottom: desktop ? 20 : 12,
                      child: _ResumeFollowChip(
                        kugo: kugo,
                        onTap: _resumeFollow,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow({
    required int index,
    required double opacity,
    required bool isActive,
    required bool desktop,
    required AppSettings settings,
    required bool showTr,
    required bool showRo,
    required KugoTheme kugo,
    required double extent,
  }) {
    final line = widget.lines[index];
    return GestureDetector(
      onTap: widget.onTapLine == null ? null : () => widget.onTapLine!(line.timeMs),
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
                if (isActive)
                  _ActiveLine(
                    line: line,
                    positionMs: widget.positionMs,
                    isPlaying: widget.isPlaying,
                    style: _lineStyle(
                      kugo,
                      true,
                      desktop: desktop,
                      scale: settings.lyricFontScale,
                    ),
                    accent: kugo.primary,
                  )
                else
                  _PrimaryLine(
                    line: line,
                    style: _lineStyle(
                      kugo,
                      false,
                      desktop: desktop,
                      scale: settings.lyricFontScale,
                    ),
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

/// A non-active lyric row, memoised across position ticks.
///
/// [opacity] is stored because it depends on the distance to the active row,
/// so the entry has to be re-validated when that distance changes.
class _CachedRow {
  const _CachedRow(this.opacity, this.widget);

  final double opacity;
  final Widget widget;
}

/// 手动翻歌词期间浮出的「回到当前行」。
///
/// 点一下立刻恢复跟随；不点则等宽限期结束自动回来。
class _ResumeFollowChip extends StatelessWidget {
  const _ResumeFollowChip({required this.kugo, required this.onTap});

  final KugoTheme kugo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '回到正在播放的那一行',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: kugo.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kugo.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.my_location_rounded, size: 14, color: kugo.primary),
                const SizedBox(width: 6),
                Text(
                  '回到当前行',
                  style: kugo.caption.copyWith(
                    fontSize: 12,
                    color: kugo.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 非活动行：普通单行文本（无逐字着色）。
class _PrimaryLine extends StatelessWidget {
  const _PrimaryLine({
    required this.line,
    required this.style,
  });

  final LyricLine line;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (line.text.isEmpty) return const SizedBox.shrink();
    return Text(
      line.text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// 活动行：内部 Ticker 按「锚点 + elapsed」在帧间插值游标，**只重建本叶子**，
/// 让逐字扫光从「位置流节奏（100–200ms 跳字）」变成每帧平滑。
///
/// 思路与桌面歌词窗 `karaoke_sweep_line.dart` 一致：父级每次位置 tick 送来新
/// 游标即作为新锚点（切行 / seek 会跳变，也靠它纠偏）；暂停或无逐字时间轴
/// （LRC）时不跑 Ticker，退回离散渲染。
class _ActiveLine extends StatefulWidget {
  const _ActiveLine({
    required this.line,
    required this.positionMs,
    required this.isPlaying,
    required this.style,
    required this.accent,
  });

  final LyricLine line;
  final int positionMs;
  final bool isPlaying;
  final TextStyle style;
  final Color accent;

  @override
  State<_ActiveLine> createState() => _ActiveLineState();
}

class _ActiveLineState extends State<_ActiveLine>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// Ticker 自走经过的时间（帧驱动）。用它而不是 `DateTime.now()`：暂停/恢复
  /// 或窗口掉帧期间流逝的墙上时间不会被算进扫光，否则恢复播放时扫光会直接
  /// 冲到整行、看起来"逐字滚动失效"。
  Duration _elapsed = Duration.zero;
  /// 上一次锚定时的 [_elapsed] 与游标；帧间插值 = 锚点游标 + (elapsed - 锚点 elapsed)。
  Duration _anchorElapsed = Duration.zero;
  int _anchorPosMs = 0;

  bool get _smooth =>
      widget.isPlaying &&
      widget.line.hasCharTiming &&
      widget.line.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _anchorPosMs = widget.positionMs;
  }

  @override
  void didUpdateWidget(covariant _ActiveLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 位置流送来新游标 / 切行 / 播放态变化 → 重锚。播放态变化必须重锚：
    // 否则暂停期间的时间会被算进扫光。
    if (oldWidget.positionMs != widget.positionMs ||
        oldWidget.isPlaying != widget.isPlaying ||
        !identical(oldWidget.line, widget.line)) {
      _reanchor();
    }
  }

  @override
  void dispose() {
    // 停掉即可：Ticker 由 SingleTickerProviderStateMixin 负责释放，
    // 且该 mixin 在 dispose 时断言 ticker 不得处于 active。
    _ticker?.stop();
    super.dispose();
  }

  /// 把当前游标钉到当前帧时钟上（切行 / seek / 暂停恢复都走这里）。
  void _reanchor() {
    _anchorPosMs = widget.positionMs;
    _anchorElapsed = _elapsed;
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    if (mounted) setState(() {});
  }

  /// 当前帧游标：平滑态用「锚点 + Ticker 自走时间」，否则用父级离散值。
  int _currentPositionMs() {
    if (!_smooth) return widget.positionMs;
    return _anchorPosMs + (_elapsed - _anchorElapsed).inMilliseconds;
  }

  /// 平滑态 start、其余 stop。Ticker **只创建一次**：
  /// SingleTickerProviderStateMixin 在 dispose 后不允许再次 createTicker
  /// （会断言失败、令活动行 build 抛错，表现为歌词区重建/滚动异常）。
  void _syncTicker() {
    if (_smooth) {
      _ticker ??= createTicker(_onTick);
      if (!_ticker!.isActive) {
        // 从停止态启动：Ticker 的 elapsed 从 0 重新计，锚点也一并重来。
        _elapsed = Duration.zero;
        _reanchor();
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTicker();

    final text = widget.line.text;
    if (text.isEmpty) return const SizedBox.shrink();

    // LRC（无逐字时间轴）：整行用活动样式，无逐字填充。
    if (!widget.line.hasCharTiming) {
      return Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }

    final sung = widget
        .line
        .sungCharCount(_currentPositionMs())
        .clamp(0, text.length);
    final played = widget.style.copyWith(
      color: widget.accent,
      fontWeight: FontWeight.w700,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (sung > 0) TextSpan(text: text.substring(0, sung), style: played),
          if (sung < text.length)
            TextSpan(text: text.substring(sung), style: widget.style),
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
