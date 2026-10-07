import 'package:flutter/material.dart';

import '../../../core/theme/kugo_theme.dart';
import '../desktop_lyric_host.dart';
import 'karaoke_sweep_line.dart';
import 'lyric_window_controller.dart';

/// 桌面歌词窗 UI：透明悬浮歌词（无卡片底）+ hover 玻璃控制条。
///
/// 业界形态：窗口全透明，可读性靠文字描边，不靠深色面板。
class DesktopLyricView extends StatefulWidget {
  const DesktopLyricView({super.key, required this.controller});

  final DesktopLyricController controller;

  @override
  State<DesktopLyricView> createState() => _DesktopLyricViewState();
}

class _DesktopLyricViewState extends State<DesktopLyricView> {
  bool _hover = false;

  DesktopLyricController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _c.notifyReady();
    });
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _onDragStart(DragStartDetails d) async {
    if (_c.locked) return;
    try {
      await DesktopLyricHost.startDragging();
    } catch (_) {}
  }

  Future<void> _onDragUpdate(DragUpdateDetails d) async {
    // 系统拖拽由 startDragging 接管；这里不需要 setPosition。
  }

  Future<void> _onDragEnd(DragEndDetails _) async {
    try {
      final b = await DesktopLyricHost.getPosition();
      await _c.reportBounds(b.x, b.y, b.width, b.height);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 锁定穿透时 hover 收不到事件，控制条只在未锁定 hover 时有用；
    // 解锁走主窗设置 / 托盘。
    final showControls = _hover && !_c.locked;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onPanStart: _onDragStart,
          onPanUpdate: _onDragUpdate,
          onPanEnd: _onDragEnd,
          // 只有子组件（歌词字/按钮）吃事件；透明留白尽量不挡下层主窗。
          behavior: HitTestBehavior.deferToChild,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 歌词本体：左对齐，撑满窗宽。
                SizedBox(width: double.infinity, child: _LyricBlock(controller: _c)),
                // 控制条：右下角 hover 浮出（与左侧歌词错开，不压字）。
                if (showControls)
                  Positioned(
                    right: 0,
                    bottom: -2,
                    child: _ControlBar(controller: _c),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricBlock extends StatelessWidget {
  const _LyricBlock({required this.controller});

  final DesktopLyricController controller;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot;
    final style = snap.style;
    final scale = style.fontScale.clamp(0.6, 2.0);
    final next = controller.nextLine;
    final tr = snap.translation ? controller.currentTranslation : null;

    final content = Column(
      // 歌词左对齐（窗口本身仍在屏幕顶部居中）。
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主行：平滑扫光（KRC 逐字插值；LRC 线性扫）。
        RepaintBoundary(
          child: KaraokeSweepLine(
            controller: controller,
            sungColor: style.sung,
            unsungColor: style.unsung,
            strokeColor: style.hasStroke ? style.stroke : null,
            strokeWidth: style.strokeWidth,
          ),
        ),
        // 副行：译文优先，否则下一行预览（EchoMusic 同款策略）
        Builder(
          builder: (_) {
            final sub = (tr != null && tr.isNotEmpty) ? tr : next;
            if (sub == null || sub.isEmpty) return const SizedBox.shrink();
            final isTr = tr != null && tr.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // 副行跟随未唱色，再压一点透明度分层。
                  color: style.unsung.withValues(alpha: isTr ? 0.72 : 0.48),
                  fontSize: (isTr ? 13 : 14) * scale,
                  height: 1.25,
                  fontWeight: isTr ? FontWeight.w400 : FontWeight.w500,
                  fontFamily: kugoFontFamily,
                  fontFamilyFallback: kugoFontFamilyFallback,
                ),
              ),
            );
          },
        ),
      ],
    );

    // 内容层背景：圆角矩形垫在歌词下，bgOpacity=0 时保持纯悬浮（P1 形态）。
    if (!style.hasBackground) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.bg.withValues(alpha: style.bgOpacity.clamp(0.0, 1.0)),
        borderRadius: BorderRadius.circular(style.bgRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: content,
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});

  final DesktopLyricController controller;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot;
    final hasTrack = snap.title.isNotEmpty || snap.artist.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        // 半透明深色底：浅色壁纸上也看得清（原来 14% 白底在白背景下几乎不可见）。
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(
            tooltip: snap.isPlaying ? '暂停' : '播放',
            icon: snap.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: hasTrack ? controller.playPause : null,
          ),
          _Btn(
            tooltip: '上一首',
            icon: Icons.skip_previous_rounded,
            onTap: hasTrack ? controller.previous : null,
          ),
          _Btn(
            tooltip: '下一首',
            icon: Icons.skip_next_rounded,
            onTap: hasTrack ? controller.next : null,
          ),
          _Btn(
            tooltip: '锁定',
            icon: Icons.lock_open_rounded,
            onTap: controller.toggleLock,
          ),
          _Btn(
            tooltip: '关闭',
            icon: Icons.close_rounded,
            onTap: controller.requestClose,
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 16,
              color: onTap == null ? Colors.white24 : Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }
}
