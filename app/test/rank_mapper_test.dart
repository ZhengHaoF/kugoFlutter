import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';

void main() {
  test('rank/list item maps via mapRankBrief (rankid, not specialid)', () {
    final brief = mapRankBrief({
      'rankname': 'TOP500',
      'rankid': 8888,
      'rank_cid': 127985,
      'id': 2,
      'imgurl': 'http://imge.kugou.com/mcommon/{size}/20241219/x.png',
      'play_times': 10169437,
      'intro': '数据来源：全曲库歌曲',
    });

    expect(brief.id, '8888');
    expect(brief.name, 'TOP500');
    expect(brief.playCountLabel, '1016.9万');
    expect(brief.coverUrl, contains('imge.kugou.com'));
    expect(brief.coverUrl, isNot(contains('{size}')));
    expect(brief.isRank, isTrue);
  });

  test('rank/song item maps authors[] into artist + artistId', () {
    final track = mapMobileSearchSong({
      'hash': '86470F212F05E4F736C1B36954685338',
      'songname': '包容',
      'filename': '郑源 - 包容',
      'authors': [
        {'author_name': '郑源', 'author_id': 3538},
      ],
      'album_id': '963730',
      'album_audio_id': 32073105,
      'audio_id': 301309704,
      'duration': 263,
      'cover': 'http://imge.kugou.com/stdmusic/{size}/c.jpg',
      '320hash': '8424FCEF26A0EAF343E410197EEDCC56',
      'sqhash': '393B7399EF67202DC0ABA4C1247A09A1',
    });

    expect(track.name, '包容');
    expect(track.artist, '郑源');
    expect(track.artistId, '3538');
    expect(track.hash.toLowerCase(), '86470f212f05e4f736c1b36954685338');
    expect(track.durationMs, 263 * 1000);
  });

  test('rank/list body path is data.info — mapper accepts nested rankname', () {
    // Simulate repository: only data.info items reach mapRankBrief.
    final map = <String, dynamic>{
      'data': {
        'info': [
          {'rankname': '飙升榜', 'rankid': 6666, 'play_times': 20000},
        ],
      },
    };
    final data = map['data'] as Map<String, dynamic>;
    final list = data['info'] as List;
    final brief = mapRankBrief(Map<String, dynamic>.from(list.first as Map));
    expect(brief.id, '6666');
    expect(brief.name, '飙升榜');
  });
}
