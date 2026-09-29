import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/kugo_theme.dart';

/// 自绘窗口标题栏（Windows）。
///
/// 配合 `windowManager.setTitleBarStyle(TitleBarStyle.hidden)` 使用：
/// 系统标题栏不再绘制，本组件负责拖拽移动 / 最小化 / 最大化 / 关闭。
/// 高度刻意压到 36，把纵向空间还给内容；关闭走 shell 的 `setPreventClose`
/// 链路（托盘），这里只发 `windowManager.close()`。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key, this.onClose});

  /// 可选：接管关闭（关到托盘）。为空则调 `windowManager.close()`。
  final Future<void> Function()? onClose;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    // 只在创建时读一次最大化态；之后靠按钮动作后的本地翻转。
    // 不挂 WindowListener：shell 已有一份，双监听容易在 hide/show
    // 过程中叠出无谓的 platform channel 往返。
    _initMaximized();
  }

  Future<void> _initMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } catch (_) {
      // 测试环境 / 窗口未就绪：保持 false。
    }
  }

  Future<void> _toggleMaximize() async {
    try {
      if (_maximized) {
        await windowManager.unmaximize();
        _maximized = false;
      } else {
        await windowManager.maximize();
        _maximized = true;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // 整条可拖拽；按钮区各自吞掉命中，避免点按钮也拖窗口。
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {
                try {
                  windowManager.startDragging();
                } catch (_) {}
              },
              onDoubleTap: _toggleMaximize,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'kugo',
                    style: kugo.caption.copyWith(
                      fontSize: 12,
                      color: kugo.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 桌面歌词入口只留在底栏「词」/ 托盘 / 设置，标题栏不重复。
          _TitleBarButton(
            tooltip: '最小化',
            icon: Icons.remove_rounded,
            onTap: () async {
              try {
                await windowManager.minimize();
              } catch (_) {}
            },
          ),
          _TitleBarButton(
            tooltip: _maximized ? '还原' : '最大化',
            icon: _maximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            onTap: _toggleMaximize,
          ),
          _TitleBarButton(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            hoverColor: const Color(0xFFE81123),
            hoverForeground: Colors.white,
            onTap: () async {
              try {
                if (widget.onClose != null) {
                  await widget.onClose!();
                } else {
                  await windowManager.close();
                }
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.hoverColor,
    this.hoverForeground,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onTap;
  final Color? hoverColor;
  final Color? hoverForeground;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final bg = _hovered
        ? (widget.hoverColor ??
            kugo.textPrimary.withValues(alpha: kugo.isLight ? 0.08 : 0.16))
        : Colors.transparent;
    final fg = _hovered
        ? (widget.hoverForeground ?? kugo.textPrimary)
        : kugo.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onTap(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: 36,
            color: bg,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
