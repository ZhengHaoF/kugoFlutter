import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/shared/widgets/common.dart';

void main() {
  group('mapMobileSearchSong artistId', () {
    test('reads singers[].id from search payload', () {
      final track = mapMobileSearchSong({
        'hash': 'abc',
        'songname': '晴天',
        'singers': [
          {'id': 3520, 'name': '周杰伦'},
        ],
      });
      expect(track.artistId, '3520');
      expect(track.hasArtistId, isTrue);
    });

    test('falls back to singerid / AuthorId / author_id', () {
      expect(
        mapMobileSearchSong({'hash': 'a', 'singerid': 42}).artistId,
        '42',
      );
      expect(
        mapMobileSearchSong({'hash': 'a', 'AuthorId': 43}).artistId,
        '43',
      );
      expect(
        mapMobileSearchSong({'hash': 'a', 'author_id': 44}).artistId,
        '44',
      );
    });

    test('is empty when payload carries no id (never fabricates one)', () {
      final track = mapMobileSearchSong({
        'hash': 'abc',
        'filename': '周杰伦 - 晴天',
      });
      expect(track.artistId, isEmpty);
      expect(track.hasArtistId, isFalse);
    });
  });

  group('mapMobileSearchSong filename fallback', () {
    test('splits "artist - title" when songname/singername are absent', () {
      // This is the real `special/song` shape: no songname, no singername.
      final track = mapMobileSearchSong({
        'hash': 'B63962001E20B7C0E6BD79C5CDF26E6B',
        'filename': '周杰伦 - 晴天',
        'duration': 269,
      });
      expect(track.name, '晴天');
      expect(track.artist, '周杰伦');
      expect(track.hash, 'b63962001e20b7c0e6bd79c5cdf26e6b');
    });

    test('keeps a title that contains no separator intact', () {
      final track = mapMobileSearchSong({
        'hash': 'abc',
        'filename': '纯音乐',
      });
      expect(track.name, '纯音乐');
      // No separator → no artist guess, falls back to the placeholder.
      expect(track.artist, '未知歌手');
    });

    test('prefers songname/singername when present', () {
      final track = mapMobileSearchSong({
        'hash': 'abc',
        'songname': '真歌名',
        'singername': '真歌手',
        'filename': '假歌手 - 假歌名',
      });
      expect(track.name, '真歌名');
      expect(track.artist, '真歌手');
    });
  });

  group('artistTapFor', () {
    testWidgets('returns a callback when the track has an artist id',
        (tester) async {
      const track = Track(
        id: '1',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        artistId: '3520',
      );
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(artistTapFor(captured, track), isNotNull);
    });

    testWidgets('returns null without an id, so the row stays non-tappable',
        (tester) async {
      const track = Track(
        id: '1',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        // artistId intentionally omitted.
      );
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(artistTapFor(captured, track), isNull);
    });
  });

  group('Track.copyWith preserves artistId', () {
    test('carries artistId through when not overridden', () {
      const track = Track(
        id: '1',
        name: 'n',
        artist: 'a',
        album: 'al',
        coverUrl: 'u',
        durationMs: 1,
        artistId: '99',
      );
      expect(track.copyWith(name: 'other').artistId, '99');
      expect(track.copyWith(artistId: '100').artistId, '100');
    });
  });
}
