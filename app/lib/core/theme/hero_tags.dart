import 'package:flutter/material.dart';

import 'kugo_theme.dart';
import 'kugo_tokens.dart';

/// Centralized Hero tags to guarantee unique namespace and avoid typos.
abstract final class KugoHeroTags {
  /// Playlist cover transition between lists/grids and detail page.
  static String playlistCover(String id) => 'playlist-cover-$id';

  /// Rank board cover transition.
  static String rankCover(String id) => 'rank-cover-$id';

  /// Album cover transition from search/track to album detail page.
  static String albumCover(String id) => 'album-cover-$id';

  /// Artist avatar transition from search/track to artist detail page.
  static String artistAvatar(String id) => 'artist-avatar-$id';

  /// Song cover transition to song detail/comments page.
  static String songCover(String id) => 'song-cover-$id';

  /// Search bar transition between Explore tab pill and SearchPage input.
  static const String searchBar = 'hero-search-bar';

  /// Daily recommend calendar badge transition across QuickEntries / Hub / Daily.
  static const String dailyRecommendBadge = 'hero-daily-recommend-badge';

  /// Smooth shuttle for the search pill morphing into the search input.
  static Widget searchBarFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final kugo = KugoTheme.of(flightContext);
    return Material(
      color: kugo.surface,
      borderRadius: BorderRadius.circular(KugoRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: kugo.textSecondary),
            const SizedBox(width: 10),
            Text(
              '搜索歌曲、歌手、专辑',
              style: kugo.caption.copyWith(
                fontSize: 14,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
