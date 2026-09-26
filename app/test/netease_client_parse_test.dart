import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/api/netease/netease_failures.dart';
import 'package:kugo/core/api/netease/netease_mappers.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/sources/netease/netease_source.dart';

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

  group('G11 榜单列表（toplist/detail）', () {
    test('mapNeteaseToplistBoards：只取 id/name/封面，跳过无 id 节点', () {
      // 实测（2026-09-26）每张榜另带整榜 `tracks`，这里不解析（曲目走 G10）。
      const raw = '''
      {"code":200,"list":[
        {"id":19723756,"name":"飙升榜","coverImgUrl":"http://p1.music.126.net/a.jpg",
         "trackCount":100,"tracks":[{"id":1,"name":"x"}]},
        {"name":"无 id 的坏节点","coverImgUrl":"https://p1.music.126.net/b.jpg"}
      ]}
      ''';
      final boards = mapNeteaseToplistBoards(raw);
      expect(boards, hasLength(1));
      expect(boards.single.id, '19723756');
      expect(boards.single.name, '飙升榜');
      // http:// 统一升级 https，避免明文封面被平台拦。
      expect(boards.single.coverUrl, 'https://p1.music.126.net/a.jpg');
    });

    test('mapNeteaseToplistBoards：无 list 时返回空', () {
      expect(mapNeteaseToplistBoards('{"code":200}'), isEmpty);
    });

    test('boardsFromWhitelist：按白名单顺序保留主流榜，剔除活动/车友榜', () {
      final boards = NeteaseSource.boardsFromWhitelist([
        // 故意乱序 + 夹带白名单外的活动/车友榜
        (id: '3778678', name: '热歌榜', coverUrl: 'https://c/hot.jpg'),
        (id: '12911403728', name: '音乐合伙人推荐榜', coverUrl: 'https://c/x.jpg'),
        (id: '8703179781', name: '特斯拉车友爱听榜', coverUrl: 'https://c/y.jpg'),
        (id: '19723756', name: '飙升榜', coverUrl: 'https://c/up.jpg'),
      ]);
      expect(boards, hasLength(NeteaseSource.boardWhitelist.length));
      // 顺序以白名单为准，与接口返回顺序无关
      expect(boards.first.id, '19723756');
      expect(boards.first.name, '飙升榜');
      expect(boards.first.coverUrl, 'https://c/up.jpg');
      // 白名单外的不出现
      expect(boards.any((b) => b.name.contains('合伙人')), isFalse);
      expect(boards.any((b) => b.name.contains('车友')), isFalse);
      // 未命中的用内置名兜底、封面留空（UI 出占位图）
      expect(boards[1].id, '3779629');
      expect(boards[1].name, '新歌榜');
      expect(boards[1].coverUrl, isEmpty);
      // 第 4 位是热歌榜：首页「今日热歌」按名字含「热歌」命中它
      expect(boards[3].id, '3778678');
      expect(boards[3].coverUrl, 'https://c/hot.jpg');
      // 统一标记：详情页据此带 ?src=netease 取数，弹窗按 rankTypeName 分组
      expect(boards.every((b) => b.isRank), isTrue);
      expect(boards.every((b) => b.platform == MusicPlatform.netease), isTrue);
      expect(boards.every((b) => b.rankTypeName == '网易官方榜'), isTrue);
    });

    test('boardsFromWhitelist：G11 不可用时退回内置名（封面空）', () {
      final boards = NeteaseSource.boardsFromWhitelist(const []);
      expect(boards, hasLength(NeteaseSource.boardWhitelist.length));
      expect(
        boards.map((b) => b.name).toList(),
        NeteaseSource.boardWhitelist.map((b) => b.name).toList(),
      );
      expect(boards.every((b) => b.coverUrl.isEmpty), isTrue);
    });
  });

  group('G13 歌手列表入参（artist/list）', () {
    test('initial 字母转大写 ASCII 码（a→65 / z→90 / A→65）', () {
      // 服务端要数字：传字符 'a' 会回 code=400（2026-09-26 实测）
      expect(NeteaseClient.artistListParams(
        type: '-1', area: '7', initial: 'a', limit: 5, offset: 0,
      )['initial'], '65');
      expect(NeteaseClient.artistListParams(
        type: '-1', area: '7', initial: 'z', limit: 5, offset: 0,
      )['initial'], '90');
      expect(NeteaseClient.artistListParams(
        type: '-1', area: '7', initial: 'A', limit: 5, offset: 0,
      )['initial'], '65');
    });

    test('initial 空串省略字段；纯数字原样透传', () {
      final empty = NeteaseClient.artistListParams(
        type: '-1', area: '-1', initial: '', limit: 30, offset: 0,
      );
      expect(empty.containsKey('initial'), isFalse);
      // 服务端约定的「热门」= -1，须原样传而非转码
      expect(NeteaseClient.artistListParams(
        type: '-1', area: '-1', initial: '-1', limit: 30, offset: 0,
      )['initial'], '-1');
    });

    test('必带 total=true（少了会退化为忽略筛选的旧路由）', () {
      final p = NeteaseClient.artistListParams(
        type: '2', area: '96', initial: 'z', limit: 30, offset: 0,
      );
      expect(p['total'], 'true');
      expect(p['type'], '2');
      expect(p['area'], '96');
      expect(p['limit'], '30');
      expect(p['offset'], '0');
    });
  });

  group('G12 新碟 / G13 歌手列表映射', () {
    test('mapNeteaseNewAlbums：顶层 albums[]，节点只有 picId 时拼 CDN 封面', () {
      // 实测（2026-09-26）：新碟节点无 picUrl，只有 picId → 必须拼直链。
      const raw = '''
      {"code":200,"albums":[
        {"id":1,"name":"神的游戏","picId":109951167805012,
         "artists":[{"name":"张悬"}],"size":9},
        {"name":"无 id 的坏节点"}
      ]}
      ''';
      final albums = mapNeteaseNewAlbums(raw);
      expect(albums, hasLength(1));
      expect(albums.single.id, '1');
      expect(albums.single.name, '神的游戏');
      expect(albums.single.artist, '张悬');
      expect(albums.single.trackCount, 9);
      expect(albums.single.platform, MusicPlatform.netease);
      expect(albums.single.coverUrl, startsWith('https://p3.music.126.net/'));
    });

    test('mapNeteaseNewAlbums：data.albums[] 同样可解析；有 picUrl 时优先', () {
      const raw = '''
      {"code":200,"data":{"albums":[
        {"id":2,"name":"叶惠美","picUrl":"http://p1.music.126.net/y.jpg"}
      ]}}
      ''';
      final albums = mapNeteaseNewAlbums(raw);
      expect(albums.single.name, '叶惠美');
      // http 统一升级 https
      expect(albums.single.coverUrl, 'https://p1.music.126.net/y.jpg');
    });

    test('mapNeteaseNewAlbums：无 albums 返回空', () {
      expect(mapNeteaseNewAlbums('{"code":200}'), isEmpty);
    });

    test('mapNeteaseArtistList：顶层 artists[]，头像走 img1v1Url', () {
      const raw = '''
      {"code":200,"artists":[
        {"id":6452,"name":"周杰伦","img1v1Url":"http://p1.music.126.net/a.jpg",
         "musicSize":568,"fansCount":123456,"alias":["Jay"]},
        {"name":"无 id 的坏节点"}
      ]}
      ''';
      final artists = mapNeteaseArtistList(raw);
      expect(artists, hasLength(1));
      expect(artists.single.id, '6452');
      expect(artists.single.name, '周杰伦');
      expect(artists.single.songCount, 568);
      expect(artists.single.fansCount, 123456);
      expect(artists.single.sourceDesc, 'Jay');
      expect(artists.single.avatarUrl, 'https://p1.music.126.net/a.jpg');
      expect(artists.single.platform, MusicPlatform.netease);
    });

    test('mapNeteaseArtistList：无 artists 返回空', () {
      expect(mapNeteaseArtistList('{"code":200}'), isEmpty);
    });
  });
}
