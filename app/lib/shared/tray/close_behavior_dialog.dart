import 'package:flutter/material.dart';

import '../../core/theme/kugo_theme.dart';
import '../../features/settings/settings_controller.dart';

/// What the user picked in the desktop close prompt, plus whether they asked us
/// to stop prompting (`记住我的选择`).
class CloseBehaviorChoice {
  const CloseBehaviorChoice(this.behavior, {this.remember = false});

  final CloseBehavior behavior;
  final bool remember;
}

/// Desktop close prompt: 退出应用 / 最小化到托盘, with an optional「记住我的选择」.
///
/// Returns `null` when the user cancels (or dismisses by clicking the barrier) —
/// the caller must then leave the window open. Shown from `DesktopShell`, which
/// has no `BuildContext`; it supplies the root navigator's context.
Future<CloseBehaviorChoice?> showCloseBehaviorDialog(BuildContext context) {
  var remember = false;
  return showDialog<CloseBehaviorChoice>(
    context: context,
    builder: (dialogContext) {
      final kugo = KugoTheme.of(dialogContext);
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('关闭 kugo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('退出应用，还是最小化到系统托盘继续播放？', style: kugo.body),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: remember,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => setState(() => remember = v ?? false),
                title: Text('记住我的选择', style: kugo.body),
                subtitle: Text('下次关闭不再询问，可在设置中修改', style: kugo.caption),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                CloseBehaviorChoice(CloseBehavior.tray, remember: remember),
              ),
              child: const Text('最小化到托盘'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                CloseBehaviorChoice(CloseBehavior.quit, remember: remember),
              ),
              child: const Text('退出应用'),
            ),
          ],
        ),
      );
    },
  );
}