import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/mappers.dart';
import '../../core/models/track.dart';

class SearchRepository {
  SearchRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final url = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.searchSong, {
      'format': 'json',
      'keyword': keyword,
      'page': page,
      'pagesize': pageSize,
      'showtype': 1,
    });
    final data = await _client.getJson(url);
    final list = _extractList(data);
    return list
        .whereType<Map>()
        .map((e) => mapMobileSearchSong(Map<String, dynamic>.from(e)))
        .where((t) => t.hash.isNotEmpty || t.name.isNotEmpty)
        .toList();
  }

  Future<List<String>> hotKeywords({int count = 20}) async {
    try {
      final url = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.searchHot, {
        'format': 'json',
        'plat': 0,
        'count': count,
      });
      final data = await _client.getJson(url);
      final list = _extractList(data);
      return list
          .whereType<Map>()
          .map((e) => (e['keyword'] ?? e['word'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } on KugoApiException {
      return const [];
    }
  }

  Future<List<String>> suggest(String keyword) async {
    try {
      final url = buildUrl(
        KugoEndpoints.mobileCdn,
        KugoEndpoints.searchSuggest,
        {'format': 'json', 'keyword': keyword},
      );
      final data = await _client.getJson(url);
      final maps = <Map>[];
      if (data is Map) {
        final info = data['data'];
        if (info is Map) {
          final infoList = info['info'];
          if (infoList is List) maps.addAll(infoList.whereType<Map>());
        }
        final list = data['list'];
        if (list is List) maps.addAll(list.whereType<Map>());
      }
      return maps
          .map((e) => (e['keyword'] ?? e['hint'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } on KugoApiException {
      return const [];
    }
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    final body = Map<String, dynamic>.from(data);
    final dataNode = body['data'];
    if (dataNode is Map) {
      final info = dataNode['info'];
      if (info is List) return info;
    }
    final info = body['info'];
    if (info is List) return info;
    final list = body['list'];
    if (list is List) return list;
    return const [];
  }
}

final searchRepository = SearchRepository();
