import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/data/repositories/fm_repository.dart';

/// 截取自真实 `POST /v2/personal_recommend`（登录态，2026-09-22）的最小样本。
const _fmBody = {
  'status': 1,
  'data': {
    'bi_biz': 'rcmd_pfm',
    'song_list': [
      {
        'songname': 'Houdini',
        'hash': '29B020FAE1DFE0FB2A9E4A9AC5570898',
        'hash_320': '29B020FAE1DFE0FB2A9E4A9AC5570898',
        'time_length': 205,
        'songid': 364326491,
        'singerinfo': [
          {'name': 'Dua Lipa', 'id': '198259'},
        ],
        'rec_song_info': {
          'rec_desc': '根据你的听歌口味推荐',
          'similar_desc': '高',
        },
      },
      {
        'songname': 'Lujon',
        'hash': 'AE7A8B645C3633131FD88E5FBB5440C8',
        'time_length': 168,
        'songid': 7918253,
        'singerinfo': [
          {'name': 'Henry Mancini', 'id': '119354'},
        ],
        'rec_song_info': {
          'rec_desc': '根据你的听歌口味推荐',
          'similar_desc': '高',
        },
      },
    ],
  },
};

void main() {
  test('parses a real personal_recommend payload into tracks', () {
    final repo = FmRepository();
    // ignore: invalid_use_of_visible_for_testing_member
    final page = repo.debugParseForTest(_fmBody);

    expect(page.fromServer, isTrue);
    expect(page.tracks, hasLength(2));
    expect(page.tracks[0].name, 'Houdini');
    expect(page.tracks[0].artist, 'Dua Lipa');
    // time_length 在 personal_recommend 里是秒。
    expect(page.tracks[0].durationMs, 205 * 1000);
    expect(page.tracks[0].recDesc, '根据你的听歌口味推荐');
    expect(page.tracks[1].artist, 'Henry Mancini');
  });

  test('everyday-style ms time_length is preserved', () {
    final track = mapEverydaySong({
      'songname': '测试',
      'hash': 'ABC',
      'time_length': 245000,
      'singername': '歌手',
    });
    expect(track.durationMs, 245000);
    expect(track.artist, '歌手');
  });
}
