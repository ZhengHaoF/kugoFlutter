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

    return Padding(
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
        ],
      ),
    );
  }
}
