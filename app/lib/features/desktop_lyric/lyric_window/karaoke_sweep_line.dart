import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/kugo_theme.dart';
import 'lyric_window_controller.dart';

/// 桌面歌词平滑扫光行（业界桌面歌词形态）。
///
/// - 布局缓存：未唱/已唱两个 TextPainter + 逐字前缀宽度表，
///   仅在换行/字号/可用宽度变化时重算；扫光帧只改 clip 边界。
/// - 驱动：内部 Ticker 仅在播放中跑；每帧用「锚点 + elapsed」自算 positionMs，
///   只 rebuild 本叶子（controller 的 notifyListeners 不参与扫光帧率）。
/// - 绘制：底层未唱白字整行绘制，上层已唱色字按扫光边界 clipRect 裁出。
///   KRC 有逐字时间轴时做字内插值；LRC 缺 chars 时整行线性扫。
class KaraokeSweepLine extends StatefulWidget {
  const KaraokeSweepLine({
    super.key,
    required this.controller,
    this.sungColor = const Color(0xFF2CE06B),
    this.unsungColor = Colors.white,
    this.strokeColor,
    this.strokeWidth = 0,
    this.heightFactor = 1.2,
  });

  final DesktopLyricController controller;

  /// 已唱部分颜色（酷狗系强调绿）。
  final Color sungColor;

  /// 未唱部分颜色。
  final Color unsungColor;

  /// 描边颜色。null / [strokeWidth] == 0 时不描边。
  final Color? strokeColor;

  /// 描边宽度（逻辑像素）。
  final double strokeWidth;

  /// 行高系数（与字号相乘得行高）。
  final double heightFactor;

  @override
  State<KaraokeSweepLine> createState() => _KaraokeSweepLineState();
}

class _KaraokeSweepLineState extends State<KaraokeSweepLine>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  // ── 扫光插值锚点（帧驱动，见 _currentPositionMs）──
  /// Ticker 自走经过的时间。
  Duration _elapsed = Duration.zero;
  /// 上一次锚定时的 [_elapsed]。
  Duration _anchorElapsed = Duration.zero;
  /// 上一次锚定对应的主窗快照锚点时刻（null = 需要重锚）。
  DateTime? _seenAnchorWall;
  /// 锚点游标（含 offset）。
  int _anchorPosMs = 0;

  // ── 布局缓存：未唱层 + 已唱层 + 描边层 ──
  TextPainter? _basePainter;
  TextPainter? _sungPainter;
  TextPainter? _strokePainter;
  String? _layoutText;
  double? _layoutFontSize;
  double _lastMaxWidth = 0;
  // 样式参与缓存键：只改颜色/描边/字重而文本未变时也要重建 painter，
  // 否则设置面板调色不会反映到歌词窗（_ensureLayout 会命中旧缓存）。
  Color? _layoutUnsung;
  Color? _layoutSung;
  Color? _layoutStrokeColor;
  double? _layoutStrokeWidth;
  FontWeight? _layoutFontWeight;

  /// 前缀宽度表：_prefixWidth[i] = 到第 i 个字起点为止的累计宽度；
  /// 长度 = chars.length + 1（末项为整行宽）。
  List<double> _prefixWidth = const [];

  @override
  void initState() {
    super.initState();
    _maybeStartTicker();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _basePainter?.dispose();
    _sungPainter?.dispose();
    _strokePainter?.dispose();
    super.dispose();
  }

  DesktopLyricController get _c => widget.controller;

  /// 把当前游标钉到当前帧时钟上（主窗每次快照都会换 [anchorWall]）。
  void _reanchorIfSnapshotChanged() {
    final c = _c;
    if (_seenAnchorWall == c.anchorWall) return;
    _seenAnchorWall = c.anchorWall;
    _anchorPosMs = c.anchorPosMs;
    _anchorElapsed = _elapsed;
  }

  void _maybeStartTicker() {
    final shouldRun =
        _c.isPlaying && (_c.currentLyric?.text.isNotEmpty ?? false);
    if (shouldRun) {
      // Ticker 只创建一次（SingleTickerProviderStateMixin 不允许再次 createTicker）。
      _ticker ??= createTicker(_onFrame);
      if (!_ticker!.isActive) {
        // 从停止态启动：elapsed 从 0 重算，锚点等下一帧以最新快照重建。
        _elapsed = Duration.zero;
        _anchorElapsed = Duration.zero;
        _seenAnchorWall = null;
        _ticker!.start();
      }
    } else {
      _ticker?.stop();
    }
  }

  void _onFrame(Duration elapsed) {
    _elapsed = elapsed;
    // 只 rebuild 本叶子；由 _SweepPainter.shouldRepaint 兜底去重重绘。
    if (mounted) setState(() {});
  }

  /// 当前帧的游标（ms，含 offset）。
  ///
  /// 用 **Ticker 帧计时**（[_elapsed]）而不是 `DateTime.now()`：暂停/恢复或掉帧
  /// 期间流逝的墙上时间不会被算进扫光，否则恢复播放时扫光会直接冲到底。
  /// 主窗每次快照都更新 `anchorWall`，视为新锚点。
  int _currentPositionMs() {
    final c = _c;
    if (!c.isPlaying) return c.positionMs;
    _reanchorIfSnapshotChanged();
    return _anchorPosMs + (_elapsed - _anchorElapsed).inMilliseconds;
  }

  /// 计算扫光边界 x（相对文本左缘，已 clamp 到 [0, textWidth]）。
  double _computeSweepX(double textWidth) {
    final line = _c.currentLyric;
    if (line == null || line.text.isEmpty || textWidth <= 0) return 0;

    final pos = _currentPositionMs();

    // 无逐字时间轴（LRC）：整行线性扫。
    if (!line.hasCharTiming) {
      final start = line.timeMs;
      final end = line.endMs ?? start + 3000;
      if (pos <= start) return 0;
      if (pos >= end) return textWidth;
      return textWidth * (pos - start) / (end - start);
    }

    // KRC 逐字：二分找当前字（chars[i].startMs <= pos），再做字内插值。
    final chars = line.chars;
    if (pos <= chars.first.startMs) return 0;

    var lo = 0, hi = chars.length - 1, idx = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (chars[mid].startMs <= pos) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    // 当前字结束（行尾/字间空隙在时间轴内）：按下一字起点前的位置推进。
    final cur = chars[idx];
    final nextStart =
        idx + 1 < chars.length ? chars[idx + 1].startMs : cur.endMs;
    final w0 = _prefixWidth[idx];
    final w1 = (idx + 1 < _prefixWidth.length)
        ? _prefixWidth[idx + 1]
        : textWidth;
    if (pos >= nextStart && pos >= cur.endMs) {
      // 字间空隙：停在下一字起点（视觉上「即将点亮」）。
      return w1.clamp(0, textWidth);
    }

    final dur = cur.endMs - cur.startMs;
    final f = dur > 0 ? (pos - cur.startMs) / dur : 1.0;
    return (w0 + (w1 - w0) * f).clamp(0, textWidth);
  }

  /// 布局（缓存）：文本 / 字号 / 可用宽度 / 样式任一变化才重算。
  /// 返回未唱层 painter（前缀表一并重建）。
  TextPainter _ensureLayout(String text, double maxWidth) {
    final unsung = widget.unsungColor;
    final sung = widget.sungColor;
    final strokeC = widget.strokeColor;
    final strokeW = widget.strokeWidth;
    final fw = _fontWeight;
    if (_basePainter != null &&
        _layoutText == text &&
        _layoutFontSize == _fontSize &&
        _lastMaxWidth == maxWidth &&
        _layoutUnsung == unsung &&
        _layoutSung == sung &&
        _layoutStrokeColor == strokeC &&
        _layoutStrokeWidth == strokeW &&
        _layoutFontWeight == fw) {
      return _basePainter!;
    }

    _basePainter?.dispose();
    _sungPainter?.dispose();
    _strokePainter?.dispose();

    final base = TextPainter(
      text: TextSpan(text: text, style: _baseStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    final sungP = TextPainter(
      text: TextSpan(text: text, style: _sungStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    // 描边层与字形同源，仅在宽度 > 0 时构建。
    TextPainter? strokeP;
    if (strokeW > 0.004 && strokeC != null) {
      strokeP = TextPainter(
        text: TextSpan(text: text, style: _strokeStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: maxWidth);
    }

    _basePainter = base;
    _sungPainter = sungP;
    _strokePainter = strokeP;
    _layoutText = text;
    _layoutFontSize = _fontSize;
    _lastMaxWidth = maxWidth;
    _layoutUnsung = unsung;
    _layoutSung = sung;
    _layoutStrokeColor = strokeC;
    _layoutStrokeWidth = strokeW;
    _layoutFontWeight = fw;
    _rebuildPrefixTable(text, base);
    return base;
  }

  double get _fontSize =>
      24.0 * _c.snapshot.style.fontScale.clamp(0.6, 2.0);

  TextStyle get _baseStyle => TextStyle(
        color: widget.unsungColor,
        fontSize: _fontSize,
        height: widget.heightFactor,
        fontWeight: _fontWeight,
        letterSpacing: 0.3,
        // TextPainter 不走 DefaultTextStyle 合并，必须显式指定，否则落到 Roboto。
        fontFamily: kugoFontFamily,
        fontFamilyFallback: kugoFontFamilyFallback,
      );

  TextStyle get _sungStyle => _baseStyle.copyWith(color: widget.sungColor);

  /// 描边层：与底层同字形，用 [Paint] 描边绘制。
  TextStyle get _strokeStyle {
    final sc = widget.strokeColor ?? Colors.transparent;
    return TextStyle(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widget.strokeWidth
        ..color = sc
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
      fontSize: _fontSize,
      height: widget.heightFactor,
      fontWeight: _fontWeight,
      letterSpacing: 0.3,
      fontFamily: kugoFontFamily,
      fontFamilyFallback: kugoFontFamilyFallback,
    );
  }

  FontWeight get _fontWeight => _c.snapshot.style.resolveFontWeight();

  /// 按chars 顺序计算前缀宽度表（含整行宽，长度 = chars.length + 1）。
  ///
  /// 宽度取 [TextPainter.getBoxesForSelection] 的累计 box right，
  /// 保证字形合字（shaping）正确；偏移口径与 chars 的 code unit 累计一致。
  void _rebuildPrefixTable(String text, TextPainter painter) {
    final line = _c.currentLyric;
    if (line == null || !line.hasCharTiming) {
      _prefixWidth = [painter.width];
      return;
    }

    final widths = <double>[0.0];
    var offset = 0;
    for (final ch in line.chars) {
      offset += ch.text.length;
      if (offset > text.length) break;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: offset),
      );
      final right = boxes.isEmpty
          ? painter.width
          : boxes.map((b) => b.right).reduce(math.max);
      widths.add(right);
      if (offset >= text.length) break;
    }
    // 兜底末项为整行宽（chars 覆盖不满 text 时）。
    if (widths.last < painter.width) widths.add(painter.width);
    _prefixWidth = widths;
  }

  @override
  Widget build(BuildContext context) {
    _maybeStartTicker();

    final line = _c.currentLyric;
    final text = line?.text ?? _c.currentLine;
    final lineHeight = _fontSize * widget.heightFactor;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 无界约束时给默认窗宽，避免 Size(infinity) / originDx 算飞。
        final maxWidth = constraints.hasBoundedWidth
            ? math.max(0.0, constraints.maxWidth)
            : 680.0;
        // 触发布局（缓存命中时零成本）。
        final base = _ensureLayout(text, maxWidth);
        return CustomPaint(
          size: Size(maxWidth, lineHeight),
          painter: _SweepPainter(
            basePainter: base,
            sungPainter: _sungPainter,
            strokePainter: _strokePainter,
            sweepX: _computeSweepX(base.width),
          ),
        );
      },
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.basePainter,
    required this.sungPainter,
    required this.strokePainter,
    required this.sweepX,
  });

  final TextPainter basePainter;
  final TextPainter? sungPainter;
  final TextPainter? strokePainter;

  /// 已唱区域右边界（相对文本左缘）。
  final double sweepX;

  @override
  void paint(Canvas canvas, Size size) {
    final p = basePainter;
    final dy = (size.height - p.height) / 2;
    final offset = Offset(0, dy);

    // 描边层垫底：先画一圈 stroke，再叠彩色字，避免彩色被描边盖住。
    strokePainter?.paint(canvas, offset);

    // 底层：未唱。
    p.paint(canvas, offset);

    // 上层：已唱，clip 左侧扫过区域。
    final sung = sungPainter;
    if (sung == null || sweepX <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, sweepX, size.height));
    sung.paint(canvas, offset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter oldDelegate) {
    // 三个 painter 都要比：换歌（文本变→base/sung 换实例）或改样式
    // （描边/颜色变）时，若只比 sweepX，当帧恰好游标位置相同
    // （例如刚 open 的 sweepX 都是 0）就会漏 repaint，歌词卡在上一首。
    return sweepX != oldDelegate.sweepX ||
        !identical(basePainter, oldDelegate.basePainter) ||
        !identical(sungPainter, oldDelegate.sungPainter) ||
        !identical(strokePainter, oldDelegate.strokePainter);
  }
}
