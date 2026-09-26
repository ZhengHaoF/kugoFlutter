import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/desktop_player_bar.dart';
import '../../shared/widgets/mini_player_bar.dart';
import 'desktop_sidebar.dart';

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _SeekForwardIntent extends Intent {
  const _SeekForwardIntent();
}

class _SeekBackwardIntent extends Intent {
  const _SeekBackwardIntent();
}

/// Bottom tabs with macOS Dock-style icon magnify/bounce and a light
/// Spaces-like content transition. Router (IndexedStack) is untouched.
/// On desktop wide screens (>= 800px), automatically switches to DesktopShell.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell>
    with TickerProviderStateMixin {
  late final AnimationController _bounce;
  late final AnimationController _navFade;
  int _prevIndex = 0;
  int _navOrder = 0;
  double _navDirection = 1;

  static const _tabs = [
    (Icons.explore_outlined, Icons.explore_rounded, '发现'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
  ];

  int _indexOf(String location) => switch (location) {
        _ when location.startsWith('/profile') ||
            location.startsWith('/history') ||
            location.startsWith('/likes') ||
            location.startsWith('/settings') =>
          1,
        _ => 0,
      };

  /// Sidebar reading order — used for content drift direction.
  static int _sidebarOrder(String location) => switch (true) {
        _ when location.startsWith('/discovery') => 1,
        _ when location.startsWith('/daily') => 2,
        _ when location.startsWith('/ranks') || location.startsWith('/rank/') =>
          3,
        _ when location.startsWith('/fm') => 4,
        _ when location.startsWith('/profile') => 5,
        _ when location.startsWith('/likes') => 6,
        _ when location.startsWith('/history') => 7,
        _ when location.startsWith('/search') => 8,
        _ when location.startsWith('/settings') => 9,
        _ => 0,
      };

  @override
  void initState() {
    super.initState();
    _prevIndex = _indexOf(widget.location);
    _navOrder = _sidebarOrder(widget.location);
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _navFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant RootShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _indexOf(widget.location);
    if (next != _indexOf(oldWidget.location)) {
      _prevIndex = _indexOf(oldWidget.location);
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    _navFade.dispose();
    super.dispose();
  }

  void _goTo(int index, String path) {
    if (_indexOf(widget.location) == index) return;
    _prevIndex = _indexOf(widget.location);
    _bounce.forward(from: 0);
    context.go(path);
  }

  /// Desktop sidebar switch: swap the pane, then fade/drift it in.
  ///
  /// `context.go` replaces the shell branch stack (and flips IndexedStack
  /// across branches) without a [PageRoute] transition — animating here is
  /// what the user sees when clicking the rail.
  void _desktopNavigate(String path) {
    if (!mounted || path == widget.location) return;
    final nextOrder = _sidebarOrder(path);
    _navDirection = nextOrder >= _navOrder ? 1.0 : -1.0;
    _navOrder = nextOrder;
    context.go(path);
    _navFade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild dock/scaffold colors when MaterialApp theme flips.
    final kugo = KugoTheme.of(context);
    final isDesktop = isDesktopView(context);

    if (isDesktop) {
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _SeekForwardIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekBackwardIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
              onInvoke: (_) {
                ref.read(playerControllerProvider.notifier).togglePlay();
                return null;
              },
            ),
            _SeekForwardIntent: CallbackAction<_SeekForwardIntent>(
              onInvoke: (_) {
                ref.read(playerControllerProvider.notifier).seekBy(5000);
                return null;
              },
            ),
            _SeekBackwardIntent: CallbackAction<_SeekBackwardIntent>(
              onInvoke: (_) {
                ref.read(playerControllerProvider.notifier).seekBy(-5000);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: kugo.bg,
              body: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        DesktopSidebar(
                          location: widget.location,
                          onNavigate: _desktopNavigate,
                        ),
                        Expanded(
                          child: _DesktopNavTransition(
                            animation: _navFade,
                            direction: _navDirection,
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const DesktopPlayerBar(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 全屏路由（/player、/player/lyrics、/login、/netease-login）挂在 shell
    // 之外，压根不会渲染本组件；能走进来的都是两个主 branch 内的路径。
    //
    // 所以**不再按路由字面值判断**要不要播放条：二级页（歌单/专辑/歌手/榜单/
    // 历史/我喜欢/设置/个人中心/搜索…）同样要挂 MiniPlayerBar，否则在详情页
    // 起一首歌再返回，底部既看不到在播什么、也没有回播放器的入口。
    // 只有底部 Tab 栏是主 tab 专属——深页带 tab 会把层级关系画错。
    final isMainTab =
        widget.location == '/explore' || widget.location == '/profile';

    final index = _indexOf(widget.location);
    // easeOutBack — light Dock bounce without looking springy-cheap.
    final bounceT = CurvedAnimation(
      parent: _bounce,
      curve: Curves.easeOutBack,
    );

    return Scaffold(
      backgroundColor: kugo.bg,
      body: Column(
        children: [
          Expanded(
            child: _TabTransition(
              index: index,
              prevIndex: _prevIndex,
              child: widget.child,
            ),
          ),
          // Keyed by brightness so const MiniPlayerBar remounts on theme flip.
          MiniPlayerBar(
            key: ValueKey('mini-player-${kugo.palette.brightness.name}'),
          ),
          // 单源时全局只读提示：多源页面各自有可切 chips，单源时没有任何
          // 入口告诉用户「当前用的是哪个源」，这里补一行小字（多源时隐藏，
          // 避免与页面内 chips 重复）。
          const _SingleSourceHint(),
        ],
      ),
      bottomNavigationBar: isMainTab
          ? _DockNavBar(
              index: index,
              bounce: bounceT,
              tabs: _tabs,
              onTap: (i) {
                switch (i) {
                  case 0:
                    _goTo(0, '/explore');
                  case 1:
                    _goTo(1, '/profile');
                }
              },
            )
          : null,
    );
  }
}

/// Desktop sidebar content pane: fade-in + light horizontal drift.
///
/// Same contract as [_TabTransition]: never leave a lasting Transform on
/// [child] and never change its identity — the shell navigator stays mounted.
class _DesktopNavTransition extends StatelessWidget {
  const _DesktopNavTransition({
    required this.animation,
    required this.direction,
    required this.child,
  });

  /// 0 = entering, 1 = settled.
  final Animation<double> animation;

  /// +1 when moving down the rail, -1 when moving up.
  final double direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        // Settled: raw child — zero transform (pixel grid + Hero).
        if (t >= 1.0) return child!;
        final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
        // Keep a floor so the pane never flashes pure background mid-switch.
        final opacity = (0.18 + 0.82 * eased).clamp(0.0, 1.0);
        final dx = direction * 14.0 * (1.0 - eased);
        return ClipRect(
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Spaces-like content transition.
///
/// Important: never wrap [child] in a lasting Transform/Scale and never
/// change the child's GlobalKey identity — IndexedStack must stay mounted
/// or pages end up permanently offset/clipped.
class _TabTransition extends StatefulWidget {
  const _TabTransition({
    required this.child,
    required this.index,
    required this.prevIndex,
  });

  final Widget child;
  final int index;
  final int prevIndex;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _fromIndex = 0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.prevIndex;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void didUpdateWidget(covariant _TabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _fromIndex = oldWidget.index;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Settled: paint the shell as-is — zero transform (fixes page offset).
        if (!_ctrl.isAnimating || _ctrl.value >= 1.0) {
          return widget.child;
        }

        final t = Curves.easeOutCubic.transform(_ctrl.value);
        final forward = widget.index >= _fromIndex;
        final dx = forward ? 24.0 : -24.0;
        final opacity = (0.35 + 0.65 * t).clamp(0.0, 1.0);

        return ClipRect(
          child: FadeTransition(
            opacity: AlwaysStoppedAnimation(opacity),
            child: Transform.translate(
              offset: Offset(dx * (1 - t), 0),
              child: Transform.scale(
                scale: 0.98 + 0.02 * t,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom bottom bar: Dock magnification around the selected tab + bounce.
class _DockNavBar extends StatelessWidget {
  const _DockNavBar({
    required this.index,
    required this.bounce,
    required this.tabs,
    required this.onTap,
  });

  final int index;
  final Animation<double> bounce;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onTap;

  double _dockScale(int i) {
    final dist = (i - index).abs();
    final base = switch (dist) {
      0 => 1.28,
      1 => 1.08,
      _ => 1.0,
    };
    if (dist != 0) return base;
    // easeOutBack overshoots past 1 — that IS the Dock bounce.
    final t = bounce.value.clamp(0.0, 1.4);
    final overshoot = t <= 0 ? 0.0 : Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    return (base + (overshoot - 1.0) * 0.35).clamp(0.95, 1.55);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Container(
      color: kugo.bg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: AnimatedBuilder(
            animation: bounce,
            builder: (context, _) {
              return Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _DockItem(
                        icon: i == index ? tabs[i].$2 : tabs[i].$1,
                        label: tabs[i].$3,
                        selected: i == index,
                        scale: _dockScale(i),
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Single-source read-only hint pinned just above the dock.
///
/// Only rendered when exactly one source is enabled — with two or more the
/// in-page switchable chips already show (and change) the active source, so a
/// global line would just duplicate them.
class _SingleSourceHint extends ConsumerWidget {
  const _SingleSourceHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final sources = settings.enabledSources;
    if (sources.length != 1) return const SizedBox.shrink();
    final platform = sources.first;
    return Container(
      width: double.infinity,
      color: kugo.bg,
      padding: const EdgeInsets.only(bottom: 4),
      child: Center(
        child: SourceLabel(platform: platform, prefix: '当前音源：'),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.scale,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Fixed slot so neighbors don't jump layout while scaling.
            SizedBox(
              height: 32,
              child: Center(
                child: Transform.scale(
                  scale: scale.clamp(0.9, 1.45),
                  child: Icon(
                    icon,
                    size: 26,
                    color: selected ? kugo.primary : kugo.textTertiary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: kugo.caption.copyWith(
                fontSize: 10,
                height: 1.1,
                color: selected ? kugo.primary : kugo.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
