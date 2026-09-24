import 'dart:convert';

import 'package:dio/dio.dart';


import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl;
import '../../core/api/network_log.dart';
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';

class SongComment {
  const SongComment({
    required this.id,
    required this.user,
    required this.content,
    required this.likeCount,
    this.avatarUrl = '',
    this.timeLabel = '',
  });

  final String id;
  final String user;
  final String content;
  final int likeCount;
  final String avatarUrl;
  final String timeLabel;
}

/// Song comments — port of KuGouMusicApi `comment_music.js`
/// (POST gateway `/mcomment/v1/cmtlist`, android signature, no x-router).
class SongDetailRepository {
  SongDetailRepository({Dio? dio}) : _dio = dio ?? _createDio() {
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
            // Risk control only signals itself through this header.
            final ssaCode = res.headers.value('ssa-code');
            _emit(
              NetworkLog(
                id: res.requestOptions.extra['__id'] as String? ??
                    res.requestOptions.uri.toString(),
                type: NetworkLogType.response,
                timestamp: DateTime.now(),
                method: res.requestOptions.method,
                url: res.requestOptions.uri.toString(),
                statusCode: res.statusCode,
                data: truncateLogData(
                  ssaCode == null || ssaCode.isEmpty
                      ? res.data
                      : 'ssa-code: $ssaCode\n${res.data}',
                ),
                duration: Duration(
                  milliseconds: DateTime.now().millisecondsSinceEpoch - start,
                ),
              ),
            );
            handler.next(res);
          },
          onError: (err, handler) {
            _emit(
              NetworkLog(
                id: err.requestOptions.extra['__id'] as String? ??
                    err.requestOptions.uri.toString(),
                type: NetworkLogType.error,
                timestamp: DateTime.now(),
                method: err.requestOptions.method,
                url: err.requestOptions.uri.toString(),
                statusCode: err.response?.statusCode,
                data: truncateLogData(err.response?.data),
                errorMessage: err.message ?? err.toString(),
              ),
            );
            handler.next(err);
          },
        ),
      );
    }
  }

  
  static void _emit(NetworkLog log) => NetworkLogHub.emit(log);

  final Dio _dio;
  String lastError = '';

  /// `ssa-code` response header of the last request (risk-control event id).
  String lastSsaCode = '';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        // Business errors come back as HTTP 200 + JSON status/err_code.
        validateStatus: (code) => code != null && code >= 200 && code < 500,
      ),
    );
  }

  Future<List<SongComment>> fetchComments({
    required String mixSongId,
    int page = 1,
    int pageSize = 20,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final id = mixSongId.trim();
    if (id.isEmpty || id == '0') {
      lastError = '缺少歌曲 ID';
      return const [];
    }

    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;

    // SSA 20028: stale/reinstall token is rejected — same fallback as play_url.
    Future<List<SongComment>> attempt({
      required bool post,
      required bool withAuth,
    }) async {
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final useToken = withAuth && auth.hasToken;
      final userId =
          withAuth && auth.userId.isNotEmpty && auth.userId != '0'
              ? auth.userId
              : '';
      final params = <String, dynamic>{
        'dfid': device.dfid,
        'mid': device.mid,
        'uuid': '-',
        'appid': int.parse(KugoSign.appId),
        'clientver': int.parse(KugoSign.clientVer),
        'clienttime': clienttime,
        if (useToken) 'token': auth.token,
        if (userId.isNotEmpty)
          'userid': int.tryParse(userId) ?? userId,
        // comment_music.js — exact fields
        'mixsongid': int.tryParse(id) ?? id,
        'need_show_image': 1,
        'p': page,
        'pagesize': pageSize,
        'show_classify': 1,
        'show_hotword_list': 1,
        'extdata': '0',
        'code': 'fc4be23b4e972707f36b8a828a93ba8a',
      };
      params['signature'] = KugoSign.signatureAndroidParams(params);

      final cookieParts = <String>[
        if (useToken) 'token=${auth.token}',
        if (userId.isNotEmpty) 'userid=$userId',
        'dfid=${device.dfid}',
        'KUGOU_API_MID=${device.mid}',
        'KUGOU_API_GUID=${device.guid}',
      ];
      final headers = <String, String>{
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': device.dfid,
        'clienttime': '$clienttime',
        'mid': device.mid,
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        if (cookieParts.isNotEmpty) 'Cookie': cookieParts.join(';'),
      };

      final res = post
          ? await _dio.post<dynamic>(
              'https://gateway.kugou.com/mcomment/v1/cmtlist',
              queryParameters: params,
              data: '',
              options: Options(headers: headers),
            )
          : await _dio.get<dynamic>(
              'https://gateway.kugou.com/mcomment/v1/cmtlist',
              queryParameters: params,
              options: Options(headers: headers),
            );

      lastSsaCode = res.headers.value('ssa-code') ?? '';

      final raw = res.data?.toString() ?? '';
      Map<String, dynamic>? body;
      try {
        final text = raw.trim();
        if (text.startsWith('{') || text.startsWith('[')) {
          final decoded = jsonDecode(text);
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}

      if (body == null) {
        if (raw.contains('Access Deny') || raw.contains('URL过滤')) {
          lastError = '评论接口被拒绝（Access Deny）';
        } else if (raw.isEmpty) {
          lastError = '评论响应为空';
        } else {
          lastError = '评论响应无法解析';
        }
        return const [];
      }

      final status = body['status'];
      final err = body['err_code'] ?? body['errcode'] ?? body['error_code'];
      final errNum = err is int ? err : int.tryParse('$err') ?? 0;
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg = (body['msg'] ?? body['message'] ?? body['error'] ?? '')
            .toString();
        if (errNum == 20028 || msg.contains('20028')) {
          lastError = useToken
              ? '登录态触发安全校验（SSA 20028），请重新登录后再试'
              : '评论需要安全校验（SSA 20028）';
        } else if (errNum == 10002 || msg.contains('参数错误')) {
          lastError = '评论参数无效（mixsongid=$id）';
        } else if (msg.contains('signature')) {
          lastError = '评论签名校验失败';
        } else {
          lastError = msg.isEmpty
              ? '评论加载失败（status=$status err=$err）'
              : msg;
        }
        return const [];
      }

      final list = _parseComments(body);
      if (list.isEmpty) {
        lastError = '';
        return const [];
      }
      return list;
    }

    try {
      final withAuth = auth.hasToken;
      var list = await attempt(post: true, withAuth: withAuth);
      if (list.isNotEmpty) return list;

      // The guest fallbacks below overwrite lastError, which would hide a
      // logged-in SSA failure behind the guest wording — remember it.
      final tokenError = withAuth ? lastError : '';

      final err = lastError;
      final ssa = err.contains('20028') || err.contains('SSA');
      final badAuth = ssa || err.contains('signature');

      // Guest-sign retry (no token) — comments are public on official params.
      if (withAuth && badAuth) {
        list = await attempt(post: true, withAuth: false);
        if (list.isNotEmpty) return list;
      }

      // GET fallback with the last-used auth mode.
      if (list.isEmpty && !lastError.contains('参数无效')) {
        list = await attempt(post: false, withAuth: false);
      }
      if (list.isEmpty &&
          tokenError.isNotEmpty &&
          lastError.contains('评论需要安全校验')) {
        lastError = tokenError;
      }
      return list;
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      if (msg.contains('Access Deny') || msg.contains('URL过滤')) {
        lastError = '网络网关拦截，无法加载评论';
      } else {
        lastError = msg.isEmpty ? '网络错误' : msg.split('\n').first;
      }
      return const [];
    }
  }

  List<SongComment> _parseComments(Map<String, dynamic> body) {
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final list = data['list'] ??
        data['info'] ??
        data['comments'] ??
        body['list'] ??
        body['info'];
    if (list is! List) return const [];

    final out = <SongComment>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final content = (m['content'] ??
              m['comment'] ??
              m['body'] ??
              m['pcontent'] ??
              '')
          .toString()
          .trim();
      if (content.isEmpty) continue;
      final user = (m['user_name'] ??
              m['uname'] ??
              m['username'] ??
              m['nickname'] ??
              '用户')
          .toString();
      final avatarRaw = (m['user_pic'] ??
              m['pic'] ??
              m['avatar'] ??
              m['user_pic'] ??
              '')
          .toString();

      var likeCount = 0;
      final like = m['like'];
      if (like is Map) {
        final lm = Map<String, dynamic>.from(like);
        final v = lm['likenum'] ?? lm['count'] ?? lm['like_num'] ?? 0;
        likeCount = v is int ? v : int.tryParse('$v') ?? 0;
      } else {
        final v = m['like_num'] ?? m['likenum'] ?? m['praise_num'] ?? 0;
        likeCount = v is int ? v : int.tryParse('$v') ?? 0;
      }

      final time = (m['addtime'] ??
              m['create_time'] ??
              m['time'] ??
              '')
          .toString();

      out.add(
        SongComment(
          id: (m['id'] ?? m['comment_id'] ?? out.length).toString(),
          user: user,
          content: content,
          likeCount: likeCount,
          avatarUrl: avatarRaw.isEmpty
              ? ''
              : normalizeCoverUrl(avatarRaw, size: '100'),
          timeLabel: _formatTime(time),
        ),
      );
    }
    return out;
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    // API often returns "2026-01-14 12:22:10" already.
    if (raw.contains('-') || raw.contains('/')) {
      final parts = raw.split(RegExp(r'[ T]'));
      return parts.isNotEmpty ? parts.first : raw;
    }
    final seconds = int.tryParse(raw);
    if (seconds == null) return raw;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      seconds > 2000000000 ? seconds : seconds * 1000,
    );
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

final songDetailRepository = SongDetailRepository();
