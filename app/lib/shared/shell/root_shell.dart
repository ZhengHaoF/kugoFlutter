import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import '../../features/player/player_controller.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  int _prevIndex = 0;

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

  @override
  void initState() {
    super.initState();
    _prevIndex = _indexOf(widget.location);
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
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
    super.dispose();
  }

  void _goTo(int index, String path) {
    if (_indexOf(widget.location) == index) return;
    _prevIndex = _indexOf(widget.location);
    _bounce.forward(from: 0);
    context.go(path);
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
                final ctl = ref.read(playerControllerProvider.notifier);
                final cur = ref.read(playerControllerProvider).positionMs;
                ctl.seekTo(cur + 5000);
                return null;
              },
            ),
            _SeekBackwardIntent: CallbackAction<_SeekBackwardIntent>(
              onInvoke: (_) {
                final ctl = ref.read(playerControllerProvider.notifier);
                final cur = ref.read(playerControllerProvider).positionMs;
                ctl.seekTo(cur - 5000);
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
                        DesktopSidebar(location: widget.location),
                        Expanded(child: widget.child),
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

    final isMainTab = widget.location == '/explore' ||
        widget.location == '/profile' ||
        widget.location == '/';

    if (!isMainTab) {
      return Scaffold(
        backgroundColor: kugo.bg,
        body: widget.child,
      );
    }

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
        ],
      ),
      bottomNavigationBar: _DockNavBar(
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
      ),
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
