import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart'
    show NetworkLogSink, looksLikeUrlFilter, decodeKugoBody;
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/api/network_log.dart';
import '../../core/models/fm_mode.dart';
import '../../core/models/track.dart';
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';

/// 私人 FM 一页结果。
///
/// [fromServer] = true 表示 [tracks] 来自酷狗真实 `/v2/personal_recommend`
/// 接口；false 表示未登录 / 被网关拦截 / 解析失败（此时 [tracks] 通常为空，
/// [needLogin] / [error] 说明原因）。数据层**从不抛异常**，错误用 [error] 承载。
class FmPage {
  const FmPage({
    this.tracks = const [],
    this.needLogin = false,
    this.error = '',
    this.fromServer = false,
    this.mode = FmMode.heart,
    this.pool = FmSongPool.taste,
  });

  final List<Track> tracks;
  final bool needLogin;
  final String error;
  final bool fromServer;

  /// 产出本页的电台档位 / 口味池（UI 取文案用，如 `pool.reasonLabel`）。
  final FmMode mode;
  final FmSongPool pool;

  bool get isEmpty => tracks.isEmpty;
}

/// 酷狗真实私人 FM 数据层。
///
/// 上行 KuGouMusicApi `module/personal_fm.js` → `POST gateway.kugou.com
/// /v2/personal_recommend`，header `x-router: persnfm.service.kugou.com`。
/// 签名 / cookie / 设备身份写法照抄 `recommend_repository._fetchPersonalized`。
///
/// 已知行为（未登录实测）：返回 HTTP 200 + `{"data":"","status":0,
/// "error_code":200101}`。已登录应返回 `data` 里的歌曲列表，但字段结构未知，
/// 因此解析尽量宽容（详见 [_mapFmSong] / [_extractList] 的字段名假设）。
class FmRepository {
  FmRepository({Dio? dio}) : _dio = dio ?? _createDio() {
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

  /// Wired from main() so personal FM gateway calls appear in network log.
  static NetworkLogSink? logSink;

  static void _emit(NetworkLog log) => logSink?.call(log);

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

  /// 拉取一页私人 FM 歌曲。
  ///
  /// 两条轴分别对应真实接口的两个参数：[mode] → `mode`（normal/small/peak），
  /// [pool] → `song_pool_id`（0/1/2）。未登录或出错时返回空
  /// [FmPage.tracks] + needLogin/error，
  /// 不抛异常。`remain_songcnt > 4` 时服务端不返回新推荐（沿用上游语义）。
  Future<FmPage> fetch({
    required FmMode mode,
    required FmSongPool pool,
    String hash = '',
    String songid = '',
    int playtime = 0,
    int remainSongcnt = 0,
    String action = 'play',
    int limit = 30,
  }) {
    return _request(
      mode: mode,
      pool: pool,
      hash: hash,
      songid: songid,
      playtime: playtime,
      remainSongcnt: remainSongcnt,
      action: action,
      limit: limit,
      isOverplay: 0,
    );
  }

  /// 上报「加载更多 / 补充歌单」意图：action=play + is_overplay。
  /// 仅登录态可用时才真正发包，返回是否成功上报。
  Future<bool> reportPlay({
    required Track track,
    required int playtime,
    int remainSongcnt = 0,
    FmMode mode = FmMode.heart,
    FmSongPool pool = FmSongPool.taste,
  }) async {
    if (!AuthTokenHolder.instance.hasToken) return false;
    final durationSec = track.durationMs <= 0 ? 0 : track.durationMs ~/ 1000;
    final overplay = durationSec > 0 && playtime >= durationSec ? 1 : 0;
    final page = await _request(
      mode: mode,
      pool: pool,
      hash: track.hash,
      songid: track.mixSongId.isNotEmpty ? track.mixSongId : track.id,
      playtime: playtime,
      remainSongcnt: remainSongcnt,
      action: 'play',
      isOverplay: overplay,
      limit: 0,
    );
    return _reportOk(page);
  }

  /// 上报「不喜欢 / 垃圾反馈」：action=garbage。
  /// 仅登录态可用时才真正发包，返回是否成功上报。
  Future<bool> reportGarbage({
    required Track track,
    int remainSongcnt = 0,
    FmMode mode = FmMode.heart,
    FmSongPool pool = FmSongPool.taste,
  }) async {
    if (!AuthTokenHolder.instance.hasToken) return false;
    final page = await _request(
      mode: mode,
      pool: pool,
      hash: track.hash,
      songid: track.mixSongId.isNotEmpty ? track.mixSongId : track.id,
      remainSongcnt: remainSongcnt,
      action: 'garbage',
      isOverplay: 0,
      limit: 0,
      playtime: 0,
    );
    return _reportOk(page);
  }

  bool _reportOk(FmPage page) {
    // 成功条件：不是需要登录、没有被拦截/解析失败（即拿到了真实响应）。
    return page.fromServer || (!page.needLogin && page.error.isEmpty);
  }

  Future<FmPage> _request({
    required FmMode mode,
    required FmSongPool pool,
    required String hash,
    required String songid,
    required int playtime,
    required int remainSongcnt,
    required String action,
    required int isOverplay,
    required int limit,
  }) async {
    lastError = '';
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final useToken = auth.hasToken;
    final userId = auth.userId.isNotEmpty && auth.userId != '0' ? auth.userId : '';
    final userIdNum = int.tryParse(userId) ?? 0;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // URL query 参数（不含 signature，先算签名再补进去）。
    final query = <String, dynamic>{
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };

    // JSON body。字段顺序不影响签名（签名内部会排序），但 bodyJson 字符串本身
    // 直接进签名的 data 位，因此保持一次成型即可。
    final body = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'clienttime': clienttime,
      'mid': device.mid,
      'action': action,
      'recommend_source_locked': 0,
      'song_pool_id': pool.poolId,
      'callerid': 0,
      'm_type': 1,
      'platform': 'ios',
      'area_code': 1,
      'remain_songcnt': remainSongcnt,
      'clientver': int.parse(KugoSign.clientVer),
      'is_overplay': isOverplay,
      'mode': mode.modeParam,
      'fakem': 'ca981cfc583a4c37f28d2d49000013c16a0a',
      // signParamsKey(clienttime)
      'key': KugoSign.signParamsKey('$clienttime'),
    };
    // 反馈 / 上下文字段（有值才带上）。
    if (hash.isNotEmpty) {
      body['hash'] = hash;
      // cur_mark = 当前播放/反馈的歌 hash（上游语义）。
      body['cur_mark'] = hash;
    }
    if (songid.isNotEmpty) body['songid'] = songid;
    if (action == 'play' && playtime > 0) body['playtime'] = playtime;
    // 登录态字段（对齐 KuGouMusicApi personal_fm.js）：
    // kguid 必须等于 userid，不是设备 guid。
    if (useToken) {
      body['token'] = auth.token;
      if (userIdNum != 0) {
        body['userid'] = userIdNum;
        body['kguid'] = userIdNum;
      }
      body['vip_type'] = 0;
    }

    final bodyJson = jsonEncode(body);
    final signedQuery = Map<String, dynamic>.from(query)
      ..['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

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
        '${KugoEndpoints.gateway}${KugoEndpoints.personalRecommend}',
        queryParameters: signedQuery,
        data: bodyJson,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'dfid': device.dfid,
            'clienttime': '$clienttime',
            'mid': device.mid,
            'x-router': KugoEndpoints.personalFmRouter,
            'Cookie': cookieParts.join(';'),
          },
        ),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        lastError = '网络网关拦截（URL过滤），无法访问酷狗';
        return FmPage(
          needLogin: !useToken,
          error: '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点后重试。',
          mode: mode,
          pool: pool,
        );
      }

      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        final msg = useToken ? '私人FM响应无法解析' : '私人FM需要登录后查看';
        lastError = msg;
        return FmPage(needLogin: !useToken, error: msg, mode: mode, pool: pool);
      }

      final body0 = Map<String, dynamic>.from(decoded);
      final status = body0['status'];
      final errRaw = body0['error_code'] ?? body0['err_code'] ?? body0['errcode'];
      final errNum = errRaw is int ? errRaw : int.tryParse('$errRaw') ?? 0;
      final list = _extractList(body0);

      // 未登录 / 空 data（实测 error_code=200101）。
      if (list.isEmpty) {
        final String msg;
        if (errNum == 200101) {
          msg = useToken ? '私人FM暂无推荐' : '登录后可获取私人FM';
        } else {
          final s =
              (body0['msg'] ?? body0['message'] ?? body0['error'] ?? '').toString();
          if (s.contains('登录')) {
            msg = '登录后可获取私人FM';
          } else if (status == 0 && s.isEmpty) {
            msg = useToken ? '私人FM暂无推荐' : '登录后可获取私人FM';
          } else {
            msg = s.isNotEmpty ? s : (useToken ? '私人FM加载失败' : '私人FM需要登录后查看');
          }
        }
        lastError = msg;
        return FmPage(
          needLogin: !useToken,
          error: msg,
          mode: mode,
          pool: pool,
        );
      }

      final tracks = _mapTracks(list, limit: limit, mode: mode);
      if (tracks.isEmpty) {
        final msg = '私人FM暂无可播放歌曲';
        lastError = msg;
        return FmPage(error: msg, mode: mode, pool: pool);
      }
      lastError = '';
      return FmPage(tracks: tracks, fromServer: true, mode: mode, pool: pool);
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      lastError = msg.contains('URL过滤') || msg.contains('Access Deny')
          ? '网络网关拦截（URL过滤），无法访问酷狗'
          : '私人FM网络错误';
      return FmPage(
        needLogin: false,
        error: lastError,
        mode: mode,
        pool: pool,
      );
    } catch (e) {
      lastError = '私人FM异常：$e';
      return FmPage(error: lastError, mode: mode, pool: pool);
    }
  }

  /// 宽容定位歌曲列表：`data` 可能是 Map 或 List，歌曲数组可能在
  /// `data.song_list` / `data.songs` / `data.list` / `data`（List 时）。
  /// 复用 [extractEverydayList]（它已覆盖这些键 + 顶层回退）。
  List<dynamic> _extractList(Map<String, dynamic> body) {
    // 先特判 `data` 本身是 List（私人 FM 常见：data 直接是歌曲数组）。
    final data = body['data'];
    if (data is List) return data;
    return extractEverydayList(body);
  }

  /// 测试用：直接把已解码的网关 JSON 解析成 [FmPage]，不发网络请求。
  @visibleForTesting
  FmPage debugParseForTest(
    Map<String, dynamic> body, {
    FmMode mode = FmMode.heart,
    FmSongPool pool = FmSongPool.taste,
  }) {
    final body0 = Map<String, dynamic>.from(body);
    final list = _extractList(body0);
    if (list.isEmpty) {
      return FmPage(error: 'empty', mode: mode, pool: pool);
    }
    final tracks = _mapTracks(list, limit: 30, mode: mode);
    return FmPage(
      tracks: tracks,
      fromServer: tracks.isNotEmpty,
      mode: mode,
      pool: pool,
    );
  }

  List<Track> _mapTracks(List<dynamic> list, {required int limit, required FmMode mode}) {
    final mapped = <Track>[];
    final seen = <String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final track = _mapFmSong(Map<String, dynamic>.from(item));
      if (track.hash.isEmpty && track.name == '未知歌曲') continue;
      final key = track.id.isNotEmpty ? track.id : track.hash;
      if (key.isEmpty || !seen.add(key)) continue;
      mapped.add(track);
    }

    if (mode.preferShort) {
      final short = _preferShort(mapped);
      if (short.isNotEmpty) {
        mapped
          ..clear()
          ..addAll(short);
      }
    }
    if (limit > 0 && mapped.length > limit) {
      return mapped.sublist(0, limit);
    }
    return mapped;
  }

  /// 本地时长过滤（速览档）：优先保留 ≤4 分钟的短曲；短曲不足时保留全部，
  /// 避免过度过滤导致空列表。
  List<Track> _preferShort(List<Track> tracks) {
    const maxMs = 4 * 60 * 1000;
    final short =
        tracks.where((t) => t.durationMs == 0 || t.durationMs <= maxMs).toList();
    return short.length >= 5 ? short : tracks;
  }

  /// 复用 [mapEverydaySong] 的健壮扁平化映射，再补齐 recDesc / similarDesc /
  /// language 三个私人 FM 专有字段。
  Track _mapFmSong(Map<String, dynamic> json) {
    final base = mapEverydaySong(json);
    final sources = <Map<String, dynamic>>[
      json,
      _asMap(json['base']),
      _asMap(json['audio_info']),
      _asMap(json['rec_song_info']),
      _asMap(json['album_info']),
    ];
    return base.copyWith(
      recDesc: _pickStr(sources, [
        'recDesc',
        'rec_desc',
        'recReason',
        'rec_reason',
        'recommend_reason',
        'reason',
      ]),
      similarDesc: _pickStr(sources, [
        'similarDesc',
        'similar_desc',
        'similar_reason',
      ]),
      language: _pickStr(sources, [
        'language',
        'lang',
        'Language',
      ]),
    );
  }
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

String _pickStr(List<Map<String, dynamic>> sources, List<String> keys) {
  for (final key in keys) {
    for (final src in sources) {
      final v = src[key];
      if (v == null || v is Map || v is List) continue;
      final t = v.toString().trim();
      if (t.isEmpty || t == 'null') continue;
      return t;
    }
  }
  return '';
}

final fmRepository = FmRepository();
