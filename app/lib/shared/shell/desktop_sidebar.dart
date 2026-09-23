import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/playback_source.dart';
import '../../core/theme/kugo_theme.dart';
import '../../features/player/player_controller.dart';

class DesktopSidebar extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    // Only the LIVE badge depends on player state — don't rebuild the whole
    // rail (and its hover regions) on every position tick.
    final isFmActive = ref.watch(
      playerControllerProvider
          .select((s) => s.queueSource == PlaybackQueueSource.fm),
    );

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: kugo.surface,
        border: Border(
          right: BorderSide(color: kugo.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------- 顶部 Logo ----------------
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'kugo',
                      style: kugo.title.copyWith(
                        fontSize: 18,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '概念版 · Windows',
                      style: kugo.caption.copyWith(
                        fontSize: 10,
                        height: 1.25,
                        color: kugo.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ---------------- 导航项列表 ----------------
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildGroupHeader('在线音乐', kugo),
                _SidebarItem(
                  icon: Icons.auto_awesome_rounded,
                  label: '发现',
                  selected: location.startsWith('/explore') || location == '/',
                  onTap: () => onNavigate('/explore'),
                ),
                _SidebarItem(
                  icon: Icons.explore_rounded,
                  label: '探索',
                  selected: location.startsWith('/discovery'),
                  onTap: () => onNavigate('/discovery'),
                ),
                _SidebarItem(
                  icon: Icons.today_rounded,
                  label: '每日推荐',
                  selected: location.startsWith('/daily'),
                  onTap: () => onNavigate('/daily'),
                ),
                _SidebarItem(
                  icon: Icons.radio_rounded,
                  label: '私人 FM',
                  selected: location.startsWith('/fm'),
                  trailing: isFmActive && !location.startsWith('/fm')
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
                  onTap: () => onNavigate('/fm'),
                ),

                const SizedBox(height: 16),
                _buildGroupHeader('我的音乐', kugo),
                _SidebarItem(
                  icon: Icons.person_rounded,
                  label: '我的',
                  selected: location == '/profile' ||
                      (location.startsWith('/profile') &&
                          !location.startsWith('/profile/detail')),
                  onTap: () => onNavigate('/profile'),
                ),
                _SidebarItem(
                  icon: Icons.badge_outlined,
                  label: '个人中心',
                  selected: location.startsWith('/profile/detail'),
                  onTap: () => onNavigate('/profile/detail'),
                ),
                _SidebarItem(
                  icon: Icons.favorite_rounded,
                  label: '我喜欢',
                  selected: location.startsWith('/likes'),
                  onTap: () => onNavigate('/likes'),
                ),
                _SidebarItem(
                  icon: Icons.history_rounded,
                  label: '播放历史',
                  selected: location.startsWith('/history'),
                  onTap: () => onNavigate('/history'),
                ),

                const SizedBox(height: 16),
                _buildGroupHeader('通用', kugo),
                _SidebarItem(
                  icon: Icons.settings_rounded,
                  label: '系统设置',
                  selected: location.startsWith('/settings'),
                  onTap: () => onNavigate('/settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title, KugoTheme kugo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Text(
        title,
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

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
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
    final hoverFill = Colors.black.withValues(alpha: kugo.isLight ? 0.08 : 0.18);
    final idleFill = Colors.black.withValues(alpha: 0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? kugo.primary.withValues(alpha: 0.14)
                : _hovered
                    ? hoverFill
                    : idleFill,
            borderRadius: BorderRadius.circular(8),
            border: widget.selected
                ? Border(
                    left: BorderSide(color: activeColor, width: 3),
                  )
                : null,
          ),
          child: Row(
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
          ),
        ),
      ),
    );
  }
}
