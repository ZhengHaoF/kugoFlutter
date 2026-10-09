import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/playback_source.dart';
import '../../core/platform.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../features/profile/source_account.dart';
import '../../features/settings/settings_controller.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../features/player/player_controller.dart';

/// 桌面侧栏。展开 220 / 图标模式 64，选中指示条用绝对定位不挤占内容。
class DesktopSidebar extends ConsumerStatefulWidget {
  const DesktopSidebar({
    super.key,
    required this.location,
    required this.onNavigate,
  });

  final String location;

  /// Top-level destination switch. RootShell animates the content pane;
  /// a bare `go()` would hard-cut the right side.
  final void Function(String path) onNavigate;

  @override
  ConsumerState<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<DesktopSidebar> {
  bool _collapsed = false;

  static const _expandedWidth = 220.0;
  static const _collapsedWidth = 64.0;

  /// 云盘入口是否显示：当前账号源具备 [CloudDiskSource] 能力，**且**该源的
  /// 「音乐云盘」功能子开关没被关掉（两级 AND，同其它入口类功能）。
  bool _cloudDiskEnabled(WidgetRef ref) {
    final platform = ref.watch(effectiveAccountSourceProvider);
    if (musicSourceRegistry?.capability<CloudDiskSource>(platform) == null) {
      return false;
    }
    return ref
        .watch(settingsControllerProvider)
        .isFeatureEnabled(platform, SourceFeature.cloud);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    // Only the LIVE badge depends on player state — don't rebuild the whole
    // rail (and its hover regions) on every position tick.
    final isFmActive = ref.watch(
      playerControllerProvider
          .select((s) => s.queueSource == PlaybackQueueSource.fm),
    );

    // 宽度动画必须由 **一个** AnimatedContainer 驱动。
    // 外面再包一层 SizedBox(width:) 会瞬间改约束，动画等于没写。
    // 内容用 LayoutBuilder 跟实际宽度走：收窄到阈值以下自动切图标模式，
    // 展开过阈值再出文案——中途不会出现「宽 64 还硬排文字」的溢出。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: _collapsed ? _collapsedWidth : _expandedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: kugo.surface,
        border: Border(
          right: BorderSide(color: kugo.divider, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 动画中途按**当前**宽度决定版式，而不是按 _collapsed 布尔。
          final compact = constraints.maxWidth < 120;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------------- 顶部 Logo + 折叠钮 ----------------
              // 紧凑态：logo 居中，展开钮在 logo 正下方。
              if (compact)
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: kugo.accentGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _CollapseButton(
                        collapsed: true,
                        onToggle: () => setState(() => _collapsed = false),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 8, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: kugo.accentGradient,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: kugo.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'kugo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: kugo.title.copyWith(
                                fontSize: 18,
                                letterSpacing: -0.5,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _platformLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: kugo.caption.copyWith(
                                fontSize: 10,
                                height: 1.25,
                                color: kugo.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _CollapseButton(
                        collapsed: false,
                        onToggle: () => setState(() => _collapsed = true),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // ---------------- 导航项列表 ----------------
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  children: [
                    if (!compact) _buildGroupHeader('在线音乐', kugo),
                    _SidebarItem(
                      icon: Icons.auto_awesome_rounded,
                      label: '发现',
                      compact: compact,
                      selected: widget.location.startsWith('/explore') ||
                          widget.location == '/',
                      onTap: () => widget.onNavigate('/explore'),
                    ),
                    _SidebarItem(
                      icon: Icons.explore_rounded,
                      label: '探索',
                      compact: compact,
                      selected: widget.location.startsWith('/discovery'),
                      onTap: () => widget.onNavigate('/discovery'),
                    ),
                    _SidebarItem(
                      icon: Icons.today_rounded,
                      label: '每日推荐',
                      compact: compact,
                      selected: widget.location.startsWith('/daily'),
                      onTap: () => widget.onNavigate('/daily'),
                    ),
                    _SidebarItem(
                      icon: Icons.radio_rounded,
                      label: '私人 FM',
                      compact: compact,
                      selected: widget.location.startsWith('/fm'),
                      trailing: isFmActive &&
                              !widget.location.startsWith('/fm') &&
                              !compact
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kugo.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'LIVE',
                                style: TextStyle(
                                  color: kugo.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => widget.onNavigate('/fm'),
                    ),

                    const SizedBox(height: 16),
                    if (!compact) _buildGroupHeader('我的音乐', kugo),
                    _SidebarItem(
                      icon: Icons.person_rounded,
                      label: '我的',
                      compact: compact,
                      selected: widget.location == '/profile' ||
                          (widget.location.startsWith('/profile') &&
                              !widget.location.startsWith('/profile/detail')),
                      onTap: () => widget.onNavigate('/profile'),
                    ),
                    _SidebarItem(
                      icon: Icons.badge_outlined,
                      label: '个人中心',
                      compact: compact,
                      selected: widget.location.startsWith('/profile/detail'),
                      onTap: () => widget.onNavigate('/profile/detail'),
                    ),
                    _SidebarItem(
                      icon: Icons.favorite_rounded,
                      label: '我喜欢',
                      compact: compact,
                      selected: widget.location.startsWith('/likes'),
                      onTap: () => widget.onNavigate('/likes'),
                    ),
                    // 云盘是账号资产：当前账号源具备该能力才显示（酷狗/网易都有）；
                    // 再 AND 一下功能子开关（关掉「音乐云盘」即隐藏入口）。
                    if (_cloudDiskEnabled(ref))
                      _SidebarItem(
                        icon: Icons.cloud_outlined,
                        label: '音乐云盘',
                        compact: compact,
                        selected: widget.location.startsWith('/cloud'),
                        onTap: () => widget.onNavigate('/cloud'),
                      ),
                    _SidebarItem(
                      icon: Icons.history_rounded,
                      label: '播放历史',
                      compact: compact,
                      selected: widget.location.startsWith('/history'),
                      onTap: () => widget.onNavigate('/history'),
                    ),

                    const SizedBox(height: 16),
                    if (!compact) _buildGroupHeader('通用', kugo),
                    _SidebarItem(
                      icon: Icons.settings_rounded,
                      label: '系统设置',
                      compact: compact,
                      selected: widget.location.startsWith('/settings'),
                      onTap: () => widget.onNavigate('/settings'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _platformLabel() {
    if (isWindowsPlatform) return '概念版 · Windows';
    if (Platform.isMacOS) return '概念版 · macOS';
    if (Platform.isLinux) return '概念版 · Linux';
    return '概念版';
  }

  Widget _buildGroupHeader(String title, KugoTheme kugo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: kugo.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: kugo.textTertiary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CollapseButton extends StatelessWidget {
  const _CollapseButton({
    required this.collapsed,
    required this.onToggle,
  });

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Tooltip(
      message: collapsed ? '展开侧栏' : '折叠侧栏',
      child: IconButton(
        onPressed: onToggle,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: Icon(
          collapsed
              ? Icons.keyboard_arrow_right_rounded
              : Icons.keyboard_arrow_left_rounded,
          color: kugo.textTertiary,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final Widget? trailing;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  // Stable tear-offs so MouseRegion doesn't see new closures every rebuild.
  void _handleEnter(PointerEnterEvent _) {
    if (_hovered) return;
    setState(() => _hovered = true);
  }

  void _handleExit(PointerExitEvent _) {
    if (!_hovered || !mounted) return;
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final activeColor = kugo.primary;
    final inactiveColor = kugo.textSecondary;
    // Same RGB as the hover fill (black); only alpha animates. Avoids
    // Colors.transparent (transparent black) lerping through gray.
    final hoverFill =
        Colors.black.withValues(alpha: kugo.isLight ? 0.08 : 0.18);
    final idleFill = Colors.black.withValues(alpha: 0);
    final compact = widget.compact;

    // 紧凑态整格就是图标，不要套 Row / SizedBox(infinity)。
    final Widget body = compact
        ? Center(
            child: Icon(
              widget.icon,
              size: 20,
              color: widget.selected ? activeColor : inactiveColor,
            ),
          )
        : Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: widget.selected ? activeColor : inactiveColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.normal,
                    color: widget.selected ? activeColor : kugo.textPrimary,
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          );

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.ease,
      margin: const EdgeInsets.symmetric(vertical: 2),
      height: compact ? 40 : null,
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 9),
      decoration: BoxDecoration(
        // 选中只留两个信号：淡底 + 左侧短胶囊。底色从 0.14 压到 0.10，
        // 免得和指示条一起抢眼。
        color: widget.selected
            ? kugo.primary.withValues(alpha: 0.10)
            : _hovered
                ? hoverFill
                : idleFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: body,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (compact)
              Tooltip(message: widget.label, child: tile)
            else
              tile,
            // 选中指示条：短胶囊，收进胶囊**内侧**并离左沿 4px，两端圆角。
            // 绝对定位是为了不挤占内容宽度（旧 Border(left:3) 会让选中项
            // 标题比未选中右移 3px，观感发抖）。节点常驻、只过渡透明度，
            // 切换时才不会硬切；画在 tile 之后，免得被选中底色盖住。
            Positioned(
              left: 4,
              top: 9,
              bottom: 9,
              child: AnimatedOpacity(
                opacity: widget.selected ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
