import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';
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
    expect(page.serverAccepted, isFalse);
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

  test('meta-only success (remain_songcnt>4) is accepted, not a load failure', () {
    // 2026-09-23 实测：remain_songcnt=25 时 data 只回会话元数据。
    const body = {
      'status': 1,
      'error_code': 0,
      'data': {
        'mode': 'normal',
        'algorithm_id': 3,
        'sync_point': 0,
        'clientver': '6.1.1',
      },
    };
    final repo = FmRepository();
    // ignore: invalid_use_of_visible_for_testing_member
    final page = repo.debugParseForTest(body);

    expect(page.tracks, isEmpty);
    expect(page.serverAccepted, isTrue);
    expect(page.fromServer, isFalse);
    expect(page.error, isEmpty, reason: '不能写成「私人FM加载失败」');
    expect(page.needLogin, isFalse);
  });

  test('empty + status=0 is still an error', () {
    const body = {
      'status': 0,
      'error_code': 200101,
      'data': '',
    };
    final repo = FmRepository();
    // ignore: invalid_use_of_visible_for_testing_member
    final page = repo.debugParseForTest(body);

    expect(page.serverAccepted, isFalse);
    expect(page.error, isNotEmpty);
  });

  group('clampRemainSongcnt', () {
    test('fresh fetch always asks for songs with 0', () {
      expect(clampRemainSongcnt(fresh: true, unplayed: 25), 0);
      expect(clampRemainSongcnt(fresh: true, unplayed: 0), 0);
      expect(clampRemainSongcnt(fresh: true, unplayed: 3), 0);
    });

    test('refill keeps real remaining but caps at 4', () {
      expect(clampRemainSongcnt(fresh: false, unplayed: 0), 0);
      expect(clampRemainSongcnt(fresh: false, unplayed: 3), 3);
      expect(clampRemainSongcnt(fresh: false, unplayed: 4), 4);
      expect(clampRemainSongcnt(fresh: false, unplayed: 5), 4);
      expect(clampRemainSongcnt(fresh: false, unplayed: 25), 4);
    });
  });
}
