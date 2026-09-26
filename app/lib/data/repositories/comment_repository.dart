import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl;
import '../../core/api/network_log.dart';
import '../../core/models/comment.dart';
import '../../core/source/music_source.dart';
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
  static const String _classifyPath = '/mcomment/v1/cmt_classify_list';
  static const String _hotwordPath = '/mcomment/v1/get_hot_word';

  /// 精彩评论：URL 由 `cmtlist` 响应的 `weightListFullApi` 给出，走服务名前缀写法。
  ///
  /// 实测：游客态返回 `status=1` 但列表为空（响应里带
  /// `tipOfNoUseArtCmt: 该功能仅对部分用户开放喔`），所以**空就是空**，UI 不显示该区块。
  static const String _featuredPath = '/m.comment.service/v1/weightlist';

  /// 弹幕：走 `index.php`，且是**另一个评论池**（code 与评论不同）。
  static const String _barrageR = 'comments/getCommentWithLike';
  static const String _barrageCode = 'articulossong';

  /// `index.php` 是评论数**和**评论写口共用的入口，靠 `x-router` 分流。
  static const String _indexPath = '/index.php';

  /// 评论数用的 host（**注意与下面的写口 host 不是同一个**）。
  static const String _countRouter = 'sum.comment.service.kugou.com';

  /// 写口（发评论 / 回复楼层）的 host。
  static const String _commentRouter = 'm.comment.service.kugou.com';

  /// 评论正文上限。EchoMusic 自定 200 字；服务端另有一道 `10003 发送字数不够` 兜底。
  static const int maxContentLength = 200;

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

    if (sort == CommentSort.barrage) {
      var pool = _childrenIdByMix[id] ?? '';
      if (pool.isEmpty) {
        // 弹幕按评论池分池，池 id 同样只能从 cmtlist 响应里取 —— 先垫一次。
        final primer = await _requestPage(
          path: _cmtListPath,
          page: 1,
          pageSize: 1,
          business: _songBusiness(mixSongId: id),
        );
        pool = primer?.childrenId ?? '';
      }
      if (pool.isEmpty) {
        lastError = lastError.isEmpty ? '评论池未知，无法加载弹幕' : lastError;
        return CommentPage.empty;
      }
      _childrenIdByMix[id] = pool;
      return _fetchBarrage(
        childrenId: pool,
        mixSongId: id,
        page: page,
        pageSize: pageSize,
      );
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
        '$_gateway$_indexPath',
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

  /// 分类评论（选中「歌曲相关」这类 chip 后取数）。
  Future<CommentPage> fetchClassifyComments({
    required String mixSongId,
    required String typeId,
    int page = 1,
    int pageSize = 20,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final id = mixSongId.trim();
    final type = typeId.trim();
    if (id.isEmpty || type.isEmpty) {
      lastError = '分类参数缺失';
      return CommentPage.empty;
    }
    final result = await _requestPage(
      path: _classifyPath,
      page: page,
      pageSize: pageSize,
      business: {
        'mixsongid': _asNumber(id) ?? id,
        'need_show_image': 1,
        'type_id': _asNumber(type) ?? type,
        'extdata': '0',
        'code': _songCode,
        // 上游：`sort` 传 2 才用 2，否则一律 1。
        'sort_method': 1,
      },
    );
    return result ?? CommentPage.empty;
  }

  /// 热词评论（点热词 chip 后取数）。
  Future<CommentPage> fetchHotwordComments({
    required String mixSongId,
    required String hotWord,
    int page = 1,
    int pageSize = 20,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final id = mixSongId.trim();
    final word = hotWord.trim();
    if (id.isEmpty || word.isEmpty) {
      lastError = '热词参数缺失';
      return CommentPage.empty;
    }
    final result = await _requestPage(
      path: _hotwordPath,
      page: page,
      pageSize: pageSize,
      business: {
        'mixsongid': _asNumber(id) ?? id,
        'need_show_image': 1,
        'hot_word': word,
        'extdata': '0',
        'code': _songCode,
      },
    );
    return result ?? CommentPage.empty;
  }

  /// 精彩评论。**空列表是正常结果**（游客态实测拿不到，响应里带
  /// 「该功能仅对部分用户开放」），所以 UI 拿到空就不显示这一块。
  Future<List<Comment>> fetchFeaturedComments({
    required String childrenId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 10,
  }) async {
    lastError = '';
    lastSsaCode = '';
    final pool = childrenId.trim();
    if (pool.isEmpty) return const [];
    final result = await _requestPage(
      path: _featuredPath,
      page: page,
      pageSize: pageSize,
      business: {
        'childrenid': _asNumber(pool) ?? pool,
        if (mixSongId.trim().isNotEmpty)
          'mixsongid': _asNumber(mixSongId.trim()),
        'code': _songCode,
      },
    );
    return result?.items ?? const [];
  }

  /// 弹幕（另一个评论池）。走 `index.php` + `key`，`key` 只算 `clienttime`。
  Future<CommentPage> _fetchBarrage({
    required String childrenId,
    required String mixSongId,
    required int page,
    required int pageSize,
  }) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = _nowSeconds();
    try {
      final body = await _postIndex(
        query: <String, dynamic>{
          'r': _barrageR,
          'code': _barrageCode,
          'childrenid': _asNumber(childrenId) ?? childrenId,
          if (mixSongId.trim().isNotEmpty)
            'mixsongid': _asNumber(mixSongId.trim()),
          'p': page,
          'pagesize': pageSize,
          'kugouid': _kugouId(auth),
          'ver': 6,
          'clienttoken': auth.token,
          'appid': int.parse(KugoSign.appId),
          'clientver': int.parse(KugoSign.clientVer),
          'mid': device.mid,
          'clienttime': clienttime,
          'key': KugoSign.signParamsKey('$clienttime'),
          'uuid': '-',
          'dfid': device.dfid,
        },
        dfid: device.dfid,
        mid: device.mid,
        clienttime: clienttime,
      );
      final status = body['status'];
      if (!(status == 1 || status == '1' || status == true)) {
        _mapError(body);
        return CommentPage.empty;
      }
      return CommentPage(
        items: _parseComments(body),
        total: _pickNumber(body, const ['count', 'total']) ?? 0,
        childrenId: _stringOf(body['childrenid']),
      );
    } on SourceFailure catch (e) {
      // 读侧约定是「返回空 + lastError」，不往上抛。
      lastError = e.message;
      return CommentPage.empty;
    }
  }

  // ── 写侧（发评论 / 回复楼层） ────────────────────────────
  //
  // 走 `index.php` + `x-router: m.comment.service.kugou.com`：这条链路
  // **不吃 `signature`、也不注入公共参数**，只带显式字段 + 上游约定的 `key`。
  // 实测（空正文对照实验）：正确 key → `10003 发送字数不够`（说明链路与签名都过），
  // 故意写错 key → `20006 参数验证失败`（说明 key 确实被校验）。

  /// 发表歌曲评论。未登录 / 参数非法 / 被风控都会抛 [SourceFailure]。
  Future<void> sendSongComment({
    required String childrenId,
    required String content,
    String songName = '',
    String mixSongId = '',
  }) async {
    _requireLogin();
    final text = _validatedContent(content);
    final pool = childrenId.trim();
    if (pool.isEmpty) {
      throw const NotFound('评论池未知，请刷新评论后再试');
    }

    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = _nowSeconds();
    // body 参与 key 计算，必须与提交的字符串逐字节一致 —— 所以这里先编码好再用。
    final payload = jsonEncode({
      'data': {
        'content': text,
        if (mixSongId.trim().isNotEmpty)
          'album_audio_id': _asNumber(mixSongId.trim()),
      },
    });

    final body = await _postIndex(
      query: <String, dynamic>{
        'r': 'commentsv3/add',
        'code': _songCode,
        'childrenid': _asNumber(pool) ?? pool,
        if (songName.trim().isNotEmpty) 'childrenname': songName.trim(),
        'kugouid': _kugouId(auth),
        'ver': 6,
        'clienttoken': auth.token,
        'appid': int.parse(KugoSign.appId),
        'clientver': int.parse(KugoSign.clientVer),
        'mid': device.mid,
        'clienttime': clienttime,
        'key': KugoSign.signParamsKey('$clienttime${device.mid}$payload'),
        'uuid': '-',
        'dfid': device.dfid,
      },
      body: payload,
      dfid: device.dfid,
      mid: device.mid,
      clienttime: clienttime,
    );
    _assertWriteOk(body, what: '评论');
  }

  /// 回复某条主评论（楼层）。
  ///
  /// 与发评论的两点差异：**key 只算 `clienttime + mid`**（正文走 query、无 body），
  /// 且 [replyToUser] 非空时按上游约定把正文拼成 `//@昵称:被回复内容`。
  Future<void> sendFloorReply({
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
    String songName = '',
    String mixSongId = '',
  }) async {
    _requireLogin();
    final pool = childrenId.trim();
    final root = rootCommentId.trim();
    if (pool.isEmpty || root.isEmpty) {
      throw const NotFound('楼层信息不完整，请刷新评论后再试');
    }

    var text = content.trim();
    if (text.isEmpty) throw const UpstreamChanged('回复内容不能为空');
    if (replyToUser.trim().isNotEmpty &&
        replyToContent.trim().isNotEmpty &&
        !text.contains('//@')) {
      text = '$text//@${replyToUser.trim()}:${replyToContent.trim()}';
    }
    text = _validatedContent(text);

    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = _nowSeconds();

    final body = await _postIndex(
      query: <String, dynamic>{
        'r': 'commentsv2/reply',
        'code': _songCode,
        'childrenid': _asNumber(pool) ?? pool,
        if (songName.trim().isNotEmpty) 'childrenname': songName.trim(),
        'kugouid': _kugouId(auth),
        'ver': 6,
        'clienttoken': auth.token,
        'appid': int.parse(KugoSign.appId),
        'clientver': int.parse(KugoSign.clientVer),
        'mid': device.mid,
        'clienttime': clienttime,
        'key': KugoSign.signParamsKey('$clienttime${device.mid}'),
        'uuid': '-',
        'dfid': device.dfid,
        if (mixSongId.trim().isNotEmpty)
          'mixsongid': _asNumber(mixSongId.trim()),
        'extdata': '0',
        'content': text,
        'tid': _asNumber(root) ?? root,
        // P1 只做「在主评论下发一条新回复」：is_t=1 / pid=0（回复楼层内的回复另议）。
        'is_t': 1,
        'pid': 0,
      },
      dfid: device.dfid,
      mid: device.mid,
      clienttime: clienttime,
    );
    _assertWriteOk(body, what: '回复');
  }

  /// 写口专用通道（`index.php` + `x-router`，无 `signature`、无公共参数）。
  Future<Map<String, dynamic>> _postIndex({
    required Map<String, dynamic> query,
    required String dfid,
    required String mid,
    required int clienttime,
    String? body,
  }) async {
    final auth = AuthTokenHolder.instance;
    final cookieParts = <String>[
      if (auth.hasToken) 'token=${auth.token}',
      if (auth.userId.isNotEmpty) 'userid=${auth.userId}',
      'dfid=$dfid',
      'KUGOU_API_MID=$mid',
      'KUGOU_API_GUID=${auth.guid}',
    ];
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        '$_gateway$_indexPath',
        queryParameters: query,
        data: body ?? '',
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json; charset=UTF-8',
            'x-router': _commentRouter,
            'dfid': dfid,
            'mid': mid,
            'clienttime': '$clienttime',
            'Cookie': cookieParts.join(';'),
          },
        ),
      );
    } on DioException catch (e) {
      final msg = e.message ?? '';
      throw NetworkFailure(
        msg.contains('过滤') || msg.contains('Access Deny')
            ? '网络网关拦截，无法发送'
            : (msg.isEmpty ? '网络错误' : msg.split('\n').first),
        filtered: msg.contains('过滤') || msg.contains('Access Deny'),
      );
    }

    final decoded = _decodeBody(res.data);
    if (decoded == null) {
      final raw = res.data?.toString() ?? '';
      if (raw.contains('Access Deny') || raw.contains('URL过滤')) {
        throw const NetworkFailure('网络网关拦截，无法发送', filtered: true);
      }
      throw const UpstreamChanged('评论响应无法解析');
    }
    return decoded;
  }

  void _assertWriteOk(Map<String, dynamic> body, {required String what}) {
    final status = body['status'];
    if (status == 1 || status == '1' || status == true) return;
    final err = body['err_code'] ?? body['errcode'] ?? body['error_code'];
    final errNum = err is int ? err : int.tryParse('$err') ?? 0;
    final msg = (body['msg'] ?? body['message'] ?? '').toString();
    if (errNum == 20028) {
      throw const RateLimited('需要安全校验：请先在酷狗官方客户端完成一次验证，再回来重试');
    }
    if (errNum == 20006) {
      throw const UpstreamChanged('评论参数校验失败（20006）');
    }
    if (errNum == 10003) {
      throw const UpstreamChanged('评论内容长度不合规（10003）');
    }
    if (errNum == 20010 || errNum == 10002) {
      throw UpstreamChanged(msg.isEmpty ? '评论参数不完整（$errNum）' : msg);
    }
    throw UpstreamChanged(
      msg.isEmpty ? '$what发送失败（status=$status err=$err）' : msg,
    );
  }

  static void _requireLogin() {
    if (!AuthTokenHolder.instance.hasToken) {
      throw const LoginRequired('登录后才能发表评论');
    }
  }

  static String _validatedContent(String raw) {
    final text = raw.trim();
    if (text.isEmpty) throw const UpstreamChanged('评论内容不能为空');
    if (text.runes.length > maxContentLength) {
      throw UpstreamChanged('评论最多 $maxContentLength 字，请精简后再发');
    }
    return text;
  }

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static Object _kugouId(AuthTokenHolder auth) {
    final id = auth.userId.trim();
    if (id.isEmpty || id == '0') return 0;
    return int.tryParse(id) ?? 0;
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
        // 只有 cmtlist 首屏会带这两个筛选项，其他接口拿到空数组即可。
        classifyList: _parseFilterOptions(
          body['classify_list'] ??
              (body['data'] is Map
                  ? (body['data'] as Map)['classify_list']
                  : null),
          idKey: 'id',
          labelKey: 'label',
          countKey: 'cnt',
        ),
        hotwordList: _parseFilterOptions(
          body['hot_word_list'] ??
              (body['data'] is Map
                  ? (body['data'] as Map)['hot_word_list']
                  : null),
          idKey: 'content',
          labelKey: 'content',
          countKey: 'count',
        ),
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
          badges: _parseBadges(m),
          talentIcon: _talentIcon(m),
        ),
      );
    }
    return out;
  }

  /// 分类 / 热词筛选项。两个接口的键名不同（分类 `{id,label,cnt}`，热词
  /// `{content,count}`），所以键名由调用方给。
  static List<CommentFilterOption> _parseFilterOptions(
    Object? raw, {
    required String idKey,
    required String labelKey,
    required String countKey,
  }) {
    if (raw is! List) return const [];
    final out = <CommentFilterOption>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = (m[idKey] ?? '').toString().trim();
      final label = (m[labelKey] ?? '').toString().trim();
      if (id.isEmpty || label.isEmpty) continue;
      out.add(
        CommentFilterOption(
          id: id,
          label: label,
          count: _firstInt(m[countKey]) ?? 0,
        ),
      );
    }
    return out;
  }

  // ── 铭牌 / 身份徽标 ────────────────────────────────────
  //
  // 精简移植 EchoMusic `commentVip.ts`（原作对应酷狗 Young 5.1.9 的
  // `com.kugou.android.app.common.comment.utils.o`）。字段全在 cmtlist 单条
  // 评论里（`vip_type` / `m_type` / `y_type` / `vipinfo` / `vinfo9` / `busi_vip`），
  // **不需要额外的批量接口** —— EchoMusic 那个 `user_batch_union_vipinfo`
  // 只是把 busi_vip 补全得更准，P2 先不做。

  static List<CommentBadge> _parseBadges(Map<String, dynamic> m) {
    final vipinfo = m['vipinfo'] is Map
        ? Map<String, dynamic>.from(m['vipinfo'] as Map)
        : const <String, dynamic>{};
    final vinfo9 = m['vinfo9'] is Map
        ? Map<String, dynamic>.from(m['vinfo9'] as Map)
        : const <String, dynamic>{};
    final vipType = _firstInt(m['vip_type']) ?? 0;
    final mType = _firstInt(m['m_type']) ?? 0;
    final yType = _firstInt(m['y_type']) ?? 0;
    final userType =
        _firstInt(vipinfo['user_type'] ?? m['vip_user_type']) ?? -1;
    final userYType = _firstInt(vipinfo['user_y_type']) ?? -1;
    final busi = _busiVip(m, vipinfo);

    final out = <CommentBadge>[];
    final plate = _plateId(
      vipType: vipType,
      mType: mType,
      yType: yType,
      userType: userType,
      userYType: userYType,
      busi: busi,
    );
    final music = _musicKind(mType, yType);
    final vipKind = _vipKindName(plate, music);
    final vipLabel = _vipLabel(vipKind);
    if (vipKind != null && vipLabel != null) {
      out.add(CommentBadge(kind: vipKind, label: vipLabel));
    }

    void addIdentity(Object? raw, String kind, String label) {
      if (_flag(raw)) out.add(CommentBadge(kind: kind, label: label));
    }

    addIdentity(
      vinfo9['student_status'] ?? m['student_status'],
      'student',
      '学生',
    );
    addIdentity(vinfo9['actor_status'] ?? m['actor_status'], 'actor', '演员');
    addIdentity(vinfo9['biz_status'] ?? m['biz_status'], 'biz', '认证');
    addIdentity(
      vinfo9['tme_star_status'] ?? m['tme_star_status'],
      'tme-star',
      '明星',
    );

    // 认证信息（如「歌手」）；达人是头像角标，不重复成 chip。
    final auth = (vinfo9['auth_info'] ?? m['auth_info'] ?? '')
        .toString()
        .trim();
    const avatarIconLabels = {'达人', '演唱者', '歌手'};
    if (auth.isNotEmpty &&
        !avatarIconLabels.contains(auth) &&
        auth != '学生' &&
        !out.any((b) => b.label == auth)) {
      out.add(CommentBadge(kind: 'auth', label: auth));
    }
    return out;
  }

  /// 头像角标：优先 `vinfo9.pic`（达人/演唱者图），只置了标志位时用官方图。
  static String _talentIcon(Map<String, dynamic> m) {
    final vinfo9 = m['vinfo9'] is Map
        ? Map<String, dynamic>.from(m['vinfo9'] as Map)
        : const <String, dynamic>{};
    for (final candidate in [
      vinfo9['pic'],
      vinfo9['t_pic'],
      vinfo9['tpic'],
      vinfo9['t_icon'],
      m['t_pic'],
    ]) {
      final url = _httpUrl(candidate);
      if (url.isNotEmpty) return url;
    }
    if (_flag(vinfo9['cmt_talent_status'] ?? m['cmt_talent_status'])) {
      // 官方达人角标（EchoMusic COMMENT_TALENT_ICON）。
      return 'https://imge.kugou.com/commendpic/20180627/20180627153930257837.png';
    }
    return '';
  }

  static bool _flag(Object? value) =>
      value == true || value == 1 || value == '1';

  static String _httpUrl(Object? value) {
    final url = (value ?? '').toString().trim();
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http')) return url.replaceFirst('http://', 'https://');
    return '';
  }

  static List<Map<String, dynamic>> _busiVip(
    Map<String, dynamic> m,
    Map<String, dynamic> vipinfo,
  ) {
    for (final bucket in [m['busi_vip'], m['busiVip'], vipinfo['busi_vip']]) {
      if (bucket is List) {
        return bucket
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }

  /// `user_type` 的 bit 16 才是超级VIP标志（不是 `svip_level`）。
  static bool _superVipBit(int type) => type >= 0 && (type & 16) > 0;

  static bool _hasBusi(List<Map<String, dynamic>> busi, String productType) =>
      busi.any(
        (e) =>
            _flag(e['is_vip'] ?? e['isVip']) &&
            (e['product_type'] ?? e['productType'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase() ==
                productType,
      );

  /// 铭牌优先级：超级VIP → 概念VIP(svip) → 周卡 → 畅听 → 季卡 → 经典回退。
  static int _plateId({
    required int vipType,
    required int mType,
    required int yType,
    required int userType,
    required int userYType,
    required List<Map<String, dynamic>> busi,
  }) {
    if (_superVipBit(userType)) return _superVipBit(userYType) ? 10 : 9;
    if (_hasBusi(busi, 'svip')) return yType == 1 ? 8 : 7;
    if (_hasBusi(busi, 'wvip')) return 13;
    if (_hasBusi(busi, 'tvip')) return 11;
    if (_hasBusi(busi, 'qvip')) return 12;
    if (yType == 2 || yType == 3) return 6;
    if (vipType >= 1 && vipType <= 4) return mType > 0 ? 2 : 1;
    return vipType == 6 ? 2 : -1;
  }

  static int _musicKind(int mType, int yType) {
    if (yType == 1 || yType == 3) return 5;
    if (mType == 1 || mType == 2) return 3;
    return (mType == 3 || mType == 4) ? 4 : -2;
  }

  /// 图标顺序（原作 `o.w`）；`plate=1` 没有独立图标但官方仍显示 → 归为 VIP。
  static String? _vipKindName(int plate, int music) {
    if (plate == 10) return 'svip-year';
    if (plate == 9) return 'svip';
    if (plate == 8) return 'concept-year';
    if (plate == 7) return 'concept';
    if (plate == 6) return 'vip-year';
    if (music == 5) return 'music-year';
    if (plate == 2) return 'vip';
    if (music == 3 || music == 4) return 'music';
    if (plate == 13) return 'wvip';
    if (plate == 11) return 'changting';
    if (plate == 12) return 'qvip';
    if (plate == 1) return 'vip';
    return null;
  }

  static String? _vipLabel(String? kind) => switch (kind) {
    'svip' || 'svip-year' => '超级VIP',
    'concept' || 'concept-year' => '概念VIP',
    'wvip' => '周卡',
    'changting' => '畅听VIP',
    'qvip' => '季卡',
    'vip-year' => '豪华VIP',
    'vip' => 'VIP',
    'music-year' => '年费音乐包',
    'music' => '音乐包',
    _ => null,
  };

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
