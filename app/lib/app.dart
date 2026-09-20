import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/kugo_theme.dart';
import 'features/album/album_detail_page.dart';
import 'features/artist/artist_detail_page.dart';
import 'features/auth/login_page.dart';
import 'features/explore/explore_page.dart';
import 'features/history/history_page.dart';
import 'features/likes/likes_page.dart';
import 'features/player/full_player_page.dart';
import 'features/playlist/playlist_detail_page.dart';
import 'features/profile/profile_page.dart';
import 'features/rank/rank_list_page.dart';
import 'features/recommend/daily_recommend_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_page.dart';
import 'features/song/song_detail_page.dart';
import 'shared/shell/root_shell.dart';

/// Center scale + fade for lyrics route; Hero still runs on cover tags.
Widget _lyricsRouteTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
      alignment: Alignment.center,
      child: child,
    ),
  );
}

final _routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/explore',
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/home' || path == '/') return '/explore';
      return null;
    },
    routes: [
      GoRoute(
        path: '/player',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: FullPlayerPage(),
        ),
      ),
      GoRoute(
        path: '/player/lyrics',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: _lyricsRouteTransition,
          child: const PlayerLyricsPage(),
        ),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (context, state) =>
            MaterialPage(child: const SearchPage()),
      ),
      GoRoute(
        path: '/playlist/:id',
        pageBuilder: (context, state) => MaterialPage(
          child: PlaylistDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/album/:id',
        pageBuilder: (context, state) => MaterialPage(
          child: AlbumDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/artist/:id',
        pageBuilder: (context, state) => MaterialPage(
          child: ArtistDetailPage(id: state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: LoginPage(),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            const MaterialPage(child: SettingsPage()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            const MaterialPage(child: HistoryPage()),
      ),
      GoRoute(
        path: '/likes',
        pageBuilder: (context, state) => const MaterialPage(child: LikesPage()),
      ),
      GoRoute(
        path: '/daily',
        pageBuilder: (context, state) =>
            const MaterialPage(child: DailyRecommendPage()),
      ),
      GoRoute(
        path: '/ranks',
        pageBuilder: (context, state) =>
            const MaterialPage(child: RankListPage()),
      ),
      GoRoute(
        path: '/song',
        pageBuilder: (context, state) {
          final q = state.uri.queryParameters;
          return MaterialPage(
            child: SongDetailPage(
              id: q['id'] ?? '',
              name: q['name'] ?? '',
              artist: q['artist'] ?? '',
              album: q['album'] ?? '',
              coverUrl: q['cover'] ?? '',
              hash: q['hash'] ?? '',
              mixSongId: q['mixSongId'] ?? '',
              durationMs: int.tryParse(q['duration'] ?? '') ?? 0,
            ),
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return RootShell(
            location: state.uri.path,
            child: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (context, state) => const ExplorePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class KugoApp extends ConsumerWidget {
  const KugoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final mode = settings.materialThemeMode;

    return MaterialApp.router(
      title: 'kugo',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildKugoTheme(Brightness.light),
      darkTheme: buildKugoTheme(Brightness.dark),
      routerConfig: router,
      builder: (context, child) {
        // Status/navigation bars follow the resolved theme, not the OS setting.
        applyKugoSystemUi(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
