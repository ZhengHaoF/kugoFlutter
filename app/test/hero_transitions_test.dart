import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/theme/hero_tags.dart';
import 'package:kugo/shared/widgets/common.dart';

void main() {
  group('KugoHeroTags', () {
    test('generates expected namespace tags', () {
      expect(KugoHeroTags.playlistCover('123'), 'playlist-cover-123');
      expect(KugoHeroTags.albumCover('456'), 'album-cover-456');
      expect(KugoHeroTags.artistAvatar('789'), 'artist-avatar-789');
      expect(KugoHeroTags.songCover('abc'), 'song-cover-abc');
      expect(KugoHeroTags.rankCover('rank1'), 'rank-cover-rank1');
      expect(KugoHeroTags.searchBar, 'hero-search-bar');
      expect(KugoHeroTags.dailyRecommendBadge, 'hero-daily-recommend-badge');
    });
  });

  group('Hero widget integration', () {
    testWidgets('PlaylistCard wraps cover with playlistCover Hero', (tester) async {
      const brief = PlaylistBrief(
        id: 'playlist_1',
        name: '热门精选',
        coverUrl: 'http://cover.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaylistCard(
              playlist: brief,
              width: 120,
            ),
          ),
        ),
      );

      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == KugoHeroTags.playlistCover('playlist_1'),
      );
      expect(heroFinder, findsOneWidget);
    });

    testWidgets('SearchResultRow wraps cover with provided heroTag', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchResultRow(
              imageSeed: 'http://album.jpg',
              title: '夜的第七章',
              heroTag: KugoHeroTags.albumCover('album_99'),
            ),
          ),
        ),
      );

      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == KugoHeroTags.albumCover('album_99'),
      );
      expect(heroFinder, findsOneWidget);
    });
  });
}
