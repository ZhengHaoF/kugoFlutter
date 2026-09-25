import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_failures.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/source/music_platform.dart';
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

  group('D 详情页映射', () {
    test('mapNeteasePlaylistDetail：playlist 头 + tracks（榜单/歌单共用）', () {
      const raw = '''
      {"code":200,"playlist":{
        "id":7236957806,"name":"云音乐说唱榜",
        "coverImgUrl":"http://p1.music.126.net/x.jpg",
        "trackCount":2,"playCount":123456,"creator":{"nickname":"小明"},
        "tracks":[
          {"id":186016,"name":"晴天","dt":269000,
           "ar":[{"id":6452,"name":"周杰伦"}],
           "al":{"id":39,"name":"叶惠美","picUrl":"http://p1.music.126.net/y.jpg"}}
        ]}}
      ''';
      final detail = mapNeteasePlaylistDetail(raw);
      expect(detail, isNotNull);
      final brief = detail!.brief;
      expect(brief.id, '7236957806');
      expect(brief.name, '云音乐说唱榜');
      expect(brief.coverUrl, 'https://p1.music.126.net/x.jpg');
      expect(brief.playCountLabel, '12.3万');
      expect(brief.platform, MusicPlatform.netease);
      expect(detail.tracks, hasLength(1));
      expect(detail.tracks.single.name, '晴天');
      expect(detail.tracks.single.durationMs, 269000);
      expect(detail.tracks.single.platform, MusicPlatform.netease);
    });

    test('mapNeteasePlaylistDetail：无 playlist 返回 null', () {
      expect(mapNeteasePlaylistDetail('{"code":200}'), isNull);
    });

    test('mapNeteaseAlbumDetail：album 头 + 顶层 songs[]', () {
      const raw = '''
      {"code":200,
       "album":{"id":34,"name":"神的游戏",
         "picUrl":"http://p1.music.126.net/z.jpg",
         "artist":{"name":"张悬"},
         "publishTime":1352980800000,
         "description":"2012 年专辑"},
       "songs":[
         {"id":26020212,"name":"关于我爱你","dt":276000,
          "ar":[{"id":10559,"name":"张悬"}],
          "al":{"id":34,"name":"神的游戏","picUrl":"http://p1.music.126.net/z.jpg"}}
       ]}
      ''';
      final album = mapNeteaseAlbumDetail(raw);
      expect(album, isNotNull);
      expect(album!.id, '34');
      expect(album.name, '神的游戏');
      expect(album.coverUrl, 'https://p1.music.126.net/z.jpg');
      expect(album.artist, '张悬');
      expect(album.publishTime, '2012-11-15');
      expect(album.intro, '2012 年专辑');
      expect(album.songs, hasLength(1));
      expect(album.songs.single.artist, '张悬');
    });

    test('mapNeteaseAlbumDetail：id 非数字返回 null', () {
      const raw = '{"code":200,"album":{"id":"x"},"songs":[]}';
      expect(mapNeteaseAlbumDetail(raw), isNull);
    });

    test('mapNeteaseArtistDetail：data.artist 头部字段', () {
      const raw = '''
      {"code":200,"data":{"artist":{
        "id":6452,"name":"周杰伦",
        "avatar":"http://p1.music.126.net/a.jpg",
        "briefDesc":"华语流行男歌手",
        "musicSize":568,"albumSize":44,"mvSize":10}}}
      ''';
      final artist = mapNeteaseArtistDetail(raw);
      expect(artist, isNotNull);
      expect(artist!.id, '6452');
      expect(artist.name, '周杰伦');
      expect(artist.avatarUrl, 'https://p1.music.126.net/a.jpg');
      expect(artist.intro, '华语流行男歌手');
      expect(artist.songCount, 568);
      expect(artist.albumCount, 44);
      expect(artist.mvCount, 10);
    });

    test('mapNeteaseArtistSongs：songs + more + total 分页', () {
      const raw = '''
      {"code":200,
       "songs":[
         {"id":186016,"name":"晴天","dt":269000,
          "ar":[{"id":6452,"name":"周杰伦"}],
          "al":{"id":39,"name":"叶惠美","picUrl":"http://p1.music.126.net/y.jpg"}}
       ],
       "more":true,"total":568}
      ''';
      final page = mapNeteaseArtistSongs(raw);
      expect(page.songs, hasLength(1));
      expect(page.songs.single.artistId, '6452');
      expect(page.total, 568);
      expect(page.hasMore, isTrue);
    });
  });

  group('G 探索发现映射', () {
    test('mapNeteaseTopPlaylists：顶点 playlists[] 复用歌单 brief 映射', () {
      const raw = '''
      {"code":200,"playlists":[
        {"id":376135194,"name":"华语流行",
         "coverImgUrl":"http://p1.music.126.net/x.jpg",
         "trackCount":50,"playCount":12345,"creator":{"nickname":"小明"}}
      ]}
      ''';
      final items = mapNeteaseTopPlaylists(raw);
      expect(items, hasLength(1));
      expect(items.single.id, '376135194');
      expect(items.single.name, '华语流行');
      expect(items.single.coverUrl, 'https://p1.music.126.net/x.jpg');
      expect(items.single.trackCount, 50);
      expect(items.single.creator, '小明');
      expect(items.single.playCountLabel, isNotEmpty);
      expect(items.single.platform, MusicPlatform.netease);
    });

    test('mapNeteaseTopPlaylists：id 非数字的节点被剔除', () {
      const raw = '{"code":200,"playlists":[{"id":"x","name":"坏节点"}]}';
      expect(mapNeteaseTopPlaylists(raw), isEmpty);
    });

    test('mapNeteasePlaylistTags：tags[] 拍成单组并前置「全部」', () {
      // 网易标签一级扁平（无 son[]），id 即 cat 要传的标签名。
      const raw = '''
      {"code":200,"tags":[
        {"id":1,"name":"华语"},
        {"id":2,"name":"流行"},
        {"id":3,"name":"华语"}
      ]}
      ''';
      final groups = mapNeteasePlaylistTags(raw);
      expect(groups, hasLength(1));
      expect(groups.single.name, '推荐');
      expect(
        groups.single.child.map((t) => t.name).toList(),
        ['全部', '华语', '流行'],
      );
      expect(groups.single.child.first.id, '全部');
      expect(groups.single.child[1].id, '华语');
    });

    test('mapNeteasePlaylistTags：接口无 tags 时仍给「全部」兜底', () {
      final groups = mapNeteasePlaylistTags('{"code":200}');
      expect(groups, hasLength(1));
      expect(groups.single.child.map((t) => t.name).toList(), ['全部']);
    });

    test('mapNeteasePersonalizedNewSongs：result[].song 内层解包', () {
      const raw = '''
      {"code":200,"result":[
        {"id":0,"song":{"id":186016,"name":"晴天","dt":269000,
          "ar":[{"id":6452,"name":"周杰伦"}],
          "al":{"id":39,"name":"叶惠美","picUrl":"http://p1.music.126.net/y.jpg"}}}
      ]}
      ''';
      final songs = mapNeteasePersonalizedNewSongs(raw);
      expect(songs, hasLength(1));
      expect(songs.single.id, '186016');
      expect(songs.single.name, '晴天');
      expect(songs.single.artist, '周杰伦');
      expect(songs.single.album, '叶惠美');
      expect(songs.single.durationMs, 269000);
      expect(songs.single.platform, MusicPlatform.netease);
    });
  });
}
