import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
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

/// Port of KuGouMusicApi `everyday_recommend.js` + public fallback mix.
///
/// EchoMusic calls `/everyday/recommend` → gateway POST
/// `/everyday_song_recommend` with login cookie (token/userid) + device mid.
/// When that path fails or returns nothing, fall back to the public rank/keyword
/// pool so guests still get a usable daily list.
class RecommendRepository {
  RecommendRepository({
    PlaylistRepository? playlists,
    SearchRepository? search,
    Dio? dio,
  })  : _playlists = playlists ?? playlistRepository,
        _search = search ?? searchRepository,
        _dio = dio ?? _createDio();

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
        final detail = await _playlists.fetchPlaylist(pick.id, pageSize: limit);
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
