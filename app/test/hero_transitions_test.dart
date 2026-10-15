import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/theme/hero_tags.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/recommend/daily_recommend_page.dart';
import 'package:overtone/shared/widgets/common.dart';
import 'package:overtone/shared/widgets/cover_box.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

void main() {
  group('OvertoneHeroTags', () {
    test('generates expected namespace tags', () {
      expect(OvertoneHeroTags.playlistCover('123'), 'playlist-cover-123');
      expect(OvertoneHeroTags.albumCover('456'), 'album-cover-456');
      expect(OvertoneHeroTags.artistAvatar('789'), 'artist-avatar-789');
      expect(OvertoneHeroTags.songCover('abc'), 'song-cover-abc');
      expect(OvertoneHeroTags.rankCover('rank1'), 'rank-cover-rank1');
      expect(OvertoneHeroTags.searchBar, 'hero-search-bar');
      expect(OvertoneHeroTags.dailyRecommendBadge, 'hero-daily-recommend-badge');
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
        (w) => w is Hero && w.tag == OvertoneHeroTags.playlistCover('playlist_1'),
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
              heroTag: OvertoneHeroTags.albumCover('album_99'),
            ),
          ),
        ),
      );

      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == OvertoneHeroTags.albumCover('album_99'),
      );
      expect(heroFinder, findsOneWidget);
    });

    testWidgets('CoverHero supports placeholder child for empty art', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverHero(
              tag: OvertoneHeroTags.artistAvatar('singer_7'),
              seed: 'singer_7',
              size: 48,
              radius: 999,
              child: const Icon(Icons.person_rounded),
            ),
          ),
        ),
      );

      final heroFinder = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == OvertoneHeroTags.artistAvatar('singer_7'),
      );
      expect(heroFinder, findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('DailyRecommendPage mounts dailyRecommendBadge Hero on initial loading frame', (tester) async {
      // 日推页现按源分发：需装一个具备 DailyRecommendSource 的源才会渲染正文。
      bootstrapFakeMusicSources();
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
            w.tag == OvertoneHeroTags.dailyRecommendBadge &&
            w.flightShuttleBuilder ==
                OvertoneHeroTags.dailyRecommendBadgeFlightShuttle,
      );
      expect(heroFinder, findsOneWidget);
    });

    testWidgets('dailyRecommendBadgeFlightShuttle builds valid widget tree for push and pop', (tester) async {
      final animController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 300),
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
                    child: OvertoneHeroTags.dailyRecommendBadgeFlightShuttle(
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
                    child: OvertoneHeroTags.dailyRecommendBadgeFlightShuttle(
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
