import 'package:dio/dio.dart';

import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/network_log.dart';
import '../../core/models/audio_quality.dart';
import '../../core/models/track.dart';
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';

/// Resolves playable audio URLs — port of KuGouMusicApi `song_url.js`
/// + `util/request.js` (lite / concept app).
class PlayRepository {
  PlayRepository({Dio? dio}) : _dio = dio ?? _createDio() {
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
                    ? null
                    : truncateLogData(options.queryParameters),
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
        ),
      );
    }
  }

  /// Wired from main() so /v5/url appears in the in-app network log.
  
  static void _emit(NetworkLog log) => NetworkLogHub.emit(log);

  final Dio _dio;
  String lastError = '';

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

  /// 查询歌曲可用音质（mobilecdn `/api/v3/song/info` → `extra` 字段）。
  /// 失败返回 null。
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchRelateGoods(
    Track track,
  ) async {
    final hash = track.hash.trim().toLowerCase();
    if (hash.isEmpty) return null;
    try {
      final res = await _dio.get<dynamic>(
        'http://mobilecdn.kugou.com/api/v3/song/info',
        queryParameters: {
          'hash': hash,
          if (track.albumId.isNotEmpty) 'album_id': track.albumId,
          'format': 'json',
        },
      );
      final decoded = decodeKugoBody(res.data?.toString() ?? '');
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final data = map['data'];
      final payload = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      final complete = payload.containsKey('relate_goods') ||
          payload.containsKey('relateGoods') ||
          map.containsKey('relate_goods') ||
          map.containsKey('relateGoods');
      final goods = AudioQualityUtil.buildRelateGoods({
        ...map,
        ...payload,
        'extra': payload['extra'] ?? map['extra'],
      });
      return (goods: goods, catalogComplete: complete);
    } catch (_) {
      return null;
    }
  }

  /// 向下兼容解析：按候选音质依次请求 `/v5/url`，返回首次成功结果。
  Future<ResolvedAudio?> resolveUrlWithFallback(
    Track track, {
    required List<String> qualityCandidates,
    String? ppageId,
  }) async {
    final candidates = qualityCandidates.isEmpty
        ? <String>['128']
        : qualityCandidates;
    ResolvedAudio? best;
    String? firstError;
    for (final q in candidates) {
      final resolved = await resolveUrl(track, quality: q, ppageId: ppageId);
      if (resolved != null) {
        best = ResolvedAudio(
          url: resolved.url,
          backupUrls: resolved.backupUrls,
          quality: q,
        );
        break;
      }
      firstError ??= lastError;
    }
    if (best == null && firstError != null && firstError.isNotEmpty) {
      lastError = firstError;
    }
    return best;
  }

  Future<ResolvedAudio?> resolveUrl(
    Track track, {
    String quality = '',
    String? ppageId,
  }) async {
    lastError = '';
    final hash = track.hash.trim().toLowerCase();
    if (hash.isEmpty) {
      lastError = '曲目缺少 hash';
      return null;
    }

    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final hasToken = auth.hasToken;
    final token = hasToken ? auth.token : '';
    final userid = auth.userId.isEmpty ? '0' : auth.userId;

    final attempts = <({String token, String userid, String? ppage})>[
      (token: token, userid: userid, ppage: null),
      (token: token, userid: userid, ppage: ppageId ?? '356753938'),
      // SSA with token after reinstall → retry as guest-signed request.
      if (hasToken) (token: '', userid: '0', ppage: null),
    ];

    String? firstError;
    for (final a in attempts) {
      final resolved = await _songUrl(
        hash: hash,
        track: track,
        quality: quality,
        mid: device.mid,
        token: a.token,
        userid: a.userid,
        ppageId: a.ppage,
      );
      if (resolved != null) return resolved;
      firstError ??= lastError;
      if (lastError.contains('曲目缺少')) break;
    }
    if (firstError != null && firstError.isNotEmpty) {
      lastError = firstError;
    }
    return null;
  }

  /// Exact song_url.js shape. dfid is **random per request** (not device-stable).
  Future<ResolvedAudio?> _songUrl({
    required String hash,
    required Track track,
    required String quality,
    required String mid,
    required String token,
    required String userid,
    String? ppageId,
  }) async {
    // song_url.js: cookie dfid = randomString(24)
    final dfid = KugoSign.randomAlnum(24);
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hasToken = token.isNotEmpty;
    final uid = hasToken && userid.isNotEmpty && userid != '0'
        ? (int.tryParse(userid) ?? 0)
        : 0;

    // quality || 128 (number) as in JS
    final q = quality.isEmpty ? 128 : quality;

    // Build dataMap exactly like song_url.js, then let request.js inject defaults.
    final params = <String, dynamic>{
      // request.js defaultParams
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': 11430,
      'clienttime': clienttime,
      if (hasToken) 'token': token,
      if (uid != 0) 'userid': uid,
      // song_url.js dataMap
      'album_id': int.tryParse(track.albumId) ?? 0,
      'area_code': 1,
      'hash': hash,
      'ssa_flag': 'is_fromtrack',
      'version': 11430,
      'page_id': 967177915,
      'quality': q,
      'album_audio_id': int.tryParse(track.mixSongId) ?? 0,
      'behavior': 'play',
      'pid': 411,
      'cmd': 26,
      'pidversion': 3001,
      'IsFreePart': 0,
      'ppage_id': ppageId ?? '356753938,823673182,967485191',
      'cdnBackup': 1,
      'module': '',
    };

    // encryptKey: true → signKey(hash, mid, userid, appid)
    params['key'] = KugoSign.signKey(
      hash,
      mid,
      userid: uid == 0 ? '0' : '$uid',
    );

    // notSign in song_url is a no-op; request.js uses notSignature → still signs.
    params['signature'] = KugoSign.signatureAndroidParams(params);

    try {
      final res = await _dio.get<dynamic>(
        'https://gateway.kugou.com/v5/url',
        queryParameters: params,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'dfid': dfid,
            'clienttime': '$clienttime',
            'mid': mid,
            'kg-rc': '1',
            'kg-thash': '5d816a0',
            'kg-rec': '1',
            'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
            'x-router': 'trackercdn.kugou.com',
          },
        ),
      );

      final decoded = decodeKugoBody(res.data?.toString() ?? '');
      if (decoded is! Map) {
        lastError = '播放地址响应无法解析';
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final errcode = map['errcode'] ?? map['error_code'] ?? 0;
      final status = map['status'] ?? 0;
      final urls = _extractUrls(map);
      if (urls.isNotEmpty) {
        final reported = _extractQuality(map) ?? (quality.isEmpty ? '128' : quality);
        return ResolvedAudio(
          url: urls.first,
          backupUrls: urls.skip(1).toList(),
          quality: reported,
        );
      }

      if (errcode == 20028 || errcode == '20028') {
        lastError = hasToken
            ? '触发安全验证（SSA 20028），请重新登录后再试'
            : '播放需要登录/安全验证（游客通道已关闭）';
      } else if (errcode == 20006 || errcode == '20006') {
        lastError = '签名失败（20006）';
      } else if (status == 0 || status == '0') {
        lastError =
            '${map['error'] ?? map['errmsg'] ?? map['msg'] ?? '无法获取播放地址'}'
                .toString();
      } else {
        lastError = '无法获取播放地址';
      }
      return null;
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return null;
    }
  }

  /// Best-effort quality token from `/v5/url` payload.
  String? _extractQuality(Map<String, dynamic> map) {
    Object? node = map['data'] is Map ? map['data'] : map;
    if (node is! Map) return null;
    final m = Map<String, dynamic>.from(node);
    for (final key in ['quality', 'Quality', 'extname', 'fileHead']) {
      final v = m[key];
      if (v == null || v is Map || v is List) continue;
      final t = v.toString().trim().toLowerCase();
      if (t.isEmpty || t == 'null') continue;
      // extname flac/mp3 → rough map when quality missing
      if (key == 'extname') {
        if (t == 'flac') return 'flac';
        if (t == 'mp3') return null;
      }
      if (key == 'fileHead') continue;
      return t;
    }
    final qualityObj = m['quality'];
    if (qualityObj is Map) {
      final qm = Map<String, dynamic>.from(qualityObj);
      for (final k in ['value', 'name', 'type', 'id']) {
        final v = qm[k];
        if (v != null && v is! Map && v is! List) {
          final t = v.toString().trim();
          if (t.isNotEmpty && t != 'null') return t;
        }
      }
    }
    return null;
  }

  List<String> _extractUrls(Map<String, dynamic> map) {
    final out = <String>[];
    void add(Object? v) {
      if (v is String && v.startsWith('http')) out.add(v);
      if (v is List) {
        for (final item in v) {
          add(item);
        }
      }
    }

    void walk(dynamic node, [int depth = 0]) {
      if (depth > 4 || node == null) return;
      if (node is Map) {
        for (final e in node.entries) {
          final k = e.key.toString().toLowerCase();
          if (k == 'url' ||
              k == 'urls' ||
              k == 'play_url' ||
              k == 'playurl' ||
              k == 'down_url' ||
              k == 'backup_url' ||
              k == 'backupurl') {
            add(e.value);
          } else {
            walk(e.value, depth + 1);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item, depth + 1);
        }
      }
    }

    walk(map);
    return out.toSet().toList();
  }
}

final playRepository = PlayRepository();
