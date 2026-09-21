import 'dart:ui' show lerpDouble;

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

  /// Smooth shuttle for the daily recommend badge morphing between compact (Explore / Hub)
  /// and expanded (DailyRecommendPage header) states.
  static Widget dailyRecommendBadgeFlightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final kugo = KugoTheme.of(flightContext);
    final isPush = flightDirection == HeroFlightDirection.push;
    final now = DateTime.now();
    final dayStr = now.day.toString();
    final monthStr = '${now.month}月';

    final compactGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        kugo.primary,
        Color.lerp(kugo.primary, kugo.secondary, 0.35)!,
      ],
    );
    final largeGrad = kugo.accentGradient;

    final fromGrad = isPush ? compactGrad : largeGrad;
    final toGrad = isPush ? largeGrad : compactGrad;

    final fromRadius = isPush ? 12.0 : KugoRadius.card;
    final toRadius = isPush ? KugoRadius.card : 12.0;

    final fromShadowAlpha = isPush ? 0.30 : 0.0;
    final toShadowAlpha = isPush ? 0.0 : 0.30;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final rawValue = animation.value;
        // In Flutter, pop runs animation from 1.0 down to 0.0.
        // Normalize progress so 0.0 is flight takeoff and 1.0 is flight landing.
        final progress = isPush ? rawValue : (1.0 - rawValue);
        final t = Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));

        final radius = lerpDouble(fromRadius, toRadius, t) ?? 12.0;
        final currentGrad = LinearGradient.lerp(fromGrad, toGrad, t) ?? fromGrad;
        final shadowAlpha = lerpDouble(fromShadowAlpha, toShadowAlpha, t) ?? 0.0;

        // Crossfade between single day and month+day
        final sourceOpacity = (1.0 - progress * 2.5).clamp(0.0, 1.0);
        final destOpacity = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);

        final compactOpacity = isPush ? sourceOpacity : destOpacity;
        final largeOpacity = isPush ? destOpacity : sourceOpacity;

        return Material(
          type: MaterialType.transparency,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: currentGrad,
              boxShadow: shadowAlpha > 0.01
                  ? [
                      BoxShadow(
                        color: kugo.primary.withValues(alpha: shadowAlpha),
                        blurRadius: 10 * (shadowAlpha / 0.30),
                        offset: Offset(0, 4 * (shadowAlpha / 0.30)),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Compact badge text (day only)
                if (compactOpacity > 0.01)
                  Opacity(
                    opacity: compactOpacity,
                    child: Center(
                      child: Text(
                        dayStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),

                // 2. Large badge text (month + day)
                if (largeOpacity > 0.01)
                  Opacity(
                    opacity: largeOpacity,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            monthStr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            dayStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
