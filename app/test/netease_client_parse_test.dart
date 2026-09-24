import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_failures.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/source/music_source.dart';

void main() {
  test('parseProbeSongs reads ar/al/dt', () {
    final raw = '''
    {"code":200,"result":{"songs":[
      {"id":186016,"name":"晴天","dt":269000,
       "ar":[{"name":"周杰伦"}],
       "al":{"name":"叶惠美","picUrl":"https://p1.music.126.net/x.jpg"}}
    ]}}
    ''';
    final songs = parseProbeSongs(raw);
    expect(songs, hasLength(1));
    expect(songs.first.id, 186016);
    expect(songs.first.name, '晴天');
    expect(songs.first.artists, '周杰伦');
    expect(songs.first.album, '叶惠美');
  });

  test('mapNeteaseSearchSongs 旧口形态：封面从 album.picId 拼出', () {
    // 实测（2026-09-25）旧搜索口 search/get 的曲目形态：`album` 只有
    // picId（无 picUrl），歌手在 `artists`、时长在 `duration`。
    const raw = '''
    {"code":200,"result":{"songs":[
      {"id":509781655,"name":"想你就写信 (Live)","duration":238698,
       "artists":[{"id":6452,"name":"周杰伦"}],
       "album":{"id":1,"name":"中国新歌声第二季 第13期",
                "picId":109951163038292176}}
    ]}}
    ''';
    final page = mapNeteaseSearchSongs(raw);
    expect(page.items, hasLength(1));
    final t = page.items.single;
    expect(t.artist, '周杰伦');
    expect(t.album, '中国新歌声第二季 第13期');
    expect(t.durationMs, 238698);
    expect(
      t.coverUrl,
      'https://p3.music.126.net/yD9vbpuILH-tqNRIaP640g==/'
      '109951163038292176.jpg?param=300y300',
    );
  });

  test('mapNeteaseSearchSongs 新口形态：优先用 al.picUrl', () {
    const raw = '''
    {"code":200,"result":{"songs":[
      {"id":186016,"name":"晴天","dt":269000,
       "ar":[{"name":"周杰伦"}],
       "al":{"name":"叶惠美","picUrl":"http://p1.music.126.net/x.jpg",
             "picId":109951163038292176}}
    ]}}
    ''';
    // picUrl 存在时不走 picId 回退（且 http → https）。
    expect(
      mapNeteaseSearchSongs(raw).items.single.coverUrl,
      'https://p1.music.126.net/x.jpg',
    );
  });

  test('parseProbePlayUrl success', () {
    final raw = '''
    {"code":200,"data":[{"url":"https://m701.music.126.net/a.mp3",
      "level":"exhigh","type":"mp3","size":100,"fee":0,"code":200}]}
    ''';
    final play = parseProbePlayUrl(raw);
    expect(play.url, contains('mp3'));
    expect(play.level, 'exhigh');
    expect(play.isPreviewClip, isFalse);
  });

  test('parseProbePlayUrl throws LoginRequired on 301', () {
    expect(
      () => parseProbePlayUrl('{"code":301}'),
      throwsA(isA<LoginRequired>()),
    );
  });

  test('parseProbePlayUrl missing url maps to NoPermission', () {
    final raw = '{"code":200,"data":[{"url":null,"fee":1,"code":404}]}';
    expect(
      () => parseProbePlayUrl(raw),
      throwsA(isA<NoPermission>()),
    );
  });

  test('parseProbePlayUrl marks preview clip', () {
    final raw = '''
    {"code":200,"data":[{"url":"https://x/a.mp3","level":"standard",
      "fee":1,"code":200,"freeTrialInfo":{"start":0,"end":30}}]}
    ''';
    expect(parseProbePlayUrl(raw).isPreviewClip, isTrue);
  });

  test('parseProbeLyric fields', () {
    final raw = '''
    {"code":200,
     "lrc":{"lyric":"[00:00.00]hello"},
     "yrc":{"lyric":"y"},
     "tlyric":{"lyric":"t"},
     "romalrc":{"lyric":"r"}}
    ''';
    final l = parseProbeLyric(raw);
    expect(l.lrc, contains('hello'));
    expect(l.yrc, 'y');
    expect(l.tlyric, 't');
    expect(l.romalrc, 'r');
  });

  test('mapNeteaseCode distinguishes 301 / rate limit', () {
    expect(mapNeteaseCode(301), isA<LoginRequired>());
    expect(mapNeteaseCode(-460), isA<RateLimited>());
    expect(mapNeteaseCode(404), isA<NotFound>());
  });
}
