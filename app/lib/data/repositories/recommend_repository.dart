import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/api/network_log.dart';
import '../../core/models/track.dart';
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';
import 'playlist_repository.dart';
import 'search_repository.dart';

/// Daily recommend result: personalized when EchoMusic-aligned API succeeds.
class DailyRecommendResult {
  const DailyRecommendResult({
    required this.tracks,
    this.personalized = false,
    this.error = '',
    this.needLogin = false,
  });

  final List<Track> tracks;
  final bool personalized;
  final String error;
  final bool needLogin;

  bool get isEmpty => tracks.isEmpty;
}

/// One style tag under a group tab (EchoMusic `tag_info[].child[]`).
class StyleTag {
  const StyleTag({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isDefault;
}

/// Style recommend tag group (EchoMusic `tag_info[]`).
class StyleTagGroup {
  const StyleTagGroup({required this.name, required this.child});

  final String name;
  final List<StyleTag> child;
}

/// Style-recommend section payload for the hub page.
class StyleRecommendResult {
  const StyleRecommendResult({
    this.tracks = const [],
    this.groups = const [],
    this.error = '',
    this.needLogin = false,
  });

  final List<Track> tracks;
  final List<StyleTagGroup> groups;
  final String error;
  final bool needLogin;

  bool get isEmpty => tracks.isEmpty && groups.isEmpty;
}

/// Playlist section result used by the recommend hub.
class RecommendPlaylistsSection {
  const RecommendPlaylistsSection({
    this.playlists = const [],
    this.error = '',
  });

  final List<PlaylistBrief> playlists;
  final String error;

  bool get isEmpty => playlists.isEmpty;
}

/// Port of KuGouMusicApi recommendation modules + public fallback mix.
///
/// Daily: `everyday_recommend.js` → gateway `/everyday_song_recommend`.
/// Style: `everyday_style_recommend.js` → `/everyday_style_recommend`.
/// Playlists: `top_playlist.js` → `/v2/special_recommend`.
/// Editorial: `top_ip.js` → `musicadservice/v1/daily_recommend`.
class RecommendRepository {
  RecommendRepository({
    PlaylistRepository? playlists,
    SearchRepository? search,
    Dio? dio,
  })  : _playlists = playlists ?? playlistRepository,
        _search = search ?? searchRepository,
        _dio = dio ?? _createDio() {
    if (dio == null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.extra['__start'] = DateTime.now().millisecondsSinceEpoch;
            options.extra['__id'] =
                '${DateTime.now().microsecondsSinceEpoch}-${options.uri}';
            _emit(
              NetworkLog(
                id: options.extra['__id'] as String,
                type: NetworkLogType.request,
                timestamp: DateTime.now(),
                method: options.method,
                url: options.uri.toString(),
                headers: sanitizeHeaders(options.headers),
                data: options.queryParameters.isEmpty
                    ? options.data
                    : truncateLogData({
                        'query': options.queryParameters,
                        'body': options.data,
                      }),
              ),
            );
            handler.next(options);
          },
          onResponse: (res, handler) {
            final start = res.requestOptions.extra['__start'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
            _emit(
              NetworkLog(
                id: res.requestOptions.extra['__id'] as String? ??
                    res.requestOptions.uri.toString(),
                type: NetworkLogType.response,
                timestamp: DateTime.now(),
                method: res.requestOptions.method,
                url: res.requestOptions.uri.toString(),
                statusCode: res.statusCode,
                data: truncateLogData(res.data),
                duration: Duration(
                  milliseconds: DateTime.now().millisecondsSinceEpoch - start,
                ),
              ),
            );
            handler.next(res);
          },
          onError: (e, handler) {
            final start = e.requestOptions.extra['__start'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
            _emit(
              NetworkLog(
                id: e.requestOptions.extra['__id'] as String? ??
                    e.requestOptions.uri.toString(),
                type: NetworkLogType.error,
                timestamp: DateTime.now(),
                method: e.requestOptions.method,
                url: e.requestOptions.uri.toString(),
                errorMessage: e.message ?? e.toString().split('\n').first,
                data: truncateLogData(e.response?.data),
                duration: Duration(
                  milliseconds: DateTime.now().millisecondsSinceEpoch - start,
                ),
              ),
            );
            handler.next(e);
          },
        ),
      );
    }
  }

  /// Wired from main() so recommend gateway calls appear in network log.
  
  static void _emit(NetworkLog log) => NetworkLogHub.emit(log);

  final PlaylistRepository _playlists;
  final SearchRepository _search;
  final Dio _dio;
  String lastError = '';

  static const moods = [
    '华语流行',
    '民谣精选',
    '轻音乐',
    '说唱热歌',
    '国风新声',
    '摇滚经典',
    '电子夜行',
    '治愈系',
  ];

  /// EchoMusic Home.vue RECOMMEND_PLAYLIST_CATEGORIES（Hi-Res 等接口验证后再扩）。
  static const recommendPlaylistCategories = <({String id, String label})>[
    (id: '0', label: '推荐'),
    (id: '11292', label: 'Hi-Res'),
  ];

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  int dayOfYear([DateTime? date]) {
    final d = date ?? DateTime.now();
    return d.difference(DateTime(d.year)).inDays + 1;
  }

  String moodLabel([DateTime? date]) {
    return moods[dayOfYear(date) % moods.length];
  }

  String dateLabel([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.month}月${d.day}日';
  }

  /// Prefer personalized `/everyday_song_recommend` (EchoMusic parity);
  /// fall back to public rank + mood search pool.
  Future<DailyRecommendResult> fetchDaily({
    DateTime? date,
    int limit = 30,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    final hasToken = auth.hasToken;

    final personalized = await _fetchPersonalized(limit: limit);
    if (personalized.isNotEmpty) {
      return DailyRecommendResult(tracks: personalized, personalized: true);
    }

    final publicTracks = await _fetchPublicFallback(date: date, limit: limit);
    final filtered = lastError.contains('拦截') || lastError.contains('URL过滤');
    if (publicTracks.isNotEmpty) {
      return DailyRecommendResult(
        tracks: publicTracks,
        personalized: false,
        needLogin: !hasToken,
        error: hasToken && !filtered ? lastError : '',
      );
    }

    return DailyRecommendResult(
      tracks: const [],
      personalized: false,
      needLogin: !hasToken,
      error: filtered
          ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点后重试。'
          : (lastError.isNotEmpty
              ? lastError
              : (hasToken
                  ? '每日推荐加载失败，请检查网络后重试'
                  : '登录后可获取个性化每日推荐')),
    );
  }

  /// EchoMusic `/everyday/style/recommend` → style tags + songs.
  ///
  /// Upstream KuGouMusicApi `everyday_style_recommend.js`:
  /// - URL path embeds the service: `/everydayrec.service/everyday_style_recommend`
  /// - method POST, **body is empty JSON object `{}`** (signature data = `'{}'`)
  /// - query only carries default device params + `tagids`
  /// - no `x-router` header (service is already in the path)
  Future<StyleRecommendResult> fetchStyleRecommend({
    String tagids = '',
    int limit = 30,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    final hasToken = auth.hasToken;

    final body = await _signedGatewayPost(
      path: KugoEndpoints.everydayStyleRecommendPrefixed,
      router: null,
      // Upstream always includes tagids (empty string = default recommend).
      extraQuery: {'tagids': tagids},
      // JSON.stringify({}) → signature + request body both use '{}'.
      body: const <String, dynamic>{},
      label: '风格推荐',
    );

    if (body == null) {
      final filtered = lastError.contains('拦截') || lastError.contains('URL过滤');
      return StyleRecommendResult(
        needLogin: !hasToken,
        error: filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗'
            : (lastError.isNotEmpty
                ? lastError
                : (hasToken
                    ? '风格推荐加载失败，请稍后重试'
                    : '登录后可获取更贴合口味的风格推荐')),
      );
    }

    final groups = extractStyleTagGroups(body)
        .map(
          (g) => StyleTagGroup(
            name: g.name,
            child: g.child
                .map(
                  (t) => StyleTag(id: t.id, name: t.name, isDefault: t.isDefault),
                )
                .toList(),
          ),
        )
        .toList();

    final tracks = <Track>[];
    final seen = <String>{};
    for (final item in extractEverydayList(body)) {
      if (item is! Map) continue;
      final track = mapEverydaySong(Map<String, dynamic>.from(item));
      if (track.hash.isEmpty && track.name == '未知歌曲') continue;
      final key = track.id.isNotEmpty ? track.id : track.hash;
      if (key.isEmpty || !seen.add(key)) continue;
      tracks.add(track);
      if (tracks.length >= limit) break;
    }

    if (tracks.isEmpty && groups.isEmpty) {
      return StyleRecommendResult(
        needLogin: !hasToken,
        error: lastError.isNotEmpty
            ? lastError
            : (hasToken ? '今日暂无风格推荐' : '登录后可获取风格推荐'),
      );
    }

    lastError = '';
    return StyleRecommendResult(tracks: tracks, groups: groups);
  }

  /// EchoMusic `/top/playlist` → specialrec `/v2/special_recommend`.
  Future<RecommendPlaylistsSection> fetchRecommendPlaylists({
    String categoryId = '0',
    int page = 1,
    int pageSize = 12,
  }) async {
    lastError = '';
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final userId = auth.userId.isNotEmpty && auth.userId != '0'
        ? auth.userId
        : '';
    final userIdNum = int.tryParse(userId) ?? 0;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final specialRecommend = <String, dynamic>{
      'withtag': 1,
      'withsong': 0,
      'sort': 1,
      'ugc': 1,
      'is_selected': 0,
      'withrecommend': 1,
      'area_code': 1,
      'categoryid': int.tryParse(categoryId) ?? 0,
    };
    final body = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'mid': device.mid,
      'clientver': int.parse(KugoSign.clientVer),
      'platform': 'android',
      'clienttime': clienttime,
      'userid': userIdNum,
      'module_id': 1,
      'page': page,
      'pagesize': pageSize,
      'key': KugoSign.signParamsKey('$clienttime'),
      'special_recommend': specialRecommend,
      'req_multi': 1,
      'retrun_min': 5,
      'return_special_falg': 1,
    };

    final decoded = await _signedGatewayPost(
      path: KugoEndpoints.specialRecommend,
      router: KugoEndpoints.specialRecommendRouter,
      body: body,
      label: '推荐歌单',
    );

    if (decoded == null) {
      final filtered = lastError.contains('拦截') || lastError.contains('URL过滤');
      return RecommendPlaylistsSection(
        error: filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗'
            : (lastError.isNotEmpty ? lastError : '推荐歌单加载失败'),
      );
    }

    final playlists = <PlaylistBrief>[];
    final seen = <String>{};
    for (final item in extractEverydayList(decoded)) {
      if (item is! Map) continue;
      final brief = mapRecommendPlaylist(Map<String, dynamic>.from(item));
      if (brief.id.isEmpty || !seen.add(brief.id)) continue;
      playlists.add(brief);
      if (playlists.length >= pageSize) break;
    }

    if (playlists.isEmpty) {
      return RecommendPlaylistsSection(
        error: lastError.isNotEmpty ? lastError : '暂无推荐歌单',
      );
    }
    lastError = '';
    return RecommendPlaylistsSection(playlists: playlists);
  }

  /// EchoMusic `/top/ip` → musicadservice `/v1/daily_recommend`.
  Future<RecommendPlaylistsSection> fetchEditorialPicks({int limit = 12}) async {
    lastError = '';
    final decoded = await _signedGatewayPost(
      baseUrl: KugoEndpoints.musicAdService,
      path: KugoEndpoints.topIp,
      router: null,
      extraQuery: {
        'clientver': 12349,
        'area_code': 1,
      },
      body: {'tags': <String, dynamic>{}},
      label: '编辑精选',
    );

    if (decoded == null) {
      final filtered = lastError.contains('拦截') || lastError.contains('URL过滤');
      return RecommendPlaylistsSection(
        error: filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗'
            : (lastError.isNotEmpty ? lastError : '编辑精选加载失败'),
      );
    }

    final playlists = <PlaylistBrief>[];
    final seen = <String>{};
    for (final item in extractEverydayList(decoded)) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final extra = map['extra'] is Map
          ? Map<String, dynamic>.from(map['extra'] as Map)
          : const <String, dynamic>{};
      final typeRaw = map['type'];
      final typeNum = typeRaw is int ? typeRaw : int.tryParse('$typeRaw') ?? 0;
      final globalId = extra['global_collection_id'] ??
          extra['global_special_id'] ??
          map['global_collection_id'];
      // EchoMusic keeps type==1 + global id; be slightly lenient when type is
      // absent so a valid payload still fills the section.
      if (typeNum != 0 && typeNum != 1) continue;
      if (typeNum == 1 && globalId == null) {
        // still try id resolution — some payloads omit extra
      }
      final brief = mapRecommendPlaylist(map);
      if (brief.id.isEmpty || !seen.add(brief.id)) continue;
      playlists.add(brief);
      if (playlists.length >= limit) break;
    }

    if (playlists.isEmpty) {
      return RecommendPlaylistsSection(
        error: lastError.isNotEmpty ? lastError : '暂无编辑精选',
      );
    }
    lastError = '';
    return RecommendPlaylistsSection(playlists: playlists);
  }

  /// Shared signed gateway/madservice POST used by style / playlist / top-ip.
  ///
  /// Aligned with KuGouMusicApi `util/request.js` encryptType=android:
  /// signature data slot = JSON body string (`''` when no body, `'{}'` for
  /// empty object). Headers include the kg-* client tags used by the official
  /// request layer.
  Future<Map<String, dynamic>?> _signedGatewayPost({
    required String path,
    String? router,
    String? baseUrl,
    Map<String, dynamic> extraQuery = const {},
    Map<String, dynamic>? body,
    String label = '推荐接口',
  }) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final useToken = auth.hasToken;
    final userId = auth.userId.isNotEmpty && auth.userId != '0'
        ? auth.userId
        : '';
    final userIdNum = int.tryParse(userId) ?? 0;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // request.js: object → JSON.stringify; missing → ''.
    final bodyJson = body == null ? '' : jsonEncode(body);

    final params = <String, dynamic>{
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      if (useToken) 'token': auth.token,
      if (userIdNum != 0) 'userid': userIdNum,
      ...extraQuery,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params, data: bodyJson);

    final cookieParts = <String>[
      if (useToken) 'token=${auth.token}',
      if (userId.isNotEmpty) 'userid=$userId',
      if (auth.t1.isNotEmpty) 't1=${auth.t1}',
      'dfid=${device.dfid}',
      'KUGOU_API_MID=${device.mid}',
      'KUGOU_API_GUID=${device.guid}',
      'KUGOU_API_DEV=${device.dev}',
    ];

    final host = baseUrl ?? KugoEndpoints.gateway;
    final headers = <String, dynamic>{
      'User-Agent': KugoSign.userAgent,
      'Content-Type': 'application/json',
      'dfid': device.dfid,
      'clienttime': '$clienttime',
      'mid': device.mid,
      // request.js default client tags (daily recommend also sends these).
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      'Cookie': cookieParts.join(';'),
    };
    if (router != null) headers['x-router'] = router;

    final url = '$host$path';
    final logId = '${DateTime.now().microsecondsSinceEpoch}-$url';
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

    try {
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

      if (looksLikeUrlFilter(raw)) {
        lastError = '网络网关拦截（URL过滤），无法访问酷狗';
        return null;
      }
      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        lastError = raw.isEmpty ? '$label响应为空' : '$label响应无法解析';
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final errRaw = map['err_code'] ?? map['error_code'] ?? map['errcode'];
      final errNum = errRaw is int ? errRaw : int.tryParse('$errRaw') ?? 0;
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg =
            (map['msg'] ?? map['message'] ?? map['error'] ?? '').toString();
        if (errNum == 20028 || msg.contains('20028')) {
          lastError = useToken
              ? '登录态触发安全校验（SSA 20028），请重新登录后再试'
              : '$label需要登录或安全校验';
        } else if (msg.contains('登录')) {
          lastError = '需要登录后查看';
        } else {
          lastError = msg.isEmpty
              ? '$label返回失败（status=$status err=$errRaw）'
              : msg;
        }
      } else {
        lastError = '';
      }
      return map;
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      lastError = msg.contains('URL过滤') || msg.contains('Access Deny')
          ? '网络网关拦截（URL过滤），无法访问酷狗'
          : '$label网络错误';
      _emit(
        NetworkLog(
          id: logId,
          type: NetworkLogType.error,
          timestamp: DateTime.now(),
          method: 'POST',
          url: url,
          errorMessage: lastError,
          data: truncateLogData(e.response?.data ?? msg),
        ),
      );
      return null;
    } catch (e) {
      lastError = '$label异常：$e';
      _emit(
        NetworkLog(
          id: logId,
          type: NetworkLogType.error,
          timestamp: DateTime.now(),
          method: 'POST',
          url: url,
          errorMessage: lastError,
        ),
      );
      return null;
    }
  }

  /// KuGouMusicApi everyday_recommend.js → EchoMusic `/everyday/recommend`.
  Future<List<Track>> _fetchPersonalized({int limit = 30}) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final useToken = auth.hasToken;
    final userId = auth.userId.isNotEmpty && auth.userId != '0'
        ? auth.userId
        : '';
    final userIdNum = int.tryParse(userId) ?? 0;

    // request.js defaultParams + everyday_recommend.js params.platform
    final params = <String, dynamic>{
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      if (useToken) 'token': auth.token,
      if (userIdNum != 0) 'userid': userIdNum,
      'platform': 'ios',
    };
    // encryptType: android; module sends no body → empty data in signature.
    params['signature'] = KugoSign.signatureAndroidParams(params, data: '');

    final cookieParts = <String>[
      if (useToken) 'token=${auth.token}',
      if (userId.isNotEmpty) 'userid=$userId',
      if (auth.t1.isNotEmpty) 't1=${auth.t1}',
      'dfid=${device.dfid}',
      'KUGOU_API_MID=${device.mid}',
      'KUGOU_API_GUID=${device.guid}',
      'KUGOU_API_DEV=${device.dev}',
    ];

    try {
      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}${KugoEndpoints.everydayRecommend}',
        queryParameters: params,
        data: '',
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'dfid': device.dfid,
            'clienttime': '$clienttime',
            'mid': device.mid,
            'kg-rc': '1',
            'kg-thash': '5d816a0',
            'kg-rec': '1',
            'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
            'x-router': KugoEndpoints.everydayRouter,
            'Cookie': cookieParts.join(';'),
          },
        ),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        lastError = '网络网关拦截（URL过滤），无法访问酷狗';
        return const [];
      }
      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        if (raw.isEmpty) {
          lastError = useToken ? '每日推荐响应为空' : '每日推荐需要登录';
        } else {
          lastError = '每日推荐响应无法解析';
        }
        return const [];
      }

      final body = Map<String, dynamic>.from(decoded);
      final status = body['status'];
      final errRaw = body['err_code'] ?? body['error_code'] ?? body['errcode'];
      final errNum = errRaw is int ? errRaw : int.tryParse('$errRaw') ?? 0;
      final ok = status == 1 || status == '1' || status == true;
      final list = extractEverydayList(body);

      if (!ok && list.isEmpty) {
        final msg = (body['msg'] ?? body['message'] ?? body['error'] ?? '')
            .toString();
        if (errNum == 20028 || msg.contains('20028')) {
          lastError = useToken
              ? '登录态触发安全校验（SSA 20028），请重新登录后再试'
              : '每日推荐需要登录或安全校验';
        } else if (msg.contains('登录') || errNum != 0 && !useToken) {
          lastError = '每日推荐需要登录后查看';
        } else {
          lastError = msg.isEmpty
              ? '每日推荐加载失败（status=$status err=$errRaw）'
              : msg;
        }
        return const [];
      }

      final tracks = <Track>[];
      final seen = <String>{};
      for (final item in list) {
        if (item is! Map) continue;
        final track = mapEverydaySong(Map<String, dynamic>.from(item));
        if (track.hash.isEmpty && track.name == '未知歌曲') continue;
        final key = track.id.isNotEmpty ? track.id : track.hash;
        if (key.isEmpty || !seen.add(key)) continue;
        tracks.add(track);
        if (tracks.length >= limit) break;
      }

      if (tracks.isEmpty) {
        lastError = useToken ? '今日暂无个性化推荐' : '每日推荐需要登录后查看';
        return const [];
      }
      lastError = '';
      return tracks;
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      lastError = msg.contains('URL过滤') || msg.contains('Access Deny')
          ? '网络网关拦截（URL过滤），无法访问酷狗'
          : '每日推荐网络错误';
      return const [];
    } catch (e) {
      lastError = '每日推荐异常：$e';
      return const [];
    }
  }

  /// Public-API daily mix (guest / network fallback).
  Future<List<Track>> _fetchPublicFallback({
    DateTime? date,
    int limit = 30,
  }) async {
    final seed = dayOfYear(date);
    final tracks = <Track>[];
    final seen = <String>{};

    void addAll(Iterable<Track> list) {
      for (final t in list) {
        if (tracks.length >= limit) return;
        final key = t.id.isNotEmpty ? t.id : t.hash;
        if (key.isEmpty || !seen.add(key)) continue;
        tracks.add(t);
      }
    }

    var publicError = '';
    try {
      final ranks = await _playlists.fetchRankList();
      if (ranks.isNotEmpty) {
        final pick = ranks[seed % ranks.length];
        // Rank boards resolve via rankid + rank/song, not specialid.
        final rankDetail = await _playlists.fetchRankDetail(
          pick.id,
          pageSize: limit,
        );
        final detail = rankDetail ??
            await _playlists.fetchPlaylist(pick.id, pageSize: limit);
        if (detail != null) addAll(detail.tracks);
      }
    } catch (e) {
      publicError = e.toString();
    }

    if (tracks.length < 15) {
      final keywords = [
        moods[seed % moods.length],
        moods[(seed * 3 + 1) % moods.length],
      ];
      for (final kw in keywords) {
        if (tracks.length >= limit) break;
        try {
          addAll(await _search.searchSongs(kw, pageSize: 20));
        } catch (e) {
          publicError = e.toString();
        }
      }
    }

    if (tracks.isEmpty && lastError.isEmpty && publicError.isNotEmpty) {
      lastError = publicError.contains('拦截') || publicError.contains('URL过滤')
          ? publicError
          : '每日推荐加载失败，请检查网络后重试';
    }
    return tracks;
  }
}

final recommendRepository = RecommendRepository();
