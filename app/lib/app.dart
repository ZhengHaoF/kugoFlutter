import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_navigator.dart';
import 'core/models/track.dart' show PlaylistBrief;
import 'core/platform.dart';
import 'core/theme/kugo_theme.dart';
import 'features/album/album_detail_page.dart';
import 'features/artist/artist_detail_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/netease_login_page.dart';
import 'features/discovery/discovery_page.dart';
import 'features/explore/explore_page.dart';
import 'features/fm/fm_page.dart';
import 'features/history/history_page.dart';
import 'features/likes/likes_page.dart';
import 'features/player/full_player_page.dart';
import 'features/playlist/playlist_detail_page.dart';
import 'features/profile/profile_detail_page.dart';
import 'features/profile/profile_page.dart';
import 'features/rank/rank_list_page.dart';
import 'features/recommend/daily_recommend_page.dart';
import 'features/recommend/recommend_hub_page.dart';
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
    navigatorKey: kugoNavigatorKey,
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
        path: '/login',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: LoginPage(),
        ),
      ),
      GoRoute(
        path: '/netease-login',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: NeteaseLoginPage(),
        ),
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
              GoRoute(
                path: '/daily',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: DailyRecommendPage()),
              ),
              GoRoute(
                path: '/discovery',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: DiscoveryPage()),
              ),
              GoRoute(
                path: '/ranks',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: RankListPage()),
              ),
              // Desktop-first Personal FM shell. Android discover/profile
              // entries still start the session and open the player instead.
              GoRoute(
                path: '/fm',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: FmPage()),
              ),
              GoRoute(
                path: '/rank/:id',
                pageBuilder: (context, state) => MaterialPage(
                  child: PlaylistDetailPage(
                    id: state.pathParameters['id'] ?? '',
                    isRank: true,
                    initialBrief: state.extra is PlaylistBrief
                        ? state.extra as PlaylistBrief
                        : null,
                  ),
                ),
              ),
              GoRoute(
                path: '/playlist/:id',
                pageBuilder: (context, state) {
                  final isRankQuery = state.uri.queryParameters['type'] == 'rank' ||
                      state.uri.queryParameters['isRank'] == 'true';
                  final initialBrief = state.extra is PlaylistBrief
                      ? state.extra as PlaylistBrief
                      : null;
                  final isRank = isRankQuery || (initialBrief?.isRank ?? false);
                  return MaterialPage(
                    child: PlaylistDetailPage(
                      id: state.pathParameters['id'] ?? '',
                      initialBrief: initialBrief,
                      isRank: isRank,
                    ),
                  );
                },
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
                path: '/recommend',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: RecommendHubPage()),
              ),
              GoRoute(
                path: '/search',
                pageBuilder: (context, state) =>
                    MaterialPage(child: const SearchPage()),
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
              ),
              // EchoMusic 风格「个人中心」独立内容页（身份/等级/档案/会员）。
              GoRoute(
                path: '/profile/detail',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: ProfileDetailPage()),
              ),
              GoRoute(
                path: '/history',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: HistoryPage()),
              ),
              GoRoute(
                path: '/likes',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: LikesPage()),
              ),
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    const MaterialPage(child: SettingsPage()),
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
        final content = child ?? const SizedBox.shrink();
        if (isDesktopPlatform) {
          return ExcludeSemantics(child: content);
        }
        return content;
      },
    );
  }
}
