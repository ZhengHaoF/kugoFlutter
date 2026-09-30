import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/desktop_lyric/desktop_lyric_style.dart';
import '../../features/settings/settings_controller.dart';
import 'common.dart';

/// 桌面歌词外观编辑面板：预设 + 实时预览 + 调色 / 滑块。
///
/// 打开即进入本地编辑态；滑块拖动过程用 `persist: false` 只改内存做即时
/// 预览，松手 / 关闭面板时统一落盘（对齐 [SettingsController.setLyricFontScale]）。
Future<void> showDesktopLyricStyleSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showKugoBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _StyleEditor(initial: ref.read(settingsControllerProvider).desktopLyricStyle),
  );
}

class _StyleEditor extends ConsumerStatefulWidget {
  const _StyleEditor({required this.initial});

  final DesktopLyricStyle initial;

  @override
  ConsumerState<_StyleEditor> createState() => _StyleEditorState();
}

class _StyleEditorState extends ConsumerState<_StyleEditor> {
  late DesktopLyricStyle _style = widget.initial;

  SettingsController get _ctrl => ref.read(settingsControllerProvider.notifier);

  void _apply(DesktopLyricStyle next, {bool persist = true}) {
    setState(() => _style = next);
    // 拖动过程只改内存；松手 / 离开面板再落盘。
    _ctrl.setDesktopLyricStyle(next, persist: persist);
  }

  @override
  void dispose() {
    // 关闭面板时兜底落盘一次（滑块 onChangeEnd 可能因手势取消没走到）。
    _ctrl.setDesktopLyricStyle(_style);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(KugoSpacing.lg, 12, KugoSpacing.lg, 12 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Text('桌面歌词样式', style: kugo.section)),
              const SizedBox(height: KugoSpacing.md),
              _Preview(style: _style),
              const SizedBox(height: KugoSpacing.md),
              _PresetBar(
                current: _style,
                onPick: (s) => _apply(s),
              ),
              const SizedBox(height: KugoSpacing.md),
              _ColorRow(
                label: '已唱颜色',
                value: _style.sungColor,
                onChanged: (c) => _apply(_style.copyWith(sungColor: c)),
              ),
              _ColorRow(
                label: '未唱颜色',
                value: _style.unsungColor,
                onChanged: (c) => _apply(_style.copyWith(unsungColor: c)),
              ),
              _ColorRow(
                label: '阴影颜色',
                value: _style.shadowColor,
                onChanged: (c) => _apply(_style.copyWith(shadowColor: c)),
              ),
              _SliderRow(
                label: '阴影强度',
                value: _style.shadowStrength,
                min: 0,
                max: 3,
                display: _style.shadowStrength == 0 ? '关' : _style.shadowStrength.toStringAsFixed(2),
                onChanged: (v) => _apply(_style.copyWith(shadowStrength: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(shadowStrength: v)),
              ),
              _ColorRow(
                label: '描边颜色',
                value: _style.strokeColor,
                onChanged: (c) => _apply(_style.copyWith(strokeColor: c)),
              ),
              _SliderRow(
                label: '描边宽度',
                value: _style.strokeWidth,
                min: 0,
                max: 6,
                display: _style.strokeWidth == 0 ? '关' : '${_style.strokeWidth.toStringAsFixed(1)} px',
                onChanged: (v) => _apply(_style.copyWith(strokeWidth: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(strokeWidth: v)),
              ),
              _ColorRow(
                label: '背景颜色',
                value: _style.bgColor,
                onChanged: (c) => _apply(_style.copyWith(bgColor: c)),
              ),
              _SliderRow(
                label: '背景深度',
                value: _style.bgOpacity,
                min: 0,
                max: 1,
                display: _style.bgOpacity == 0 ? '透明' : '${(_style.bgOpacity * 100).round()}%',
                onChanged: (v) => _apply(_style.copyWith(bgOpacity: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(bgOpacity: v)),
              ),
              _SliderRow(
                label: '背景圆角',
                value: _style.bgRadius,
                min: 0,
                max: 40,
                display: '${_style.bgRadius.round()} px',
                onChanged: (v) => _apply(_style.copyWith(bgRadius: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(bgRadius: v)),
              ),
              _SliderRow(
                label: '字号',
                value: _style.fontScale,
                min: 0.6,
                max: 2.0,
                display: '${(_style.fontScale * 100).round()}%',
                onChanged: (v) => _apply(_style.copyWith(fontScale: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(fontScale: v)),
              ),
              _SliderRow(
                label: '字重',
                value: _style.fontWeight,
                min: 0,
                max: 2,
                display: switch (_style.resolveFontWeight()) {
                  FontWeight.w400 => '常规',
                  FontWeight.w500 => '中等',
                  FontWeight.w600 => '半粗',
                  FontWeight.w700 => '粗体',
                  FontWeight.w800 => '特粗',
                  FontWeight.w900 => '黑体',
                  _ => '自定义',
                },
                onChanged: (v) => _apply(_style.copyWith(fontWeight: v), persist: false),
                onChangeEnd: (v) => _apply(_style.copyWith(fontWeight: v)),
              ),
              const SizedBox(height: KugoSpacing.sm),
              TextButton(
                onPressed: () => _apply(const DesktopLyricStyle()),
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 预览 ──

class _Preview extends StatelessWidget {
  const _Preview({required this.style});

  final DesktopLyricStyle style;

  @override
  Widget build(BuildContext context) {
    final demo = '夜空中最亮的星';
    final cut = (demo.length * 0.45).round();
    final size = 22.0 * style.fontScale.clamp(0.6, 2.0);
    // 大字号时预览区跟着长高，避免裁切。
    final height = math.max(108.0, size * 1.25 + 56);

    return Container(
      height: height,
      alignment: Alignment.center,
      // 棋盘格底：无论背景透明与否都能看清效果。
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KugoTheme.of(context).divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _CheckerPainter(),
          child: Center(
            child: style.hasBackground
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: style.bg.withValues(alpha: style.bgOpacity.clamp(0, 1)),
                      borderRadius: BorderRadius.circular(style.bgRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: _buildText(demo, cut),
                    ),
                  )
                : _buildText(demo, cut),
          ),
        ),
      ),
    );
  }

  Widget _buildText(String demo, int cut) {
    final shadows = style.shadowsOf();
    final size = 22.0 * style.fontScale.clamp(0.6, 2.0);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: demo.substring(0, cut),
            style: TextStyle(
              color: style.sung,
              fontSize: size,
              height: 1.25,
              fontWeight: style.resolveFontWeight(),
              letterSpacing: 0.3,
              shadows: shadows,
            ),
          ),
          TextSpan(
            text: demo.substring(cut),
            style: TextStyle(
              color: style.unsung,
              fontSize: size,
              height: 1.25,
              fontWeight: style.resolveFontWeight(),
              letterSpacing: 0.3,
              shadows: shadows,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFF2A2E36);
    final dark = Paint()..color = const Color(0xFF1A1E26);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final odd = ((x ~/ cell) + (y ~/ cell)).isOdd;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), odd ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

// ── 预设 ──

class _PresetBar extends StatelessWidget {
  const _PresetBar({required this.current, required this.onPick});

  final DesktopLyricStyle current;
  final ValueChanged<DesktopLyricStyle> onPick;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kDesktopLyricPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = kDesktopLyricPresets[i];
          final selected = p.style == current;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onPick(p.style),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: selected ? kugo.primary.withValues(alpha: 0.16) : kugo.surfaceElevated,
                border: Border.all(
                  color: selected ? kugo.primary : kugo.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 小色点：已唱色。
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.style.sung,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    p.name,
                    style: kugo.caption.copyWith(
                      color: selected ? kugo.primary : kugo.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 颜色行 ──

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: kugo.body),
      trailing: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final c = await showColorPickerDialog(context, Color(value));
          if (c != null) onChanged(c.toARGB32());
        },
        child: Container(
          width: 36,
          height: 28,
          decoration: BoxDecoration(
            color: Color(value),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kugo.divider),
          ),
        ),
      ),
    );
  }
}

// ── 滑块行 ──

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: kugo.body),
            const Spacer(),
            Text(display, style: kugo.caption),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

// ── 取色器 ──

/// 轻量 HSV 取色器：色相 / 饱和度 / 明度滑块 + 常用色板 + 预览。
Future<Color?> showColorPickerDialog(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late double _alpha = widget.initial.a;

  static const _swatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF000000),
    Color(0xFF2CE06B),
    Color(0xFF5B7CFF),
    Color(0xFFE60026),
    Color(0xFFFFB300),
    Color(0xFF00E5FF),
    Color(0xFFE1BEE7),
    Color(0xFFA855F7),
    Color(0xFF101418),
    Color(0xFFBDBDBD),
    Color(0xFFFFF3E0),
  ];

  Color get _color => _hsv.toColor().withValues(alpha: _alpha);

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return AlertDialog(
      backgroundColor: kugo.surfaceElevated,
      title: Text('选择颜色', style: kugo.section.copyWith(fontSize: 16)),
      content: SizedBox(
        width: math.min(360, MediaQuery.sizeOf(context).width * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 预览条
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kugo.divider),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _swatches)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        _hsv = HSVColor.fromColor(c);
                        _alpha = c.a;
                      });
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kugo.divider),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _HsvSlider(
              label: '色相',
              value: _hsv.hue,
              max: 360,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
              ),
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _HsvSlider(
              label: '饱和度',
              value: _hsv.saturation,
              max: 1,
              gradient: LinearGradient(
                colors: [
                  _hsv.withSaturation(0).toColor(),
                  _hsv.withSaturation(1).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _HsvSlider(
              label: '明度',
              value: _hsv.value,
              max: 1,
              gradient: LinearGradient(
                colors: [
                  _hsv.withValue(0).toColor(),
                  _hsv.withValue(1).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
            _HsvSlider(
              label: '不透明度',
              value: _alpha,
              max: 1,
              gradient: LinearGradient(
                colors: [
                  _hsv.toColor().withValues(alpha: 0),
                  _hsv.toColor().withValues(alpha: 1),
                ],
              ),
              onChanged: (v) => setState(() => _alpha = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _HsvSlider extends StatelessWidget {
  const _HsvSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: kugo.caption)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackShape: _GradientTrackShape(gradient),
              ),
              child: Slider(
                value: value.clamp(0, max),
                min: 0,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientTrackShape extends RoundedRectSliderTrackShape {
  const _GradientTrackShape(this.gradient);

  final Gradient gradient;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      paint,
    );
  }
}
