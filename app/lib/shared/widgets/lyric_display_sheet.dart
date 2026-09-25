import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/settings/settings_controller.dart';
import 'common.dart';

/// 播放页 VIP/HQ 旁的「歌词显示」入口。
///
/// 有任一副行开关打开时呈高亮；点开 [showLyricDisplaySheet]。
class LyricDisplayButton extends ConsumerWidget {
  const LyricDisplayButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final active = settings.lyricTranslation || settings.lyricRomanization;

    return Tooltip(
      message: '歌词显示',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showLyricDisplaySheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Icon(
            Icons.lyrics_outlined,
            size: 16,
            color: active ? kugo.primary : kugo.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 翻译 / 罗马音开关弹层（与音质 sheet 并列，不混进音质列表）。
Future<void> showLyricDisplaySheet(BuildContext context, WidgetRef ref) {
  return showKugoBottomSheet<void>(
    context: context,
    builder: (_) => const _LyricDisplaySheetBody(),
  );
}

class _LyricDisplaySheetBody extends ConsumerWidget {
  const _LyricDisplaySheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          KugoSpacing.md,
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
                margin: const EdgeInsets.only(bottom: KugoSpacing.md),
                decoration: BoxDecoration(
                  color: kugo.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '歌词显示',
              textAlign: TextAlign.center,
              style: kugo.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '当前歌有译文/音译时才会显示副行',
              textAlign: TextAlign.center,
              style: kugo.caption,
            ),
            const SizedBox(height: KugoSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('显示翻译', style: kugo.body),
              subtitle: Text('歌词下方显示中文译文', style: kugo.caption),
              value: settings.lyricTranslation,
              onChanged: controller.setLyricTranslation,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('显示罗马音', style: kugo.body),
              subtitle: Text('日文等音译显示在副行', style: kugo.caption),
              value: settings.lyricRomanization,
              onChanged: controller.setLyricRomanization,
            ),
            const SizedBox(height: KugoSpacing.sm),
            // 字号 / 行间距：拖动中只改内存态做即时预览（播放页同时可见），
            // 松手才落盘，避免一次拖动写几十次 SharedPreferences。
            _LyricScaleSlider(
              label: '歌词字号',
              value: settings.lyricFontScale,
              min: kLyricFontScaleMin,
              max: kLyricFontScaleMax,
              onChanged: (v) => controller.setLyricFontScale(v, persist: false),
              onChangeEnd: (v) => controller.setLyricFontScale(v),
            ),
            _LyricScaleSlider(
              label: '歌词行间距',
              value: settings.lyricSpacingScale,
              min: kLyricSpacingScaleMin,
              max: kLyricSpacingScaleMax,
              onChanged: (v) =>
                  controller.setLyricSpacingScale(v, persist: false),
              onChangeEnd: (v) => controller.setLyricSpacingScale(v),
            ),
            // 已是 100% / 100% 时置灰，避免「点了没反应」的错觉。
            Center(
              child: TextButton(
                onPressed: settings.lyricFontScale == 1 &&
                        settings.lyricSpacingScale == 1
                    ? null
                    : () {
                        controller.setLyricFontScale(1);
                        controller.setLyricSpacingScale(1);
                      },
                child: const Text('恢复默认'),
              ),
            ),
            const SizedBox(height: KugoSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// 倍率滑块行：左侧名称 + 右侧百分比读数，下行滑杆。
class _LyricScaleSlider extends StatelessWidget {
  const _LyricScaleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
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
            Expanded(child: Text(label, style: kugo.body)),
            Text('${(value * 100).round()}%', style: kugo.caption),
          ],
        ),
        SliderTheme(
          // 与桌面播放条 / 音量滑块同款外观（细轨道 + 圆点）。
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: kugo.primary,
            inactiveTrackColor: kugo.divider,
            thumbColor: kugo.primary,
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
