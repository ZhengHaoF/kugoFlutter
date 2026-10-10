import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform.dart' show isDesktopPlatform;
import '../../core/desktop_capabilities.dart';

/// 进入迷你态前的窗口形态，退出时原样还原。
typedef MvDesktopMiniState = ({Rect bounds, bool maximized});

/// 桌面端 MV 迷你窗（P2-2）：把**主窗口**瘦成一块置顶小窗——可以拖到桌面
/// 任意位置、压在其他应用之上（应用内浮动层做不到这一点）。
///
/// 与 `DesktopShell` 的约定：窗口无原生标题栏（`TitleBarStyle.hidden`，
/// 在 boot 时设定），所以迷你态下的拖动由页面用 `windowManager.startDragging()`
/// 自绘拖拽区完成；[exit] 会把尺寸下限还原成 boot 时的 900×640。
class MvDesktopMini {
  const MvDesktopMini._();

  /// 迷你窗默认宽度（高度按视频宽高比换算）。
  static const double width = 360;

  /// 迷你态下的窗口尺寸下限：够拖、不至于缩成一条。
  static const Size miniMinimumSize = Size(220, 124);

  /// `DesktopShell.boot` 里设定的窗口尺寸下限，退出迷你态时还原用。
  static const Size shellMinimumSize = Size(900, 640);

  /// 进入迷你态。返回进入前的窗口形态（退出时还原）；非桌面端返回 null。
  static Future<MvDesktopMiniState?> enter(double aspect) async {
    if (!isDesktopPlatform) return null;
    MvDesktopMiniState? previous;
    try {
      final prevBounds = await windowManager.getBounds();
      final wasMaximized = await windowManager.isMaximized();
      previous = (bounds: prevBounds, maximized: wasMaximized);
      final a = (aspect.isFinite && aspect > 0) ? aspect : 16 / 9;
      // 最大化状态下 setSize 不生效，先还原。
      if (wasMaximized) {
        await windowManager.unmaximize();
      }
      await windowManager.setMinimumSize(miniMinimumSize);
      if (DesktopCapabilities.current.alwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
      }
      // 锁宽高比：拖边缩放时窗口始终保持视频形状。
      await windowManager.setAspectRatio(a);
      final w = width;
      final h = (w / a).clamp(miniMinimumSize.height, 900.0);
      await windowManager.setSize(Size(w, h));
      // 贴屏幕右下角，像系统画中画一样好找。
      if (DesktopCapabilities.current.absolutePosition) {
        await windowManager.setAlignment(Alignment.bottomRight);
      }
      return (bounds: prevBounds, maximized: wasMaximized);
    } catch (_) {
      // 窗口未初始化（测试）等场景：静默降级，页面照常全页播放。
      await exit(previous);
      return null;
    }
  }

  /// 退出迷你态：解除置顶 / 宽高比，还原窗口形态与尺寸下限。
  static Future<void> exit(MvDesktopMiniState? prev) async {
    if (!isDesktopPlatform) return;
    try {
      if (DesktopCapabilities.current.alwaysOnTop) {
        await windowManager.setAlwaysOnTop(false);
      }
      await windowManager.setAspectRatio(0);
      await windowManager.setMinimumSize(shellMinimumSize);
      if (prev == null) return;
      if (prev.maximized) {
        await windowManager.maximize();
      } else if (prev.bounds.width > 0 && prev.bounds.height > 0) {
        if (DesktopCapabilities.current.absolutePosition) {
          await windowManager.setBounds(prev.bounds);
        } else {
          await windowManager.setSize(prev.bounds.size);
        }
      }
    } catch (_) {}
  }
}
