import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl;
import '../../core/api/network_log.dart';
import '../../core/models/comment.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

/// 酷狗评论（读侧）。上游口径：
///
/// | 能力 | 请求 | 签名 |
/// |---|---|---|
/// | 全部 | `POST https://gateway.kugou.com/mcomment/v1/cmtlist` | android |
/// | 最热 | `POST .../m.comment.service/r/v1/rank/topliked` | android |
/// | 楼层 | `POST .../mcomment/v1/hot_replylist` | android |
/// | 评论数 | `GET .../index.php?r=comments/getcommentsnum` + `x-router: sum.comment.service.kugou.com` | web |
///
/// 两条容易踩的错：
/// 1. 评论数要的是**歌曲 hash**（返回 `{"<hash>": n}`），不是 mixsongid；
///    而「最热」要的是 `childrenid`（评论池），不是 mixsongid。
/// 2. 响应结构是**顶层平铺**（`list` / `count` / `childrenid` 都在顶层），
///    没有 `data` 包裹 —— 但旧版本响应有过 `data` 包裹，解析仍保留兜底。
class CommentRepository {
  CommentRepository({Dio? dio}) : _dio = dio ?? _createDio() {
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
            final start =
                res.requestOptions.extra['__start'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
            // Risk control only signals itself through this header.
            final ssaCode = res.headers.value('ssa-code');
            _emit(
              NetworkLog(
                id:
                    res.requestOptions.extra['__id'] as String? ??
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
                id:
                    err.requestOptions.extra['__id'] as String? ??
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

  static const String _gateway = 'https://gateway.kugou.com';
  static const String _songCode = 'fc4be23b4e972707f36b8a828a93ba8a';
  static const String _cmtListPath = '/mcomment/v1/cmtlist';
  static const String _hottestPath = '/m.comment.service/r/v1/rank/topliked';
  static const String _floorPath = '/mcomment/v1/hot_replylist';
  static const String _countPath = '/index.php';
  static const String _countRouter = 'sum.comment.service.kugou.com';

  final Dio _dio;

  /// 最近一次失败的**用户可读**文案（UI 直接显示）。
  String lastError = '';

  /// 最近一次响应的 `ssa-code`（风控事件 id）。
  String lastSsaCode = '';

  /// mixsongid → childrenid（评论池）。同曲切换排序/翻页都要复用。
  final Map<String, String> _childrenIdByMix = {};

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

  /// 歌曲评论分页。[childrenId] 会随返回值带出，供页面缓存后调 [fetchFloorReplies]。
  Future<CommentPage> fetchSongComments({
    required String mixSongId,
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final id = mixSongId.trim();
    if (id.isEmpty || id == '0') {
      lastError = '缺少歌曲 ID';
      return CommentPage.empty;
    }

    if (sort == CommentSort.hottest) {
      var childrenId = _childrenIdByMix[id] ?? '';
      if (childrenId.isEmpty) {
        // 最热接口只认评论池 id，而它只能从 cmtlist 响应里拿 —— 先垫一次。
        final primer = await _requestPage(
          path: _cmtListPath,
          page: 1,
          pageSize: 1,
          business: _songBusiness(mixSongId: id),
        );
        childrenId = primer?.childrenId ?? '';
      }
      if (childrenId.isEmpty) {
        lastError = lastError.isEmpty ? '评论池未知，无法按最热排序' : lastError;
        return CommentPage.empty;
      }
      _childrenIdByMix[id] = childrenId;
      final hottest = await _requestPage(
        path: _hottestPath,
        page: page,
        pageSize: pageSize,
        business: {
          'childrenid': childrenId,
          'mixsongid': _asNumber(id) ?? id,
          'code': _songCode,
        },
      );
      if (hottest == null) return CommentPage.empty;
      // 最热接口不一定回 `childrenid`，缺了就补上已知的 —— 否则切到「最热」后
      // 楼层会因为拿不到评论池 id 而失效。
      return hottest.childrenId.isEmpty
          ? CommentPage(
              items: hottest.items,
              total: hottest.total,
              childrenId: childrenId,
              maxPage: hottest.maxPage,
            )
          : hottest;
    }

    final result = await _requestPage(
      path: _cmtListPath,
      page: page,
      pageSize: pageSize,
      business: _songBusiness(mixSongId: id),
    );
    final pageData = result ?? CommentPage.empty;
    // 评论池 id 只在 cmtlist 里出现，拿到就存，供「最热」复用。
    if (pageData.childrenId.isNotEmpty) {
      _childrenIdByMix[id] = pageData.childrenId;
    }
    return pageData;
  }

  /// 楼层回复（某条主评论下的回复）。
  ///
  /// [childrenId] 必填（评论池 id）；[rootCommentId] 是主评论的 `id`（上游 `tid`）。
  Future<List<Comment>> fetchFloorReplies({
    required String childrenId,
    required String rootCommentId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 20,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final pool = childrenId.trim();
    final root = rootCommentId.trim();
    if (pool.isEmpty || root.isEmpty) {
      lastError = '楼层参数缺失，请刷新评论后重试';
      return const [];
    }
    final pageResult = await _requestPage(
      path: _floorPath,
      page: page,
      pageSize: pageSize,
      business: {
        'childrenid': pool,
        'tid': _asNumber(root) ?? root,
        if (mixSongId.trim().isNotEmpty)
          'mixsongid': _asNumber(mixSongId.trim()),
        'need_show_image': 1,
        'show_classify': 1,
        'show_hotword_list': 1,
        'code': _songCode,
      },
    );
    return pageResult?.items ?? const [];
  }

  /// 评论数。入参是**音频 hash**，返回 null = 无数据 / 失败（UI 显示「—」）。
  ///
  /// 实测：`{"<hash>": 706580}`，与列表接口的 `count` 同口径。
  Future<int?> fetchCommentCount({required String hash}) async {
    lastError = '';
    final h = hash.trim();
    if (h.isEmpty) return null;
    final params = <String, dynamic>{
      'r': 'comments/getcommentsnum',
      'code': _songCode,
      'hash': h,
    };
    params['signature'] = KugoSign.signatureWebParams(params);
    try {
      final res = await _dio.get<dynamic>(
        '$_gateway$_countPath',
        queryParameters: params,
        options: Options(
          headers: {'User-Agent': KugoSign.userAgent, 'x-router': _countRouter},
        ),
      );
      final body = _decodeBody(res.data);
      if (body == null) return null;
      // 正常形态是 `{"<hash>": 706580}` —— 键就是 hash 本身。
      final byHash = _firstInt(body[h]);
      if (byHash != null) return byHash;
      final data = body['data'];
      if (data is Map) {
        final nested = _firstInt(data[h]);
        if (nested != null) return nested;
      }
      return _pickNumber(body, const ['count', 'comments_num']);
    } on DioException {
      return null;
    }
  }

  // ── 请求 ────────────────────────────────────────────────

  Map<String, dynamic> _songBusiness({required String mixSongId}) => {
    'mixsongid': _asNumber(mixSongId) ?? mixSongId,
    'need_show_image': 1,
    'show_classify': 1,
    'show_hotword_list': 1,
    'extdata': '0',
    'code': _songCode,
  };

  /// 列表族请求（android 签名）：POST 优先，POST 拿不到数据时回退 GET。
  ///
  /// 返回 null = 失败（[lastError] 已写好文案）。
  Future<CommentPage?> _requestPage({
    required String path,
    required int page,
    required int pageSize,
    required Map<String, dynamic> business,
  }) async {
    final withAuth = AuthTokenHolder.instance.hasToken;
    var result = await _attempt(
      path: path,
      page: page,
      pageSize: pageSize,
      business: business,
      post: true,
      withAuth: withAuth,
    );
    if (result != null && result.items.isNotEmpty) return result;
    if (result != null && result.items.isEmpty && lastError.isEmpty) {
      // 服务端明确回了「空列表」：不再折腾 GET，交给 UI 出空态。
      return result;
    }

    // 登录态触发风控（SSA 20028）或签名被拒 → 用游客签名重试一次。
    final tokenError = withAuth ? lastError : '';
    final ssa = lastError.contains('20028') || lastError.contains('SSA');
    if (withAuth && (ssa || lastError.contains('signature'))) {
      result = await _attempt(
        path: path,
        page: page,
        pageSize: pageSize,
        business: business,
        post: true,
        withAuth: false,
      );
      if (result != null && result.items.isNotEmpty) return result;
    }

    if (!lastError.contains('参数无效')) {
      result = await _attempt(
        path: path,
        page: page,
        pageSize: pageSize,
        business: business,
        post: false,
        withAuth: false,
      );
      if (result != null && result.items.isNotEmpty) return result;
    }

    // 游客兜底会覆盖掉登录态的真实原因，还原它，避免误导。
    if (tokenError.isNotEmpty && lastError.contains('需要安全校验')) {
      lastError = tokenError;
    }
    return result;
  }

  Future<CommentPage?> _attempt({
    required String path,
    required int page,
    required int pageSize,
    required Map<String, dynamic> business,
    required bool post,
    required bool withAuth,
  }) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final useToken = withAuth && auth.hasToken;
    final userId = withAuth && auth.userId.isNotEmpty && auth.userId != '0'
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
      if (userId.isNotEmpty) 'userid': int.tryParse(userId) ?? userId,
      'p': page,
      'pagesize': pageSize,
      ...business,
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

    try {
      final res = post
          ? await _dio.post<dynamic>(
              '$_gateway$path',
              queryParameters: params,
              data: '',
              options: Options(headers: headers),
            )
          : await _dio.get<dynamic>(
              '$_gateway$path',
              queryParameters: params,
              options: Options(headers: headers),
            );

      lastSsaCode = res.headers.value('ssa-code') ?? '';

      final body = _decodeBody(res.data);
      if (body == null) {
        if (lastError.isEmpty) {
          final raw = res.data?.toString() ?? '';
          if (raw.contains('Access Deny') || raw.contains('URL过滤')) {
            lastError = '评论接口被拒绝（Access Deny）';
          } else if (raw.isEmpty) {
            lastError = '评论响应为空';
          } else {
            lastError = '评论响应无法解析';
          }
        }
        return null;
      }

      final status = body['status'];
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        _mapError(body);
        return null;
      }

      return CommentPage(
        items: _parseComments(body),
        total: _pickNumber(body, const ['count', 'total']) ?? 0,
        childrenId: _stringOf(
          body['childrenid'] ??
              (body['data'] is Map
                  ? (body['data'] as Map)['childrenid']
                  : null),
        ),
        maxPage: _firstInt(body['maxPage']) ?? 0,
      );
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      lastError = msg.contains('Access Deny') || msg.contains('URL过滤')
          ? '网络网关拦截，无法加载评论'
          : (msg.isEmpty ? '网络错误' : msg.split('\n').first);
      return null;
    }
  }

  void _mapError(Map<String, dynamic> body) {
    final err = body['err_code'] ?? body['errcode'] ?? body['error_code'];
    final errNum = err is int ? err : int.tryParse('$err') ?? 0;
    final msg = (body['msg'] ?? body['message'] ?? body['error'] ?? '')
        .toString();
    if (errNum == 20028 || msg.contains('20028')) {
      lastError = AuthTokenHolder.instance.hasToken
          ? '登录态触发安全校验（SSA 20028），请重新登录后再试'
          : '评论需要安全校验（SSA 20028）';
    } else if (errNum == 10002 || msg.contains('参数错误')) {
      lastError = '评论参数无效';
    } else if (msg.contains('signature')) {
      lastError = '评论签名校验失败';
    } else {
      lastError = msg.isEmpty
          ? '评论加载失败（status=${body['status']} err=$err）'
          : msg;
    }
  }

  // ── 解析 ────────────────────────────────────────────────

  List<Comment> _parseComments(Map<String, dynamic> body) {
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final list =
        data['list'] ??
        data['info'] ??
        data['comments'] ??
        body['list'] ??
        body['info'];
    if (list is! List) return const [];

    final out = <Comment>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final content =
          (m['content'] ?? m['comment'] ?? m['body'] ?? m['pcontent'] ?? '')
              .toString()
              .trim();
      if (content.isEmpty) continue;
      final user =
          (m['user_name'] ??
                  m['uname'] ??
                  m['username'] ??
                  m['nickname'] ??
                  '用户')
              .toString();
      final avatarRaw = (m['user_pic'] ?? m['pic'] ?? m['avatar'] ?? '')
          .toString();

      out.add(
        Comment(
          id: (m['id'] ?? m['comment_id'] ?? out.length).toString(),
          user: user,
          userId: (m['user_id'] ?? m['userid'] ?? m['uid'] ?? '').toString(),
          content: content,
          likeCount: _likeCount(m),
          avatarUrl: avatarRaw.isEmpty
              ? ''
              : normalizeCoverUrl(avatarRaw, size: '100'),
          timeLabel: _formatTime(
            (m['addtime'] ?? m['create_time'] ?? m['time'] ?? '').toString(),
          ),
          replyCount:
              _firstInt(
                m['reply_num'] ?? m['reply_count'] ?? m['comments_num'],
              ) ??
              0,
          location: (m['location'] ?? m['ip_location'] ?? '').toString(),
        ),
      );
    }
    return out;
  }

  static int _likeCount(Map<String, dynamic> item) {
    final like = item['like'];
    if (like is Map) {
      final m = Map<String, dynamic>.from(like);
      return _firstInt(m['likenum'] ?? m['count'] ?? m['like_num']) ?? 0;
    }
    return _firstInt(
          item['like_num'] ?? item['likenum'] ?? item['praise_num'],
        ) ??
        0;
  }

  static String _formatTime(String raw) {
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
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  // ── 小工具 ──────────────────────────────────────────────

  static Map<String, dynamic>? _decodeBody(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    if (!text.startsWith('{') && !text.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// 严格按 key 取数字：先顶层，再 `data` 下，找不到返回 null。
  ///
  /// **不做全量扫描** —— 响应里有 `status: 1`、`current_page: 1` 这类字段，
  /// 扫出来的「第一个 int」会把总数算成 1。
  static int? _pickNumber(Map<String, dynamic> body, List<String> keys) {
    for (final key in keys) {
      final parsed = _firstInt(body[key]);
      if (parsed != null) return parsed;
    }
    final data = body['data'];
    if (data is Map) {
      for (final key in keys) {
        final parsed = _firstInt(data[key]);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static int? _firstInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    if (value is Map) {
      for (final v in value.values) {
        final parsed = _firstInt(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String _stringOf(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return (text == 'null' || text == '0') ? '' : text;
  }

  /// 数字型 id 用 int 传（上游对 `mixsongid` 等有类型容忍，但 int 更稳）。
  static Object? _asNumber(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v) ?? v;
  }
}

final commentRepository = CommentRepository();
