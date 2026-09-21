import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/playback_source.dart';
import '../../core/theme/kugo_theme.dart';
import '../../features/fm/fm_controller.dart';
import '../../features/player/player_controller.dart';

class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final isFmActive =
        ref.watch(playerControllerProvider).queueSource == PlaybackQueueSource.fm;

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
                        height: 1.1,
                      ),
                    ),
                    Text(
                      '概念版 · Windows',
                      style: kugo.caption.copyWith(
                        fontSize: 10,
                        height: 1.2,
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
                  icon: Icons.explore_rounded,
                  label: '发现',
                  selected: location.startsWith('/explore') || location == '/',
                  onTap: () => context.go('/explore'),
                ),
                _SidebarItem(
                  icon: Icons.today_rounded,
                  label: '每日推荐',
                  selected: location.startsWith('/daily'),
                  onTap: () => context.go('/daily'),
                ),
                _SidebarItem(
                  icon: Icons.leaderboard_rounded,
                  label: '排行榜',
                  selected: location.startsWith('/ranks'),
                  onTap: () => context.go('/ranks'),
                ),
                _SidebarItem(
                  icon: Icons.radio_rounded,
                  label: '私人 FM',
                  selected: isFmActive,
                  trailing: isFmActive
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
                  onTap: () {
                    final player = ref.read(playerControllerProvider);
                    if (player.queueSource == PlaybackQueueSource.fm &&
                        player.current != null) {
                      ref.read(playerControllerProvider.notifier).togglePlay();
                    } else {
                      final fm = ref.read(fmControllerProvider.notifier);
                      final pendingMode =
                          ref.read(fmControllerProvider).pendingMode;
                      unawaited(fm.start(mode: pendingMode));
                    }
                  },
                ),

                const SizedBox(height: 16),
                _buildGroupHeader('我的音乐', kugo),
                _SidebarItem(
                  icon: Icons.person_rounded,
                  label: '我的',
                  selected: location.startsWith('/profile'),
                  onTap: () => context.go('/profile'),
                ),
                _SidebarItem(
                  icon: Icons.favorite_rounded,
                  label: '我喜欢',
                  selected: location.startsWith('/likes'),
                  onTap: () => context.go('/likes'),
                ),
                _SidebarItem(
                  icon: Icons.history_rounded,
                  label: '播放历史',
                  selected: location.startsWith('/history'),
                  onTap: () => context.go('/history'),
                ),

                const SizedBox(height: 16),
                _buildGroupHeader('通用', kugo),
                _SidebarItem(
                  icon: Icons.search_rounded,
                  label: '快速搜索',
                  selected: location.startsWith('/search'),
                  onTap: () => context.go('/search'),
                ),
                _SidebarItem(
                  icon: Icons.settings_rounded,
                  label: '系统设置',
                  selected: location.startsWith('/settings'),
                  onTap: () => context.go('/settings'),
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

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final activeColor = kugo.primary;
    final inactiveColor = kugo.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? kugo.primary.withValues(alpha: 0.14)
                : _hovered
                    ? kugo.surfaceElevated.withValues(alpha: 0.6)
                    : Colors.transparent,
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
