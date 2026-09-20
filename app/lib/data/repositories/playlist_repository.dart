import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/mappers.dart';
import '../../core/models/track.dart';

class PlaylistRepository {
  PlaylistRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  /// Public playlist metadata + tracks via mobile CDN.
  ///
  /// Uses the `special` endpoint family: the `playlist/*` paths are
  /// Access-Denied on this network (see [KugoEndpoints.playlistInfo]).
  /// Metadata and tracks come from two separate calls.
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylist(
    String id, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final numericId = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericId.isEmpty) return null;

    try {
      final infoUrl = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.playlistInfo,
        {'specialid': numericId, 'format': 'json'},
      );
      final infoData = await _client.getJson(infoUrl);
      final infoMap = _asMap(infoData);
      if (infoMap == null) return null;
      // `special/info` nests the payload under `data`.
      final info = _asMap(infoMap['data']) ?? infoMap;
      final brief = mapPlaylistInfo(info);

      final songsUrl = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.playlistSongs,
        {
          'specialid': numericId,
          'page': page,
          'pagesize': pageSize,
          'format': 'json',
        },
      );
      final songsData = await _client.getJson(songsUrl);
      final songsMap = _asMap(songsData);
      final dataNode = songsMap == null ? null : _asMap(songsMap['data']);
      final listNode = dataNode?['info'] ?? songsMap?['info'];

      final tracks = <Track>[];
      if (listNode is List) {
        for (final item in listNode) {
          if (item is! Map) continue;
          final track = mapMobileSearchSong(Map<String, dynamic>.from(item));
          if (track.hash.isNotEmpty || track.name.isNotEmpty) {
            tracks.add(track);
          }
        }
      }
      return (brief: brief, tracks: tracks);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  /// Square / category playlists (best-effort public).
  /// Many CDNs now return plain `Access Deny ! No Actions !` for this path.
  Future<List<PlaylistBrief>> fetchSquare({int page = 1, int pageSize = 20}) async {
    try {
      final url = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.playlistSquare,
        {'page': page, 'pagesize': pageSize, 'format': 'json'},
      );
      final data = await _client.getJson(url);
      if (data is! Map) return const [];
      final map = Map<String, dynamic>.from(data);
      final list = map['info'] ?? map['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => mapPlaylistInfo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Home hero / recommend cards: rank boards are reliably public.
  Future<List<PlaylistBrief>> fetchHomeCards({int take = 6}) async {
    final square = await fetchSquare(pageSize: take);
    if (square.isNotEmpty) return square.take(take).toList();
    final ranks = await fetchRankList();
    return ranks.take(take).toList();
  }

  Future<List<PlaylistBrief>> fetchRankList() async {
    try {
      final url = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.rankList, {
        'format': 'json',
        'plat': 0,
      });
      final data = await _client.getJson(url);
      if (data is! Map) return const [];
      final map = Map<String, dynamic>.from(data);
      // `rank/list` nests the board list under `data.info` (not root `info`).
      final dataNode = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;
      final list = dataNode['info'] ??
          dataNode['list'] ??
          map['info'] ??
          map['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => mapRankBrief(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Rank board detail: `rank/info` + `rank/song?rankid=`.
  ///
  /// Rank ids are **not** specialids — `/playlist/:id` must fall back here
  /// when `special/*` returns nothing for a rank board id.
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchRankDetail(
    String rankId, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final id = rankId.replaceAll(RegExp(r'[^0-9]'), '');
    if (id.isEmpty) return null;

    PlaylistBrief? brief;
    var tracks = const <Track>[];

    try {
      final infoUrl = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.rankInfo,
        {'rankid': id, 'plat': 0, 'format': 'json'},
      );
      final infoData = await _client.getJson(infoUrl);
      final infoMap = _asMap(infoData);
      final info = _asMap(infoMap?['data']) ?? infoMap;
      if (info != null && info.isNotEmpty) {
        brief = mapRankBrief({
          ...info,
          'rankid': _s(info['rankid']) == '' ? id : info['rankid'],
        });
      }
    } catch (_) {
      // fall through to songs
    }

    try {
      final songsUrl = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.rankSong,
        {
          'rankid': id,
          'page': page,
          'pagesize': pageSize,
          'plat': 0,
          'format': 'json',
        },
      );
      final songsData = await _client.getJson(songsUrl);
      final songsMap = _asMap(songsData);
      final dataNode = _asMap(songsMap?['data']);
      final listNode = dataNode?['info'] ?? songsMap?['info'];

      final parsed = <Track>[];
      if (listNode is List) {
        for (final item in listNode) {
          if (item is! Map) continue;
          final track = mapMobileSearchSong(Map<String, dynamic>.from(item));
          if (track.hash.isNotEmpty || track.name.isNotEmpty) {
            parsed.add(track);
          }
        }
      }
      if (parsed.isNotEmpty) tracks = parsed;
    } catch (_) {
      // keep whatever brief we already have
    }

    if (brief == null && tracks.isEmpty) return null;
    brief ??= PlaylistBrief(
      id: id,
      name: '榜单',
      coverUrl: normalizeCoverUrl(id),
      description: '',
      creator: '酷狗官方',
      trackCount: tracks.length,
      playCountLabel: '',
      isRank: true,
    );
    return (brief: brief, tracks: tracks);
  }
}

String _s(Object? v) {
  if (v == null) return '';
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? '' : t;
}

final playlistRepository = PlaylistRepository();
