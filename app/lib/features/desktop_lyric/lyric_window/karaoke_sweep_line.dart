import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    this.shadows = const [],
    this.strokeColor,
    this.strokeWidth = 0,
    this.heightFactor = 1.2,
  });

  final DesktopLyricController controller;

  /// 已唱部分颜色（酷狗系强调绿）。
  final Color sungColor;

  /// 未唱部分颜色。
  final Color unsungColor;

  /// 文字阴影（两层共用，保证可读性一致）。
  final List<Shadow> shadows;

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

  void _maybeStartTicker() {
    final shouldRun =
        _c.isPlaying && (_c.currentLyric?.text.isNotEmpty ?? false);
    if (shouldRun && _ticker == null) {
      _ticker = createTicker((_) => _onFrame());
      _ticker!.start();
    } else if (!shouldRun && _ticker != null) {
      _ticker!.stop();
    }
  }

  void _onFrame() {
    // 只 rebuild 本叶子；由 _SweepPainter.shouldRepaint 兜底去重重绘。
    if (mounted) setState(() {});
  }

  /// 当前帧的游标（ms，含 offset）：锚点 + 自走时间；暂停时用 controller 的离散值。
  int _currentPositionMs() {
    final c = _c;
    if (!c.isPlaying) return c.positionMs;
    final elapsed = DateTime.now().difference(c.anchorWall).inMilliseconds;
    return c.anchorPosMs + elapsed;
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
        shadows: widget.shadows,
      );

  TextStyle get _sungStyle => _baseStyle.copyWith(color: widget.sungColor);

  /// 描边层：与底层同字形，用 [Paint] 描边绘制；阴影不重复叠加。
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
        final maxWidth = math.max(0.0, constraints.maxWidth);
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
    // 扫光是连续动画，帧间 sweepX 几乎必然变化；两行字的重绘成本极低。
    return sweepX != oldDelegate.sweepX ||
        strokePainter != oldDelegate.strokePainter;
  }
}
