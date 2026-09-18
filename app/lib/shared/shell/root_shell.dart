import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/mini_player_bar.dart';

/// Bottom tabs with macOS Dock-style icon magnify/bounce and a light
/// Spaces-like content transition. Router (IndexedStack) is untouched.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  int _prevIndex = 0;

  static const _tabs = [
    (Icons.home_outlined, Icons.home_rounded, '首页'),
    (Icons.explore_outlined, Icons.explore_rounded, '发现'),
    (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
  ];

  int _indexOf(String location) => switch (location) {
        _ when location.startsWith('/explore') => 1,
        _ when location.startsWith('/profile') => 2,
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
    final index = _indexOf(widget.location);
    // easeOutBack — light Dock bounce without looking springy-cheap.
    final bounceT = CurvedAnimation(
      parent: _bounce,
      curve: Curves.easeOutBack,
    );

    return Scaffold(
      backgroundColor: KugoColors.bg,
      body: Column(
        children: [
          Expanded(
            child: _TabTransition(
              index: index,
              prevIndex: _prevIndex,
              child: widget.child,
            ),
          ),
          const MiniPlayerBar(),
        ],
      ),
      bottomNavigationBar: _DockNavBar(
        index: index,
        bounce: bounceT,
        tabs: _tabs,
        onTap: (i) {
          switch (i) {
            case 0:
              _goTo(0, '/home');
            case 1:
              _goTo(1, '/explore');
            case 2:
              _goTo(2, '/profile');
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
    return Container(
      color: KugoColors.bg,
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
                    color: selected
                        ? KugoColors.primary
                        : KugoColors.textTertiary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Dock indicator dot
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: selected ? 1 : 0,
              child: Transform.scale(
                scale: selected ? (0.85 + 0.25 * (scale - 1.0).clamp(0, 0.5)) : 0.6,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: KugoColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: KugoTypography.caption.copyWith(
                fontSize: 10,
                height: 1.1,
                color: selected
                    ? KugoColors.primary
                    : KugoColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
