import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_tokens.dart';
import '../../shared/widgets/mini_player_bar.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  int get _index => switch (location) {
        _ when location.startsWith('/explore') => 1,
        _ when location.startsWith('/profile') => 2,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          const MiniPlayerBar(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/home');
            case 1:
              context.go('/explore');
            case 2:
              context.go('/profile');
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
        selectedItemColor: KugoColors.primary,
        unselectedItemColor: KugoColors.textTertiary,
        backgroundColor: KugoColors.bg,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
