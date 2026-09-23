import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/mappers.dart';
import '../../core/models/track.dart';

class AlbumDetail {
  const AlbumDetail({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.artist = '',
    this.publishTime = '',
    this.intro = '',
    this.songs = const [],
  });

  final String id;
  final String name;
  final String coverUrl;
  final String artist;
  final String publishTime;
  final String intro;
  final List<Track> songs;
}

/// 歌曲排序：接口侧 `sort=hot|new`。
enum ArtistSongSort {
  hot('hot', '热门'),
  newest('new', '最新');

  const ArtistSongSort(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.intro = '',
    this.fansLabel = '',
    this.birthday = '',
    this.songCount = 0,
    this.albumCount = 0,
    this.mvCount = 0,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String intro;
  final String fansLabel;
  final String birthday;
  final int songCount;
  final int albumCount;
  final int mvCount;
  final List<Track> songs;
}

class ArtistSongsPage {
  const ArtistSongsPage({
    this.songs = const [],
    this.total = 0,
    this.hasMore = false,
  });

  final List<Track> songs;
  final int total;
  final bool hasMore;
}

class CatalogRepository {
  CatalogRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  Future<AlbumDetail?> fetchAlbum(String albumId) async {
    final id = albumId.trim();
    if (id.isEmpty) return null;
    try {
      final infoUrl = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.albumInfo, {
        'albumid': id,
        'format': 'json',
      });
      final infoData = await _client.getJson(infoUrl);
      final info = _asMap(infoData);
      final data = _asMap(info?['data']) ?? info;

      final name = _s(data?['albumname'], _s(data?['name'], '专辑'));
      final coverRaw = _s(data?['cover'], _s(data?['imgurl'], id));
      final cover = normalizeCoverUrl(coverRaw.isEmpty ? id : coverRaw);
      final artist = _s(data?['singername'], _s(data?['author'], ''));
      final publish = _s(data?['publish_time'], _s(data?['publishtime']));
      final intro = _s(data?['intro'], _s(data?['description']));

      // songs may be nested under data.info or data.list
      var songsNode = info?['list'];
      if (songsNode is! List) songsNode = data?['list'];
      if (songsNode is! List) songsNode = data?['info'];
      final songs = <Track>[];
      if (songsNode is List) {
        for (final item in songsNode) {
          if (item is! Map) continue;
          songs.add(mapMobileSearchSong(Map<String, dynamic>.from(item)));
        }
      }

      // Fallback: album songs endpoint
      if (songs.isEmpty) {
        final songsUrl = buildUrl(
          KugoEndpoints.mobileCdn,
          KugoEndpoints.albumSongs,
          {'albumid': id, 'page': 1, 'pagesize': 100, 'format': 'json'},
        );
        final songsData = await _client.getJson(songsUrl);
        final songsMap = _asMap(songsData);
        final list = songsMap?['info'] ?? songsMap?['data'];
        final listNode = list is Map ? list['info'] : list;
        if (listNode is List) {
          for (final item in listNode) {
            if (item is! Map) continue;
            songs.add(mapMobileSearchSong(Map<String, dynamic>.from(item)));
          }
        }
      }

      return AlbumDetail(
        id: id,
        name: name,
        coverUrl: cover,
        artist: artist,
        publishTime: publish,
        intro: intro,
        songs: songs,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ArtistDetail?> fetchArtist(String singerId) async {
    final id = singerId.trim();
    if (id.isEmpty) return null;
    try {
      final infoUrl = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.singerInfo, {
        'singerid': id,
        'format': 'json',
      });
      final infoData = await _client.getJson(infoUrl);
      final info = _asMap(infoData);
      final data = _asMap(info?['data']) ?? info;

      final name = _s(data?['singername'], _s(data?['name'], '歌手'));
      final avatarRaw = _s(
        data?['avatar'],
        _s(data?['imgurl'], _s(data?['pic'], _s(data?['sizable_avatar'], id))),
      );
      final avatar = normalizeCoverUrl(avatarRaw.isEmpty ? id : avatarRaw);
      final intro = _s(data?['intro'], _s(data?['description'], _s(data?['info'])));
      final fans = _i2(data?['fans_count'], data?['fans']);
      final birthday = _s(
        data?['birthday'],
        _s(data?['birth'], _s(data?['birthday_str'])),
      );
      final songCount = _i2(data?['songcount'], data?['song_count']);
      final albumCount = _i2(data?['albumcount'], data?['album_count']);
      final mvCount = _i2(data?['mvcount'], data?['mv_count']);

      // Songs load separately via [fetchArtistSongs] so the page can paginate.
      return ArtistDetail(
        id: id,
        name: name,
        avatarUrl: avatar,
        intro: intro,
        fansLabel: fans > 0 ? formatCount(fans) : '',
        birthday: birthday,
        songCount: songCount,
        albumCount: albumCount,
        mvCount: mvCount,
        songs: const [],
      );
    } catch (_) {
      return null;
    }
  }

  /// 歌手单曲分页。`sort`：`hot` 热门 / `new` 最新。
  Future<ArtistSongsPage> fetchArtistSongs(
    String singerId, {
    int page = 1,
    int pageSize = 50,
    ArtistSongSort sort = ArtistSongSort.hot,
  }) async {
    final id = singerId.trim();
    if (id.isEmpty) return const ArtistSongsPage();
    try {
      final songsUrl = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.singerSong, {
        'singerid': id,
        'page': page,
        'pagesize': pageSize,
        'sort': sort.apiValue,
        'format': 'json',
      });
      final songsData = await _client.getJson(songsUrl);
      final songsMap = _asMap(songsData);
      final data = _asMap(songsMap?['data']);
      final listNode = songsMap?['info'] ?? data?['info'] ?? songsMap?['data'];
      final rawList = listNode is Map ? (listNode['info'] ?? listNode['list']) : listNode;

      final songs = <Track>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is! Map) continue;
          songs.add(mapMobileSearchSong(Map<String, dynamic>.from(item)));
        }
      }

      final total = _i2(songsMap?['total'], data?['total']);
      final resolvedTotal = total > 0 ? total : songs.length;
      final hasMore = songs.length >= pageSize &&
          (total <= 0 ? songs.isNotEmpty : songs.length * page < total);

      return ArtistSongsPage(
        songs: songs,
        total: resolvedTotal,
        hasMore: hasMore,
      );
    } catch (_) {
      return const ArtistSongsPage();
    }
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  String _s(Object? a, [Object? b]) {
    for (final v in [a, b]) {
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty && t != 'null') return t;
    }
    return '';
  }

  int _i(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(_s(v)) ?? 0;
  }

  int _i2(Object? a, Object? b) {
    final x = _i(a);
    return x != 0 ? x : _i(b);
  }
}

final catalogRepository = CatalogRepository();
