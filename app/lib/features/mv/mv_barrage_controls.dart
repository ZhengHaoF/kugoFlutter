import 'package:flutter/material.dart';

import '../../core/models/barrage.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart' show SourceFailure;
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/common.dart' show showKugoBottomSheet;

/// MV 弹幕入口按钮 + 设置 / 发送面板。
///
/// 对齐 EchoMusic `components/music/BarrageControls.vue`：面板里同时有
/// 开关、五项显示设置（透明度 / 字号 / 速度 / 密度 / 区域）和发送框。
/// 开关与设置通过回调交给调用方落 [SettingsController]，本组件不持有全局态。
class MvBarrageButton extends StatelessWidget {
  const MvBarrageButton({
    super.key,
    required this.hash,
    required this.name,
    required this.enabled,
    required this.config,
    required this.onEnabledChanged,
    required this.onConfigChanged,
    required this.onSent,
    this.platform = MusicPlatform.kugou,
    this.color = Colors.white70,
  });

  final String hash;
  final String name;
  final bool enabled;
  final BarrageConfig config;
  final ValueChanged<bool> onEnabledChanged;

  /// [persist] = false 用于拖动中的即时预览，松手再落盘。
  final void Function(BarrageConfig config, {required bool persist})
      onConfigChanged;
  final ValueChanged<String> onSent;
  final MusicPlatform platform;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return IconButton(
      tooltip: enabled ? '弹幕已开启 · 设置与发送' : '弹幕已关闭 · 设置与发送',
      color: enabled ? kugo.primary : color,
      onPressed: () => showKugoBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _MvBarrageSheet(
          hash: hash,
          name: name,
          platform: platform,
          initialEnabled: enabled,
          initialConfig: config,
          onEnabledChanged: onEnabledChanged,
          onConfigChanged: onConfigChanged,
          onSent: onSent,
        ),
      ),
      icon: const Icon(Icons.subtitles_outlined),
    );
  }
}

class _MvBarrageSheet extends StatefulWidget {
  const _MvBarrageSheet({
    required this.hash,
    required this.name,
    required this.platform,
    required this.initialEnabled,
    required this.initialConfig,
    required this.onEnabledChanged,
    required this.onConfigChanged,
    required this.onSent,
  });

  final String hash;
  final String name;
  final MusicPlatform platform;
  final bool initialEnabled;
  final BarrageConfig initialConfig;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(BarrageConfig config, {required bool persist})
      onConfigChanged;
  final ValueChanged<String> onSent;

  @override
  State<_MvBarrageSheet> createState() => _MvBarrageSheetState();
}

class _MvBarrageSheetState extends State<_MvBarrageSheet> {
  late bool _enabled = widget.initialEnabled;
  late BarrageConfig _config = widget.initialConfig;
  final TextEditingController _draftController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  MvBarrageSource? get _source =>
      musicSourceRegistry?.capability<MvBarrageSource>(widget.platform);

  void _setEnabled(bool value) {
    setState(() => _enabled = value);
    widget.onEnabledChanged(value);
  }

  void _updateConfig(BarrageConfig next, {required bool persist}) {
    final normalized = next.normalized();
    setState(() => _config = normalized);
    widget.onConfigChanged(normalized, persist: persist);
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _send() async {
    final text = _draftController.text.trim();
    if (text.isEmpty || _sending) return;
    final src = _source;
    if (src == null) {
      _toast('当前音源不支持弹幕');
      return;
    }
    setState(() => _sending = true);
    try {
      await src.sendMvBarrage(
        hash: widget.hash,
        content: text,
        name: widget.name,
      );
      if (!mounted) return;
      _draftController.clear();
      setState(() => _sending = false);
      widget.onSent(text);
      _toast('弹幕已发送');
    } on SourceFailure catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.xl,
          KugoSpacing.md,
          KugoSpacing.xl,
          KugoSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: KugoSpacing.lg),
                decoration: BoxDecoration(
                  color: kugo.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.subtitles_outlined, size: 20, color: kugo.primary),
                const SizedBox(width: KugoSpacing.sm),
                Text('弹幕', style: kugo.section),
                const Spacer(),
                Text(
                  _enabled ? '显示中' : '已关闭',
                  style: kugo.caption.copyWith(color: kugo.textSecondary),
                ),
                const SizedBox(width: KugoSpacing.sm),
                Switch(value: _enabled, onChanged: _setEnabled),
              ],
            ),
            const SizedBox(height: KugoSpacing.md),
            _LabeledSlider(
              label: '透明度',
              valueLabel: '${_config.opacity}%',
              value: _config.opacity.toDouble(),
              min: 20,
              max: 100,
              divisions: 16,
              onChanged: (v) => _updateConfig(
                _config.copyWith(opacity: _roundTo(v, 5).round()),
                persist: false,
              ),
              onChangeEnd: (_) => _updateConfig(_config, persist: true),
            ),
            _LabeledSlider(
              label: '字号',
              valueLabel: '${_config.fontSize.round()} px',
              value: _config.fontSize,
              min: 12,
              max: 28,
              divisions: 16,
              onChanged: (v) => _updateConfig(
                _config.copyWith(fontSize: v.roundToDouble()),
                persist: false,
              ),
              onChangeEnd: (_) => _updateConfig(_config, persist: true),
            ),
            _LabeledSlider(
              label: '速度',
              valueLabel: '${_trimSpeed(_config.speed)}×',
              value: _config.speed,
              min: 0.5,
              max: 2,
              divisions: 6,
              onChanged: (v) => _updateConfig(
                _config.copyWith(speed: _roundTo(v, 0.25)),
                persist: false,
              ),
              onChangeEnd: (_) => _updateConfig(_config, persist: true),
            ),
            const SizedBox(height: KugoSpacing.sm),
            Text('密度', style: kugo.caption.copyWith(color: kugo.textSecondary)),
            const SizedBox(height: KugoSpacing.xs),
            _SegmentedRow<int>(
              value: _config.density,
              options: const [(1, '稀疏'), (2, '适中'), (3, '密集')],
              onSelect: (v) =>
                  _updateConfig(_config.copyWith(density: v), persist: true),
            ),
            const SizedBox(height: KugoSpacing.md),
            Text('显示区域', style: kugo.caption.copyWith(color: kugo.textSecondary)),
            const SizedBox(height: KugoSpacing.xs),
            _SegmentedRow<int>(
              value: _config.area,
              options: const [(25, '顶部'), (50, '上半屏'), (100, '全屏')],
              onSelect: (v) =>
                  _updateConfig(_config.copyWith(area: v), persist: true),
            ),
            const SizedBox(height: KugoSpacing.lg),
            Text(
              '发送弹幕',
              style: kugo.caption.copyWith(color: kugo.textSecondary),
            ),
            const SizedBox(height: KugoSpacing.xs),
            TextField(
              controller: _draftController,
              maxLength: kBarrageMaxLength,
              maxLines: 2,
              minLines: 2,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '写下此刻的感受…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: KugoSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _enabled ? '' : '发送后开启弹幕即可在画面上看到',
                    style: kugo.caption.copyWith(color: kugo.textTertiary),
                  ),
                ),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: kugo.caption.copyWith(color: kugo.textSecondary),
            ),
            Text(
              valueLabel,
              style: kugo.caption.copyWith(color: kugo.textPrimary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
    required this.value,
    required this.options,
    required this.onSelect,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Row(
      children: [
        for (final (optionValue, label) in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _SegmentButton(
                label: label,
                selected: optionValue == value,
                onTap: () => onSelect(optionValue),
                kugo: kugo,
              ),
            ),
          ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.kugo,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final KugoTheme kugo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kugo.primary.withValues(alpha: 0.14)
          : kugo.surface,
      borderRadius: BorderRadius.circular(KugoRadius.tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(KugoRadius.tile),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KugoSpacing.sm),
          child: Center(
            child: Text(
              label,
              style: kugo.caption.copyWith(
                color: selected ? kugo.primary : kugo.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 四舍五入到 [step] 的整数倍（滑块取连续值，落盘前归一）。
double _roundTo(double value, double step) =>
    (value / step).roundToDouble() * step;

String _trimSpeed(double speed) {
  final rounded = (speed * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.round().toString();
  return rounded.toString();
}