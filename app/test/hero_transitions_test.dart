import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/theme/hero_tags.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/recommend/daily_recommend_page.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:kugo/shared/widgets/cover_box.dart';

import 'fakes/fake_audio_player.dart';

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

    testWidgets('CoverHero supports placeholder child for empty art', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverHero(
              tag: KugoHeroTags.artistAvatar('singer_7'),
              seed: 'singer_7',
              size: 48,
              radius: 999,
              child: const Icon(Icons.person_rounded),
            ),
          ),
        ),
      );

      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == KugoHeroTags.artistAvatar('singer_7'),
      );
      expect(heroFinder, findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('DailyRecommendPage mounts dailyRecommendBadge Hero on initial loading frame', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider
                .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
          ],
          child: const MaterialApp(
            home: DailyRecommendPage(),
          ),
        ),
      );
      // Immediately verify before any network or timer resolves
      final heroFinder = find.byWidgetPredicate(
        (w) =>
            w is Hero &&
            w.tag == KugoHeroTags.dailyRecommendBadge &&
            w.flightShuttleBuilder ==
                KugoHeroTags.dailyRecommendBadgeFlightShuttle,
      );
      expect(heroFinder, findsOneWidget);
    });

    testWidgets('dailyRecommendBadgeFlightShuttle builds valid widget tree for push and pop', (tester) async {
      final animController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
      );

      final dummyFromHero = Hero(
        tag: KugoHeroTags.dailyRecommendBadge,
        child: const SizedBox(width: 44, height: 44),
      );
      final dummyToHero = Hero(
        tag: KugoHeroTags.dailyRecommendBadge,
        child: const SizedBox(width: 64, height: 64),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Column(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: KugoHeroTags.dailyRecommendBadgeFlightShuttle(
                      context,
                      animController,
                      HeroFlightDirection.push,
                      context,
                      context,
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: KugoHeroTags.dailyRecommendBadgeFlightShuttle(
                      context,
                      animController,
                      HeroFlightDirection.pop,
                      context,
                      context,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.byType(Material), findsWidgets);
      animController.dispose();
    });
  });
}
