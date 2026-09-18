import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';

void main() {
  group('extractEverydayList', () {
    test('reads data.list', () {
      final list = extractEverydayList({
        'status': 1,
        'data': {
          'list': [
            {'hash': 'a'},
          ],
        },
      });
      expect(list, hasLength(1));
    });

    test('reads data.songs.list', () {
      final list = extractEverydayList({
        'data': {
          'songs': {
            'list': [
              {'hash': 'a'},
              {'hash': 'b'},
            ],
          },
        },
      });
      expect(list, hasLength(2));
    });

    test('reads top-level special_list', () {
      final list = extractEverydayList({
        'special_list': [
          {'hash': 'x'},
        ],
      });
      expect(list, hasLength(1));
    });
  });

  group('mapEverydaySong', () {
    test('maps flat top-level song', () {
      final t = mapEverydaySong({
        'hash': 'ABCDEF',
        'songname': '测试歌',
        'singername': '歌手',
        'duration': 200,
        'album_id': 12,
        'mixsongid': 345,
        'album_name': '专辑',
      });
      expect(t.hash, 'abcdef');
      expect(t.name, '测试歌');
      expect(t.artist, '歌手');
      expect(t.durationMs, 200000);
      expect(t.mixSongId, '345');
      expect(t.albumId, '12');
    });

    test('maps nested base/audio_info/rec_song_info', () {
      final t = mapEverydaySong({
        'base': {
          'mixsongid': 999,
          'album_audio_id': 888,
        },
        'audio_info': {
          'hash': 'deadbeef',
          'filename': '歌手 - 歌名',
        },
        'rec_song_info': {
          'audio_name': '歌名',
          'author_name': '歌手甲',
        },
        'time_length': 245000,
        'album_info': {'album_name': '精选', 'album_id': 7},
      });
      expect(t.hash, 'deadbeef');
      expect(t.name, '歌名');
      expect(t.artist, '歌手甲');
      expect(t.durationMs, 245000);
      expect(t.mixSongId, '999');
      expect(t.album, '精选');
    });

    test('maps singer list', () {
      final t = mapEverydaySong({
        'hash': 'h1',
        'name': '合唱',
        'singer': [
          {'name': 'A'},
          {'name': 'B'},
        ],
        'duration': 180,
      });
      expect(t.artist, 'A/B');
      expect(t.durationMs, 180000);
    });
  });
}
