import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform.dart';
import '../../core/theme/overtone_theme.dart';
import '../../core/theme/overtone_tokens.dart';
import '../../features/desktop_lyric/android_overlay/android_overlay_bridge.dart';
import '../../features/settings/settings_controller.dart';
import 'common.dart';

/// 播放页 VIP/HQ 旁的「歌词显示」入口。
///
/// 有任一副行开关打开时呈高亮；点开 [showLyricDisplaySheet]。
class LyricDisplayButton extends ConsumerWidget {
  const LyricDisplayButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
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
            color: active ? theme.primary : theme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 翻译 / 罗马音开关弹层（与音质 sheet 并列，不混进音质列表）。
Future<void> showLyricDisplaySheet(BuildContext context, WidgetRef ref) {
  return showOvertoneBottomSheet<void>(
    context: context,
    builder: (_) => const _LyricDisplaySheetBody(),
  );
}

class _LyricDisplaySheetBody extends ConsumerWidget {
  const _LyricDisplaySheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OvertoneSpacing.lg,
          OvertoneSpacing.md,
          OvertoneSpacing.lg,
          OvertoneSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: OvertoneSpacing.md),
                decoration: BoxDecoration(
                  color: theme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '歌词显示',
              textAlign: TextAlign.center,
              style: theme.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '当前歌有译文/音译时才会显示副行',
              textAlign: TextAlign.center,
              style: theme.caption,
            ),
            const SizedBox(height: OvertoneSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('显示翻译', style: theme.body),
              subtitle: Text('歌词下方显示中文译文', style: theme.caption),
              value: settings.lyricTranslation,
              onChanged: controller.setLyricTranslation,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('显示罗马音', style: theme.body),
              subtitle: Text('日文等音译显示在副行', style: theme.caption),
              value: settings.lyricRomanization,
              onChanged: controller.setLyricRomanization,
            ),
            if (isAndroidPlatform)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('悬浮歌词', style: theme.body),
                subtitle: Text('悬浮窗显示桌面歌词，可拖动锁定', style: theme.caption),
                value: settings.desktopLyricEnabled,
                onChanged: (v) async {
                  final bridge = ref.read(androidLyricBridgeProvider);
                  if (v) {
                    final ok = await bridge.open();
                    if (!ok) {
                      final granted = await bridge.requestPermission();
                      if (granted) await bridge.open();
                    }
                  } else {
                    await bridge.close();
                  }
                },
              ),
            const SizedBox(height: OvertoneSpacing.sm),
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
            const SizedBox(height: OvertoneSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// 播放页「歌词偏移」入口。
///
/// 只微调**当前这首歌**的偏移；全局值在设置页里调，两者叠加生效
/// （对齐 EchoMusic `adjustTimeOffset` + `globalTimeOffsetMs`）。
class LyricOffsetButton extends ConsumerWidget {
  const LyricOffsetButton({super.key, required this.trackKey});

  final String? trackKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final overridden = settings.hasLyricOffsetOverride(trackKey);

    return Tooltip(
      message: '歌词偏移',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: trackKey == null
            ? null
            : () => showLyricOffsetSheet(context, ref, trackKey: trackKey!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Icon(
            Icons.swap_vert_rounded,
            size: 16,
            color: overridden ? theme.primary : theme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 逐曲歌词偏移微调弹层。
Future<void> showLyricOffsetSheet(
  BuildContext context,
  WidgetRef ref, {
  required String trackKey,
}) {
  return showOvertoneBottomSheet<void>(
    context: context,
    builder: (_) => _LyricOffsetSheetBody(trackKey: trackKey),
  );
}

class _LyricOffsetSheetBody extends ConsumerWidget {
  const _LyricOffsetSheetBody({required this.trackKey});

  final String trackKey;

  /// 微调档位（ms）：细调 ±0.1s，粗调 ±0.5s。
  static const _steps = [-500, -100, 100, 500];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = OvertoneTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final trackOffset = settings.lyricOffsetOverrides[trackKey] ?? 0;
    final total = settings.lyricOffsetFor(trackKey);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OvertoneSpacing.lg,
          OvertoneSpacing.md,
          OvertoneSpacing.lg,
          OvertoneSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: OvertoneSpacing.md),
                decoration: BoxDecoration(
                  color: theme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '歌词偏移（当前歌曲）',
              textAlign: TextAlign.center,
              style: theme.section.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '只微调这一首；正数 = 歌词提前，负数 = 歌词延后',
              textAlign: TextAlign.center,
              style: theme.caption,
            ),
            const SizedBox(height: OvertoneSpacing.sm),
            Text(
              '本曲微调 ${_fmt(trackOffset)}　'
              '全局 ${_fmt(settings.lyricOffsetMs)}　'
              '合计生效 ${_fmt(total)}',
              textAlign: TextAlign.center,
              style: theme.body,
            ),
            const SizedBox(height: OvertoneSpacing.sm),
            // Wrap 而非 Row：桌面侧边弹层只有 ~368px 宽，四个按钮一行会溢出。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final step in _steps)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () => controller.adjustTrackLyricOffsetMs(
                      trackKey,
                      deltaMs: step,
                    ),
                    child: Text(
                      '${step > 0 ? '+' : '−'}'
                      '${(step.abs() / 1000).toStringAsFixed(1)}s',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: OvertoneSpacing.sm),
            Center(
              child: TextButton(
                onPressed: settings.hasLyricOffsetOverride(trackKey)
                    ? () => controller.adjustTrackLyricOffsetMs(
                        trackKey,
                        reset: true,
                      )
                    : null,
                child: const Text('重置本曲微调'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 偏移读数，如 `+0.5s` / `-0.1s` / `0.0s`。
  static String _fmt(int ms) {
    final sign = ms > 0 ? '+' : (ms < 0 ? '-' : '');
    return '$sign${(ms.abs() / 1000).toStringAsFixed(1)}s';
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
    final theme = OvertoneTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.body)),
            Text('${(value * 100).round()}%', style: theme.caption),
          ],
        ),
        SliderTheme(
          // 与桌面播放条 / 音量滑块同款外观（细轨道 + 圆点）。
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: theme.primary,
            inactiveTrackColor: theme.divider,
            thumbColor: theme.primary,
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
