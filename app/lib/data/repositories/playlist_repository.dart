import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/api/network_log.dart';
import '../../core/models/track.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

class PlaylistRepository {
  PlaylistRepository({KugoClient? client, Dio? dio})
      : _client = client ?? kugoClient,
        _dio = dio ?? _createDio();

  /// Wired from main() so signed gateway rank calls show up in network logs.
  static NetworkLogSink? logSink;

  final KugoClient _client;
  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  static void _emit(NetworkLog log) => logSink?.call(log);

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

  /// Rank board detail: signed `rank/audio` first, public `rank/song` fallback.
  ///
  /// Rank ids are **not** specialids — `/playlist/:id` must fall back here
  /// when `special/*` returns nothing for a rank board id.
  ///
  /// Public `mobilecdn .../rank/song` often returns only a degraded slice
  /// (e.g. TOP500 → 3 songs). EchoMusic / KuGouMusicApi use signed
  /// `POST gateway.kugou.com/openapi/kmr/v2/rank/audio` with `rank_id` in the
  /// JSON body; that path reports `data.total` and a full `data.songlist[]`.
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchRankDetail(
    String rankId, {
    int page = 1,
    int pageSize = 100,
    String rankCid = '0',
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

    // 1) Signed gateway rank/audio (EchoMusic / KuGouMusicApi).
    final audio = await _fetchRankAudio(
      id,
      page: page,
      pageSize: pageSize,
      rankCid: rankCid,
    );
    if (audio != null && audio.tracks.isNotEmpty) {
      tracks = audio.tracks;
      final count = audio.total > 0 ? audio.total : tracks.length;
      brief = (brief ?? _fallbackRankBrief(id, tracks))
          .copyWith(trackCount: count);
    } else {
      // 2) Legacy public rank/song (often a short slice).
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
    }

    if (brief == null && tracks.isEmpty) return null;
    brief ??= _fallbackRankBrief(id, tracks);
    return (brief: brief, tracks: tracks);
  }

  PlaylistBrief _fallbackRankBrief(String id, List<Track> tracks) {
    return PlaylistBrief(
      id: id,
      name: '榜单',
      coverUrl: normalizeCoverUrl(id),
      description: '',
      creator: '酷狗官方',
      trackCount: tracks.length,
      playCountLabel: '',
      isRank: true,
    );
  }

  /// Signed `POST /openapi/kmr/v2/rank/audio` (KuGouMusicApi `rank_audio.js`).
  Future<({List<Track> tracks, int total})?> _fetchRankAudio(
    String rankId, {
    required int page,
    required int pageSize,
    required String rankCid,
  }) async {
    try {
      final device = await DeviceIdentity.ensure();
      final auth = AuthTokenHolder.instance;
      final useToken = auth.hasToken;
      final userId = auth.userId.isNotEmpty && auth.userId != '0'
          ? auth.userId
          : '';
      final userIdNum = int.tryParse(userId) ?? 0;
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final body = <String, dynamic>{
        'show_portrait_mv': 1,
        'show_type_total': 1,
        'filter_original_remarks': 1,
        'area_code': 1,
        'pagesize': pageSize,
        'rank_cid': int.tryParse(rankCid) ?? 0,
        'type': 1,
        'page': page,
        'rank_id': int.tryParse(rankId) ?? 0,
      };
      final bodyJson = jsonEncode(body);

      final params = <String, dynamic>{
        'dfid': device.dfid,
        'mid': device.mid,
        'uuid': '-',
        'appid': int.parse(KugoSign.appId),
        'clientver': int.parse(KugoSign.clientVer),
        'clienttime': clienttime,
        if (useToken) 'token': auth.token,
        if (userIdNum != 0) 'userid': userIdNum,
      };
      params['signature'] =
          KugoSign.signatureAndroidParams(params, data: bodyJson);

      final headers = <String, dynamic>{
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': device.dfid,
        'clienttime': '$clienttime',
        'mid': device.mid,
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        // rank_audio.js — required by the openapi rank gateway.
        'kg-tid': '369',
        'Cookie': [
          if (useToken) 'token=${auth.token}',
          if (userId.isNotEmpty) 'userid=$userId',
          if (auth.t1.isNotEmpty) 't1=${auth.t1}',
          'dfid=${device.dfid}',
          'KUGOU_API_MID=${device.mid}',
          'KUGOU_API_GUID=${device.guid}',
          'KUGOU_API_DEV=${device.dev}',
        ].join(';'),
      };

      final url = '${KugoEndpoints.gateway}${KugoEndpoints.rankAudio}';
      final logId =
          '${DateTime.now().microsecondsSinceEpoch}-$url-$rankId-$page';
      _emit(
        NetworkLog(
          id: logId,
          type: NetworkLogType.request,
          timestamp: DateTime.now(),
          method: 'POST',
          url: url,
          headers: sanitizeHeaders(headers),
          data: truncateLogData({'query': params, 'body': bodyJson}),
        ),
      );

      final res = await _dio.post<dynamic>(
        url,
        queryParameters: params,
        data: bodyJson,
        options: Options(headers: headers),
      );
      final raw = res.data?.toString() ?? '';
      _emit(
        NetworkLog(
          id: logId,
          type: NetworkLogType.response,
          timestamp: DateTime.now(),
          method: 'POST',
          url: url,
          statusCode: res.statusCode,
          data: truncateLogData(raw),
        ),
      );

      if (looksLikeUrlFilter(raw)) return null;
      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final ok = status == 1 || status == '1' || status == true;
      final songs = extractRankAudioSongs(map);
      if (!ok && songs.isEmpty) return null;

      final parsed = <Track>[];
      final seen = <String>{};
      for (final item in songs) {
        if (item is! Map) continue;
        final track = mapMobileSearchSong(Map<String, dynamic>.from(item));
        if (track.hash.isEmpty && track.name == '未知歌曲') continue;
        final key = track.id.isNotEmpty ? track.id : track.hash;
        if (key.isEmpty || !seen.add(key)) continue;
        parsed.add(track);
      }
      if (parsed.isEmpty) return null;
      return (tracks: parsed, total: extractRankAudioTotal(map));
    } catch (_) {
      return null;
    }
  }
}

String _s(Object? v) {
  if (v == null) return '';
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? '' : t;
}

final playlistRepository = PlaylistRepository();
