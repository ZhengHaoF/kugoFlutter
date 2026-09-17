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

class ArtistDetail {
  const ArtistDetail({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.intro = '',
    this.fansLabel = '',
    this.songs = const [],
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String intro;
  final String fansLabel;
  final List<Track> songs;
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
      final cover = coverRaw.startsWith('http')
          ? coverRaw
          : kugouCover(coverRaw.isEmpty ? id : coverRaw);
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
      final avatarRaw = _s(data?['avatar'], _s(data?['imgurl'], id));
      final avatar = avatarRaw.startsWith('http')
          ? avatarRaw
          : kugouCover(avatarRaw.isEmpty ? id : avatarRaw);
      final intro = _s(data?['intro'], _s(data?['description']));
      final fans = _i(data?['fans_count'] ?? data?['fans']);

      final songsUrl = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.singerSong, {
        'singerid': id,
        'page': 1,
        'pagesize': 50,
        'format': 'json',
      });
      final songsData = await _client.getJson(songsUrl);
      final songsMap = _asMap(songsData);
      final listNode = songsMap?['info'] ?? songsMap?['data'];
      final rawList = listNode is Map ? listNode['info'] : listNode;
      final songs = <Track>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is! Map) continue;
          songs.add(mapMobileSearchSong(Map<String, dynamic>.from(item)));
        }
      }

      return ArtistDetail(
        id: id,
        name: name,
        avatarUrl: avatar,
        intro: intro,
        fansLabel: fans > 0 ? formatCount(fans) : '',
        songs: songs,
      );
    } catch (_) {
      return null;
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
}

final catalogRepository = CatalogRepository();
