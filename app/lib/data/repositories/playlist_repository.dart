import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/mappers.dart';
import '../../core/models/track.dart';

class PlaylistRepository {
  PlaylistRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  /// Public playlist metadata + tracks via mobile CDN.
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylist(
    String id, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final numericId = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericId.isEmpty) return null;

    try {
      final url = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.playlistInfo, {
        'specialid': numericId,
        'page': page,
        'pagesize': pageSize,
        'format': 'json',
      });
      final data = await _client.getJson(url);
      if (data is! Map) return null;
      final map = Map<String, dynamic>.from(data);
      final info = map['info'];
      if (info is! Map) return null;
      final brief = mapPlaylistInfo(Map<String, dynamic>.from(info));

      final listNode = map['list'] ?? info['list'];
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
      final list = map['list'] ?? map['info'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => mapPlaylistInfo(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

final playlistRepository = PlaylistRepository();
