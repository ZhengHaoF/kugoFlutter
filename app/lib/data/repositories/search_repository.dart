import 'dart:async';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/mappers.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';

export '../../core/models/search_result.dart'
    show AlbumBrief, ArtistBrief, SearchPageResult;

/// The four search tabs. Each maps to its own kugou endpoint — these are
/// *not* one endpoint behind a `type` parameter (verified against the live
/// API: `showtype` is a correction toggle, not a type switch).
enum SearchType {
  song,
  playlist,
  album,
  artist;

  String get label => switch (this) {
        SearchType.song => '歌曲',
        SearchType.playlist => '歌单',
        SearchType.album => '专辑',
        SearchType.artist => '歌手',
      };
}

class SearchRepository {
  SearchRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  /// `search/singer` has no artwork; cache `singer/info` avatars by id so
  /// re-search / pagination don't re-hit the same singers.
  final Map<String, String> _avatarCache = {};

  /// Songs only, without pagination metadata.
  ///
  /// Kept as the convenient shape for callers that just want a list
  /// (song-detail relate lists, FM seeding, etc.). Use [searchSongsPage] when
  /// you need `total` to drive load-more.
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final result = await searchSongsPage(keyword, page: page, pageSize: pageSize);
    return result.items;
  }

  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final body = await _get(KugoEndpoints.searchSong, keyword, page, pageSize);
    final items = _list(body)
        .whereType<Map>()
        .map((e) => mapMobileSearchSong(Map<String, dynamic>.from(e)))
        .where((t) => t.hash.isNotEmpty || t.name.isNotEmpty)
        .toList();
    return SearchPageResult(items: items, total: _total(body));
  }

  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final body = await _get(KugoEndpoints.searchSpecial, keyword, page, pageSize);
    final items = _list(body)
        .whereType<Map>()
        .map((e) => mapPlaylistInfo(Map<String, dynamic>.from(e)))
        .where((p) => p.id.isNotEmpty || p.name.isNotEmpty)
        .toList();
    return SearchPageResult(items: items, total: _total(body));
  }

  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final body = await _get(KugoEndpoints.searchAlbum, keyword, page, pageSize);
    final items = _list(body)
        .whereType<Map>()
        .map((e) => mapAlbumBrief(Map<String, dynamic>.from(e)))
        .where((a) => a.id.isNotEmpty || a.name.isNotEmpty)
        .toList();
    return SearchPageResult(items: items, total: _total(body));
  }

  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final body = await _get(KugoEndpoints.searchSinger, keyword, page, pageSize);
    final items = _list(body)
        .whereType<Map>()
        .map((e) => mapArtistBrief(Map<String, dynamic>.from(e)))
        .where((a) => a.id.isNotEmpty && a.name.isNotEmpty)
        .toList();
    // `search/singer` reports no total; the caller falls back to
    // "did we get a full page?".
    final enriched = await _withAvatars(items);
    return SearchPageResult(items: enriched, total: _total(body));
  }

  /// Backfill [ArtistBrief.avatarUrl] from `singer/info` (the search payload
  /// has no image). Limited concurrency + cache so a page of 30 doesn't stampede.
  Future<List<ArtistBrief>> _withAvatars(List<ArtistBrief> artists) async {
    if (artists.isEmpty) return artists;

    final needFetch = <String>[];
    for (final a in artists) {
      if (a.avatarUrl.isNotEmpty) continue;
      if (_avatarCache[a.id]?.isNotEmpty == true) continue;
      needFetch.add(a.id);
    }

    const concurrency = 6;
    for (var start = 0; start < needFetch.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, needFetch.length);
      await Future.wait([
        for (var i = start; i < end; i++)
          _fillAvatar(needFetch[i]),
      ]);
    }

    return [
      for (final a in artists)
        a.avatarUrl.isNotEmpty
            ? a
            : a.copyWith(avatarUrl: _avatarCache[a.id] ?? ''),
    ];
  }

  Future<void> _fillAvatar(String singerId) async {
    if (_avatarCache[singerId]?.isNotEmpty == true) return;
    try {
      final url = buildUrl(KugoEndpoints.mobileCdn, KugoEndpoints.singerInfo, {
        'singerid': singerId,
        'format': 'json',
      });
      // Cap wait so a hung singer/info can't block the whole artist tab.
      final body = await _client
          .getJson(url)
          .timeout(const Duration(seconds: 6));
      if (body is! Map) return;
      final map = Map<String, dynamic>.from(body);
      final data = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;
      for (final v in [
        data['imgurl'],
        data['avatar'],
        data['sizable_avatar'],
        data['pic'],
      ]) {
        final s = v?.toString().trim() ?? '';
        if (s.isEmpty || s == 'null') continue;
        _avatarCache[singerId] = normalizeCoverUrl(s);
        return;
      }
    } catch (_) {
      // Keep the person-glyph fallback; don't fail the search page.
    }
  }

  Future<dynamic> _get(
    String path,
    String keyword,
    int page,
    int pageSize,
  ) async {
    final url = buildUrl(KugoEndpoints.mobileCdn, path, {
      'format': 'json',
      'keyword': keyword,
      'page': page,
      'pagesize': pageSize,
    });
    return _client.getJson(url);
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

  /// Result array for the four search endpoints.
  ///
  /// `search/singer` puts the array **directly** in `data` rather than under
  /// `data.info`, so that case has to be handled explicitly or artists always
  /// come back empty.
  List<dynamic> _list(dynamic body) {
    if (body is List) return body;
    if (body is! Map) return const [];
    final map = Map<String, dynamic>.from(body);
    final data = map['data'];
    if (data is List) return data;
    if (data is Map) {
      final info = data['info'];
      if (info is List) return info;
      final list = data['list'];
      if (list is List) return list;
    }
    final info = map['info'];
    if (info is List) return info;
    final list = map['list'];
    if (list is List) return list;
    return const [];
  }

  /// `data.total`, or `null` when absent. Never guessed.
  int? _total(dynamic body) {
    if (body is! Map) return null;
    final map = Map<String, dynamic>.from(body);
    final data = map['data'];
    final candidates = <dynamic>[
      if (data is Map) data['total'],
      map['total'],
    ];
    for (final c in candidates) {
      if (c is int) return c;
      if (c is num) return c.toInt();
      if (c is String) {
        final parsed = int.tryParse(c.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];
    final body = Map<String, dynamic>.from(data);
    final dataNode = body['data'];
    if (dataNode is List) return dataNode;
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
