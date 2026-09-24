import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_failures.dart';
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
