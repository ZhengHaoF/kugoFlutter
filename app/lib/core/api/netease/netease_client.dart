import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../source/music_source.dart';
import 'netease_crypto.dart';
import 'netease_endpoints.dart';
import 'netease_failures.dart';
import '../network_log.dart';

/// 一期探针用网易客户端：加密 + Cookie 会话 + A1–A4。
///
/// 对齐 NeriPlayer `NeteaseClient` 的请求形态；不做完整 CookieJar 持久化。
class NeteaseClient {
  NeteaseClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                // 避免 br：一期用 gzip/deflate 即可。
                headers: {
                  'Accept': '*/*',
                  'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
                  'Accept-Encoding': 'gzip, deflate',
                  'Connection': 'keep-alive',
                  'Referer': NeteaseEndpoints.mainHost,
                  'User-Agent': _ua,
                },
                responseType: ResponseType.plain,
                validateStatus: (c) => c != null && c >= 200 && c < 500,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['__start'] = DateTime.now().millisecondsSinceEpoch;
          options.extra['__id'] =
              '${DateTime.now().microsecondsSinceEpoch}-${options.uri}';
          if (_cookies.isNotEmpty) {
            options.headers['Cookie'] = _cookieHeader();
          }
          NetworkLogHub.emit(
            NetworkLog(
              id: options.extra['__id'] as String,
              type: NetworkLogType.request,
              timestamp: DateTime.now(),
              method: options.method,
              url: options.uri.toString(),
              headers: sanitizeHeaders(options.headers),
              data: truncateLogData(options.data ?? options.queryParameters),
            ),
          );
          handler.next(options);
        },
        onResponse: (res, handler) {
          _absorbSetCookie(res);
          NetworkLogHub.emit(
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
                milliseconds: DateTime.now().millisecondsSinceEpoch -
                    (res.requestOptions.extra['__start'] as int? ??
                        DateTime.now().millisecondsSinceEpoch),
              ),
            ),
          );
          handler.next(res);
        },
      ),
    );
  }

  static const _ua =
      'Mozilla/5.0 (Linux; Android 10; kugo-netease-probe) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final Dio _dio;
  final Map<String, String> _cookies = {
    'os': 'pc',
    'appver': '8.10.35',
    '__remember_me': 'true',
    '_ntes_nuid': _randomHex(32),
    'NMTID': _randomHex(32),
  };
  bool _preheated = false;

  static final Random _rnd = Random.secure();

  static String _randomHex(int len) {
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(_rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  bool get hasLogin => (_cookies['MUSIC_U'] ?? '').isNotEmpty;

  String get csrf => _cookies['__csrf'] ?? '';

  void reset() {
    _cookies
      ..clear()
      ..addAll({
        'os': 'pc',
        'appver': '8.10.35',
        '__remember_me': 'true',
        '_ntes_nuid': _randomHex(32),
        'NMTID': _randomHex(32),
      });
    _preheated = false;
  }

  String _cookieHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _absorbSetCookie(Response res) {
    final raw = res.headers.map['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      final first = line.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty || value == 'deleted') {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  /// GET 首页拿 `__csrf`（WEAPI 前预热）。
  ///
  /// [force] 为 true 时忽略「已预热」标记重新拉一次（B3 重试用）。
  ///
  /// 注意：本环境首页**常无 Set-Cookie**，`__csrf` 一直是空。所以这里只按
  /// 「是否预热过」判断——若再要求 `csrf.isNotEmpty`，每次 weapi 都会白跑一次
  /// 首页 GET（实测一轮探针会多出 14 次），既慢又容易撞风控。
  Future<void> ensureWeapiSession({bool force = false}) async {
    if (!force && _preheated) return;
    try {
      final res = await _dio.get<String>(
        '${NeteaseEndpoints.mainHost}/',
        options: Options(responseType: ResponseType.plain),
      );
      // eslint-disable-next-line — debug: status + set-cookie 数量
      // ignore: avoid_print
      print('[preheat] status=${res.statusCode} '
          'setCookie=${res.headers.map['set-cookie']?.length ?? 0}');
    } catch (e) {
      // ignore: avoid_print
      print('[preheat] failed: $e');
    }
    _preheated = true;
  }

  Future<String> callWeApi(
    String path,
    Map<String, dynamic> params, {
    bool usePersistedCookies = true,
    String host = NeteaseEndpoints.mainHost,
    Map<String, String>? extraHeaders,
  }) {
    final p = path.startsWith('/') ? path : '/$path';
    final full = p.startsWith('/weapi') ? p : '/weapi$p';
    return _request(
      url: '$host$full',
      params: params,
      weapi: true,
      usePersistedCookies: usePersistedCookies,
      extraHeaders: extraHeaders,
    );
  }

  Future<String> callEApi(
    String path,
    Map<String, dynamic> params, {
    bool usePersistedCookies = true,
    String host = NeteaseEndpoints.interfaceHost,
  }) {
    final p = path.startsWith('/') ? path : '/$path';
    final full = p.startsWith('/eapi') ? p : '/eapi$p';
    return _request(
      url: '$host$full',
      params: params,
      weapi: false,
      usePersistedCookies: usePersistedCookies,
    );
  }

  /// weapi 加密但 **完整 URL 自定**（如 `/api/playlist/highquality/tags` 不带 weapi 前缀）。
  Future<String> callWeApiAt(
    String url, {
    Map<String, dynamic> params = const {},
    bool usePersistedCookies = true,
  }) {
    return _request(
      url: url,
      params: params,
      weapi: true,
      usePersistedCookies: usePersistedCookies,
    );
  }

  /// 明文 form（Neri `CryptoMode.API`：歌单/艺人等）。
  Future<String> callPlainApi(
    String path,
    Map<String, dynamic> params, {
    bool usePersistedCookies = true,
    String host = NeteaseEndpoints.mainHost,
  }) {
    final p = path.startsWith('/') ? path : '/$path';
    return _request(
      url: '$host$p',
      params: params,
      weapi: false,
      plain: true,
      usePersistedCookies: usePersistedCookies,
    );
  }

  Future<String> _request({
    required String url,
    required Map<String, dynamic> params,
    required bool weapi,
    bool plain = false,
    bool usePersistedCookies = true,
    Map<String, String>? extraHeaders,
  }) async {
    final res = await _requestDetailed(
      url: url,
      params: params,
      weapi: weapi,
      plain: plain,
      usePersistedCookies: usePersistedCookies,
      extraHeaders: extraHeaders,
    );
    return res.body;
  }

  /// 同 [_request]，但额外回传响应头（扫码登录需要 `x-refresh-token`）。
  Future<({String body, String refreshToken})> _requestDetailed({
    required String url,
    required Map<String, dynamic> params,
    required bool weapi,
    bool plain = false,
    bool usePersistedCookies = true,
    Map<String, String>? extraHeaders,
  }) async {
    if (weapi && usePersistedCookies) {
      await ensureWeapiSession();
    }
    final uri = Uri.parse(url);
    var reqUri = uri;
    final Map<String, String> body;
    if (weapi) {
      body = NeteaseCrypto.weApiEncrypt(params);
      reqUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'csrf_token': usePersistedCookies ? csrf : '',
        },
      );
    } else if (plain) {
      body = {for (final e in params.entries) e.key: '${e.value}'};
    } else {
      body = NeteaseCrypto.eApiEncrypt(uri.path, params);
    }

    // 显式 UTF-8 表单体，避免 Dio 对 Map 的编码差异。
    final form = body.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await _dio.post<String>(
      reqUri.toString(),
      data: form,
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=utf-8',
        responseType: ResponseType.plain,
        headers: {
          'Origin': NeteaseEndpoints.mainHost,
          ...?extraHeaders,
        },
      ),
    );
    return (
      body: res.data ?? '',
      refreshToken: res.headers.value('x-refresh-token') ?? '',
    );
  }

  // ── B3：301 预热重试 ─────────────────────────────────────

  static final RegExp _bodyCodeRe = RegExp(r'"code"\s*:\s*(-?\d+)');

  /// 从响应体里取业务 `code`（无则 null）。
  static int? bodyCode(String raw) {
    final m = _bodyCodeRe.firstMatch(raw);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// 播放 URL / 歌词遇 body `code==301`（会话失效或需登录）时，
  /// 强制预热一次再重试一遍；其余失败（404 / fee / 无 url）不重试。
  ///
  /// 对齐 Neri：301 → `ensureWeapiSession` → 重试。
  Future<String> _retryOnceOnLoginRequired(
    Future<String> Function() call,
  ) async {
    var raw = await call();
    if (bodyCode(raw) != 301) return raw;
    await ensureWeapiSession(force: true);
    raw = await call();
    return raw;
  }

  // ── A1 搜索 ──────────────────────────────────────────────

  /// A1c 分类搜索：`type` **1 单曲 / 10 专辑 / 100 歌手 / 1000 歌单**（实测）。
  ///
  /// 走旧口 `search/get`（`cloudsearch/get/web` 实测 50000005）。
  Future<String> searchRaw({
    required String keyword,
    int limit = 10,
    int offset = 0,
    int type = 1,
  }) {
    return callWeApi(NeteaseEndpoints.search, {
      's': keyword,
      'type': type.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  /// 探针用：逐个试搜索路径/参数，定位 50000005。
  Future<String> searchSongsDebug(String keyword) async {
    Future<String> tryCall(String label, Future<String> Function() call) async {
      try {
        final raw = await call();
        final code = RegExp(r'"code"\s*:\s*(-?\d+)').firstMatch(raw)?.group(1);
        // ignore: avoid_print
        print('[A1-try $label] code=$code len=${raw.length} '
            '${raw.substring(0, raw.length.clamp(0, 140))}');
        if (code == '200') return raw;
      } catch (err) {
        // ignore: avoid_print
        print('[A1-try $label] ERR $err');
      }
      return '';
    }

    final body = {
      's': keyword,
      'type': '1',
      'limit': '5',
      'offset': '0',
      'total': 'true',
    };

    final raw = await tryCall(
      'weapi/cloudsearch',
      () => callWeApi('/weapi/cloudsearch/get/web', body),
    );
    if (raw.isNotEmpty) return raw;

    final raw2 = await tryCall(
      'weapi/search/get',
      () => callWeApi('/weapi/search/get', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
      }),
    );
    if (raw2.isNotEmpty) return raw2;

    final raw3 = await tryCall(
      'eapi/cloudsearch/pc',
      () => callEApi('/eapi/cloudsearch/pc', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
        'total': 'true',
      }),
    );
    if (raw3.isNotEmpty) return raw3;

    final raw4 = await tryCall(
      'eapi/search/get',
      () => callEApi('/eapi/search/get', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
      }),
    );
    if (raw4.isNotEmpty) return raw4;

    // interface3 host + cloudsearch
    final raw5 = await tryCall('iface3-cloudsearch', () async {
      final uri = Uri.parse(
        'https://interface3.music.163.com/weapi/cloudsearch/get/web',
      ).replace(queryParameters: {'csrf_token': csrf});
      final enc = NeteaseCrypto.weApiEncrypt(body);
      final form = enc.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final res = await _dio.post<String>(
        uri.toString(),
        data: form,
        options: Options(
          contentType: 'application/x-www-form-urlencoded; charset=utf-8',
          responseType: ResponseType.plain,
        ),
      );
      return res.data ?? '';
    });
    if (raw5.isNotEmpty) return raw5;

    throw const UpstreamChanged('all search variants failed');
  }

  // ── A2 播放 URL ──────────────────────────────────────────

  Future<String> songPlayUrlRaw(
    int songId, {
    String level = 'exhigh',
  }) {
    return _retryOnceOnLoginRequired(
      () => callEApi(NeteaseEndpoints.songPlayUrlV1, {
        'ids': '[$songId]',
        'level': level,
        'encodeType': 'flac',
      }),
    );
  }

  Future<String> songPlayUrlWeapiRaw(int songId, {int br = 320000}) {
    return _retryOnceOnLoginRequired(
      () => callWeApi(NeteaseEndpoints.songPlayUrlWeapi, {
        'ids': '[$songId]',
        'br': br.toString(),
      }),
    );
  }

  // ── A3 歌词 ──────────────────────────────────────────────

  Future<String> songLyricRaw(int songId) {
    return _retryOnceOnLoginRequired(
      () => callEApi(NeteaseEndpoints.songLyricV1, {
        'id': songId.toString(),
        'cp': 'false',
        'lv': 0,
        'tv': 1,
        'rv': 0,
        'yv': 1,
        'ytv': 1,
        'yrv': 0,
      }),
    );
  }

  Future<String> songLyricPlainRaw(int songId) async {
    final res = await _dio.get<String>(
      NeteaseEndpoints.plainUrl(NeteaseEndpoints.songLyricPlain),
      queryParameters: {
        'id': songId,
        'lv': -1,
        'tv': -1,
        'rv': -1,
        'yv': -1,
        'ytv': -1,
        'yrv': -1,
      },
    );
    return res.data ?? '';
  }

  // ── 登录 / 账号（对齐 Neri） ────────────────────────────────

  /// `POST /weapi/w/nuser/account/get`（游客 code 可能非 200）。
  Future<String> accountRaw() => callWeApi(NeteaseEndpoints.account, const {});

  // ── 扫码登录（E2/E3，对齐 Neri `NeteaseQrLoginClient`） ─────

  /// Neri 扫码链路专用桌面 UA（与常规探测 UA 不同）。
  static const _qrUa = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 '
      'Edg/149.0.0.0';

  /// 扫码链路附加头（Neri `executeWeApiPost` 固定带的 web 端标记）。
  static const Map<String, String> _qrHeaders = {
    'User-Agent': _qrUa,
    'x-os': 'web',
    'x-channelsource': 'undefined',
    'nm-gcore-status': '1',
  };

  static final RegExp _unikeyRe = RegExp(r'"unikey"\s*:\s*"([^"]*)"');
  static final RegExp _msgRe = RegExp(r'"(?:message|msg)"\s*:\s*"([^"]*)"');

  /// 从响应体取 `message`/`msg`（无则空串）。
  static String messageOf(String raw) =>
      _msgRe.firstMatch(raw)?.group(1) ?? '';

  /// chainId 格式：`v1_{sDeviceId|unknown-N}_web_login_{ms}`（Neri L404-408）。
  static String buildLoginChainId({String sDeviceId = ''}) {
    final deviceId =
        sDeviceId.isEmpty ? 'unknown-${_rnd.nextInt(1000000)}' : sDeviceId;
    return 'v1_${deviceId}_web_login_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 二维码内容不是裸 unikey，而是 scanlogin URL（Neri L410-426）。
  static String buildScanLoginUrl(String key, String chainId) {
    return Uri.parse('${NeteaseEndpoints.mainHost}/st/platform/scanlogin')
        .replace(
      queryParameters: {
        'codekey': key,
        'chainId': chainId,
        'hdw_device': 'web',
        'hdw_appid': 'web',
        'hitExp': '1',
      },
    ).toString();
  }

  /// 合并 cookies + refresh token（`MUSIC_U` 缺失时用 refresh token 顶替）。
  static Map<String, String> mergeQrCredentialCookies(
    Map<String, String> cookies,
    String refreshToken,
  ) {
    final merged = <String, String>{
      for (final e in cookies.entries)
        if (e.key.isNotEmpty && e.value.isNotEmpty) e.key: e.value,
    };
    if ((merged['MUSIC_U'] ?? '').isEmpty && refreshToken.isNotEmpty) {
      merged['MUSIC_U'] = refreshToken;
    }
    return merged;
  }

  /// E2：创建扫码会话，拿到 unikey + chainId + 二维码内容。
  ///
  /// 不发 csrf / 不预热（对齐 Neri：QR 走独立客户端，不做 weapi 预热）。
  Future<NeteaseQrSession> createQrSession() async {
    final raw = await _request(
      url: '${NeteaseEndpoints.mainHost}${NeteaseEndpoints.qrUnikey}',
      params: {'type': 1, 'noCheckToken': true},
      weapi: true,
      usePersistedCookies: false,
      extraHeaders: _qrHeaders,
    );
    final code = bodyCode(raw);
    final key = _unikeyRe.firstMatch(raw)?.group(1)?.trim() ?? '';
    if (code != 200 || key.isEmpty) {
      throw UpstreamChanged(
        '扫码会话创建失败 code=$code ${messageOf(raw)}'.trim(),
      );
    }
    final chainId = buildLoginChainId();
    return NeteaseQrSession(
      key: key,
      chainId: chainId,
      qrContent: buildScanLoginUrl(key, chainId),
    );
  }

  /// E3：轮询扫码状态。
  ///
  /// `ydDeviceToken` 缺省发空串——Neri 用 runCatching 包住指纹获取、失败即回退
  /// 空 snapshot，说明它并非必需（本方法首要验证的就是这一点）。
  /// 800 生成/过期 · 801 待扫 · 802 待确认 · 803 成功。
  Future<NeteaseQrCheckResult> pollQrLogin(
    NeteaseQrSession session, {
    String ydDeviceToken = '',
  }) async {
    final res = await _requestDetailed(
      url: '${NeteaseEndpoints.mainHost}${NeteaseEndpoints.qrCheck}',
      params: {
        'type': 1,
        'noCheckToken': true,
        'key': session.key,
        'ydDeviceToken': ydDeviceToken,
      },
      weapi: true,
      usePersistedCookies: false,
      extraHeaders: {
        ..._qrHeaders,
        'x-loginmethod': 'QrCode',
        'x-login-chain-id': session.chainId,
      },
    );
    return NeteaseQrCheckResult(
      code: bodyCode(res.body) ?? -1,
      message: messageOf(res.body),
      refreshToken: res.refreshToken,
    );
  }

  /// 803 后的登录态确认（Neri `verifyConfirmedLogin` L307-339）：
  /// 先直接验账号；失败则把 `x-refresh-token` 当 `MUSIC_U` 合并后再验一次；
  /// 仍失败则保留该凭据（尽力而为）。
  Future<bool> confirmQrLogin({required String refreshToken}) async {
    if (await _verifyAccount()) return true;
    final credential = mergeQrCredentialCookies(cookies, refreshToken);
    if ((credential['MUSIC_U'] ?? '').isEmpty) return false;
    seedCookies(credential);
    if (await _verifyAccount()) return true;
    return hasLogin;
  }

  /// 把外部 cookies（持久化恢复 / refresh token 兜底）灌回内存会话。
  void seedCookies(Map<String, String> cookies) {
    for (final e in cookies.entries) {
      if (e.key.isEmpty || e.value.isEmpty) continue;
      _cookies[e.key] = e.value;
    }
  }

  /// 退出登录：清掉登录凭据（本地登出，不调远端 logout 口）。
  void clearLogin() {
    _cookies.remove('MUSIC_U');
    _cookies.remove('__csrf');
    _preheated = false;
  }

  Future<bool> _verifyAccount() async {
    try {
      final raw = await callWeApi(NeteaseEndpoints.account, {
        'noCheckToken': true,
        if (csrf.isNotEmpty) 'csrf_token': csrf,
      });
      final root = jsonDecode(raw);
      if (root is! Map) return false;
      if (root['code'] != 200) return false;
      return root['account'] != null || root['profile'] != null;
    } catch (_) {
      return false;
    }
  }

  /// 手机号 + 密码（密码 MD5）。
  Future<String> loginByPhoneRaw(
    String phone,
    String password, {
    int countryCode = 86,
  }) {
    return callEApi(
      NeteaseEndpoints.loginCellphone,
      {
        'phone': phone,
        'countrycode': countryCode,
        'remember': 'true',
        'password': NeteaseCrypto.md5Hex(password),
        'type': '1',
      },
      usePersistedCookies: false,
    );
  }

  /// 短信验证码登录。
  Future<String> loginByCaptchaRaw(
    String phone,
    String captcha, {
    int ctcode = 86,
  }) {
    return callEApi(
      NeteaseEndpoints.loginCellphone,
      {
        'phone': phone,
        'countrycode': ctcode,
        'remember': 'true',
        'type': '1',
        'captcha': captcha,
      },
      usePersistedCookies: false,
    );
  }

  /// 发送短信验证码（interface host weapi）。
  Future<String> sendSmsCaptchaRaw(String phone, {int ctcode = 86}) {
    return callWeApi(
      NeteaseEndpoints.smsSend,
      {'cellphone': phone, 'ctcode': ctcode.toString()},
      host: NeteaseEndpoints.interfaceHost,
      usePersistedCookies: false,
    );
  }

  /// 校验短信验证码。
  Future<String> verifySmsCaptchaRaw(
    String phone,
    String captcha, {
    int ctcode = 86,
  }) {
    return callWeApi(
      NeteaseEndpoints.smsVerify,
      {
        'cellphone': phone,
        'captcha': captcha,
        'ctcode': ctcode.toString(),
      },
      host: NeteaseEndpoints.interfaceHost,
      usePersistedCookies: false,
    );
  }

  // ── 我喜欢 / 用户歌单 ─────────────────────────────────────

  Future<String> userPlaylistsRaw(int userId, {int offset = 0, int limit = 30}) {
    return callWeApi(NeteaseEndpoints.userPlaylist, {
      'uid': userId.toString(),
      'offset': offset.toString(),
      'limit': limit.toString(),
      'includeVideo': 'true',
    });
  }

  Future<String> likedSongIdsRaw(int userId) {
    return callWeApi(NeteaseEndpoints.songLikeGet, {
      'uid': userId.toString(),
    });
  }

  Future<String> likeSongRaw(int songId, {bool like = true, int? time}) {
    return callWeApi(NeteaseEndpoints.songLike, {
      'trackId': songId.toString(),
      'like': like.toString(),
      if (time != null) 'time': time.toString(),
    });
  }

  /// 加曲到歌单（对齐 Neri `buildNeteasePlaylistAddTracksParams`）。
  Future<String> addSongsToPlaylistRaw(int playlistId, List<int> songIds) {
    final ids = songIds.where((id) => id > 0).toSet().toList();
    return callWeApi(NeteaseEndpoints.playlistManipulateTracks, {
      'op': 'add',
      'pid': playlistId.toString(),
      'id': playlistId.toString(),
      'tracks': ids.join(','),
      'trackIds': '[${ids.join(',')}]',
      'imme': 'true',
    });
  }

  /// 从歌单删曲（同 F5 端点，`op=del`；**探针未实测**，见 接口文档 §五 F5）。
  Future<String> removeSongsFromPlaylistRaw(int playlistId, List<int> songIds) {
    final ids = songIds.where((id) => id > 0).toSet().toList();
    return callWeApi(NeteaseEndpoints.playlistManipulateTracks, {
      'op': 'del',
      'pid': playlistId.toString(),
      'id': playlistId.toString(),
      'tracks': ids.join(','),
      'trackIds': '[${ids.join(',')}]',
      'imme': 'true',
    });
  }

  /// 收藏专辑（interface3 eapi）。
  Future<String> userAlbumsRaw(int userId, {int offset = 0, int limit = 30}) {
    return callEApi(
      NeteaseEndpoints.userAlbums,
      {
        'userId': userId.toString(),
        'offset': offset.toString(),
        'limit': limit.toString(),
        'pageType': '3',
        'needRcmd': '0',
        'isVistor': 'false',
        'includeStarPodcast': 'true',
      },
      host: NeteaseEndpoints.interface3Host,
    );
  }

  // ── 详情：歌单 / 专辑 / 歌人（对齐 Neri） ────────────────────

  /// `POST /api/v6/playlist/detail`（明文 CryptoMode.API）。
  Future<String> playlistDetailRaw(int playlistId, {int n = 100000, int s = 8}) {
    return callPlainApi(NeteaseEndpoints.playlistDetail, {
      'id': playlistId.toString(),
      'n': n.toString(),
      's': s.toString(),
    });
  }

  /// `POST /weapi/v1/album/{id}`（interface host）。
  Future<String> albumDetailRaw(int albumId, {int n = 100000, int s = 8}) {
    return callWeApi(
      '${NeteaseEndpoints.albumDetail}$albumId',
      {'n': n.toString(), 's': s.toString()},
      host: NeteaseEndpoints.interfaceHost,
    );
  }

  Future<String> artistDetailRaw(int artistId) {
    return callPlainApi(NeteaseEndpoints.artistHeadInfo, {
      'id': artistId.toString(),
    });
  }

  Future<String> artistDynamicRaw(int artistId) {
    return callPlainApi(NeteaseEndpoints.artistDynamic, {
      'id': artistId.toString(),
    });
  }

  Future<String> artistSongsRaw(
    int artistId, {
    String order = 'hot',
    int offset = 0,
    int limit = 50,
  }) {
    return callPlainApi(NeteaseEndpoints.artistSongs, {
      'id': artistId.toString(),
      'private_cloud': 'true',
      'work_type': '1',
      'order': order,
      'offset': offset.toString(),
      'limit': limit.toString(),
    });
  }

  Future<String> artistAlbumsRaw(int artistId, {int offset = 0, int limit = 30}) {
    return callPlainApi('${NeteaseEndpoints.artistAlbums}$artistId', {
      'limit': limit.toString(),
      'offset': offset.toString(),
      'total': 'true',
    });
  }

  // ── G. 推荐 / 发现（对齐 Neri） ─────────────────────────────

  /// 个性推荐歌单 `POST /weapi/personalized/playlist`。
  Future<String> personalizedPlaylistsRaw({int limit = 30}) {
    return callWeApi(NeteaseEndpoints.personalizedPlaylist, {
      'limit': limit.toString(),
    });
  }

  /// 每日推荐歌单 `POST /weapi/v1/discovery/recommend/resource`（需登录）。
  Future<String> dailyRecommendResourceRaw() {
    return callWeApi(NeteaseEndpoints.dailyRecommendResource, const {});
  }

  /// 每日推荐歌曲 `POST /weapi/v3/discovery/recommend/songs`（需登录）。
  Future<String> dailyRecommendSongsRaw({bool afresh = false}) {
    return callWeApi(NeteaseEndpoints.dailyRecommendSongs, {
      'afresh': afresh.toString(),
    });
  }

  /// 私人 FM `POST /weapi/v1/radio/get`（需登录）。
  Future<String> personalFmRaw() {
    return callWeApi(NeteaseEndpoints.personalFm, const {});
  }

  /// 新歌推荐 `POST /weapi/personalized/newsong`。
  Future<String> personalizedNewSongsRaw({int limit = 30}) {
    return callWeApi(NeteaseEndpoints.personalizedNewSong, {
      'type': 'recommend',
      'limit': limit.toString(),
      'areaId': '0',
    });
  }

  /// 热门/分类歌单 `POST /weapi/playlist/list`。
  Future<String> topPlaylistsRaw({
    String cat = '全部',
    String order = 'hot',
    int limit = 30,
    int offset = 0,
  }) {
    return callWeApi(NeteaseEndpoints.topPlaylists, {
      'cat': cat,
      'order': order,
      'limit': limit.toString(),
      'offset': offset.toString(),
      'total': 'true',
    });
  }

  /// 精品歌单 `POST /weapi/playlist/highquality/list`。
  Future<String> highQualityPlaylistsRaw({
    String cat = '全部',
    int limit = 50,
    int before = 0,
  }) {
    return callWeApi(NeteaseEndpoints.highQualityList, {
      'cat': cat,
      'limit': limit.toString(),
      'lasttime': before.toString(),
      'total': 'true',
    });
  }

  /// 精品标签：weapi 加密，URL 为 `/api/playlist/highquality/tags`（Neri 形态）。
  Future<String> highQualityTagsRaw() {
    return callWeApiAt(
      '${NeteaseEndpoints.mainHost}${NeteaseEndpoints.highQualityTags}',
    );
  }

  /// 雷达/官方歌单元数据 `POST /api/playlist/detail`（plain，Neri radar）。
  Future<String> radarPlaylistMetaRaw(int playlistId) {
    return callPlainApi(NeteaseEndpoints.radarPlaylistMeta, {
      'id': playlistId.toString(),
      'n': '1',
      's': '0',
      'uiPlaylistType': 'MGC',
    });
  }

  // ── A4 详情 ──────────────────────────────────────────────

  Future<String> songDetailRaw(List<int> ids) {
    final idsCsv = ids.join(',');
    final c = [for (final id in ids) '{"id":$id}'].join(',');
    return callWeApi(NeteaseEndpoints.songDetail, {
      'c': '[$c]',
      'ids': '[$idsCsv]',
    });
  }
}

/// 默认网易云客户端（全局共享 Cookie 会话）。
///
/// `NeteaseSource` / 登录页 / 探针都走这一份，登录态才不会两处打架。
final neteaseClient = NeteaseClient();

// ── 扫码登录 DTO ───────────────────────────────────────────

/// 扫码会话：`key` 是 unikey，`qrContent` 是二维码真正要编码的内容。
class NeteaseQrSession {
  const NeteaseQrSession({
    required this.key,
    required this.chainId,
    required this.qrContent,
  });

  final String key;
  final String chainId;
  final String qrContent;
}

/// 扫码轮询结果（800 过期 / 801 待扫 / 802 待确认 / 803 成功）。
class NeteaseQrCheckResult {
  const NeteaseQrCheckResult({
    required this.code,
    this.message = '',
    this.refreshToken = '',
  });

  final int code;
  final String message;
  final String refreshToken;

  bool get isConfirmed => code == 803;
}

// ── 轻量解析 DTO（探针/一期用） ────────────────────────────

class ProbeSong {
  const ProbeSong({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationMs,
    this.picUrl = '',
  });

  final int id;
  final String name;
  final String artists;
  final String album;
  final int durationMs;
  final String picUrl;

  @override
  String toString() =>
      'ProbeSong($id, $name, $artists, $album, ${durationMs}ms)';
}

class ProbePlayUrl {
  const ProbePlayUrl({
    required this.url,
    this.type = '',
    this.level = '',
    this.size = 0,
    this.isPreviewClip = false,
    this.fee = 0,
    this.dataCode = 200,
  });

  final String url;
  final String type;
  final String level;
  final int size;
  final bool isPreviewClip;
  final int fee;
  final int dataCode;
}

class ProbeLyric {
  const ProbeLyric({
    this.lrc = '',
    this.yrc = '',
    this.tlyric = '',
    this.romalrc = '',
  });

  final String lrc;
  final String yrc;
  final String tlyric;
  final String romalrc;

  bool get isEmpty => lrc.isEmpty && yrc.isEmpty;
}

List<ProbeSong> parseProbeSongs(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int?;
  if (code != null && code != 200) {
    throw mapNeteaseCode(code, message: 'search failed code=$code');
  }
  final result = root['result'] as Map<String, dynamic>?;
  final songs = result?['songs'] as List? ?? const [];
  return [
    for (final item in songs)
      if (item is Map)
        (() {
          final m = Map<String, dynamic>.from(item);
          final artists = m['ar'] ?? m['artists'] ?? const [];
          final album = m['al'] ?? m['album'] ?? const {};
          var albumName = album is Map ? '${album['name'] ?? ''}' : '';
          var pic = album is Map ? '${album['picUrl'] ?? ''}' : '';
          // 旧 search/get：album.artist / album.picUrl 等。
          if (album is Map) {
            albumName = albumName.isEmpty ? '${album['name'] ?? ''}' : albumName;
            pic = pic.isEmpty ? '${album['picUrl'] ?? album['blurPicUrl'] ?? ''}' : pic;
          }
          final artistList = <String>[];
          if (artists is List) {
            for (final a in artists) {
              if (a is Map) artistList.add('${a['name'] ?? ''}');
            }
          }
          if (artistList.isEmpty && album is Map && album['artist'] is Map) {
            artistList.add('${(album['artist'] as Map)['name'] ?? ''}');
          }
          if (artistList.isEmpty && m['artist'] is Map) {
            artistList.add('${(m['artist'] as Map)['name'] ?? ''}');
          }
          return ProbeSong(
            id: (m['id'] as num?)?.toInt() ?? 0,
            name: '${m['name'] ?? ''}',
            artists: artistList.join('/'),
            album: albumName,
            durationMs: ((m['dt'] ?? m['duration'] ?? 0) as num).toInt(),
            picUrl: pic,
          );
        })(),
  ];
}

ProbePlayUrl parseProbePlayUrl(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int? ?? -1;
  if (code == 301) {
    throw const LoginRequired('code=301');
  }
  if (code != 200) {
    throw mapNeteaseCode(code, message: 'play url code=$code');
  }
  final data = root['data'];
  final item = data is List && data.isNotEmpty
      ? data.first
      : (data is Map ? data : null);
  if (item is! Map) {
    throw const NotFound('play url data empty');
  }
  final m = Map<String, dynamic>.from(item);
  final url = '${m['url'] ?? ''}';
  final fee = (m['fee'] as num?)?.toInt() ?? 0;
  final dataCode = (m['code'] as num?)?.toInt() ?? 200;
  final freeTrial = m['freeTrialInfo'];
  final hasTrial = freeTrial != null && freeTrial != false;
  if (url.isEmpty || url == 'null') {
    final cannot = (m['freeTrialPrivilege'] is Map)
        ? ((m['freeTrialPrivilege'] as Map)['cannotListenReason'] as num?)
            ?.toInt()
        : null;
    throw mapNeteasePlayFailure(
      dataCode: dataCode,
      fee: fee,
      cannotListenReason: cannot,
    );
  }
  return ProbePlayUrl(
    url: url,
    type: '${m['type'] ?? ''}',
    level: '${m['level'] ?? ''}',
    size: (m['size'] as num?)?.toInt() ?? 0,
    isPreviewClip: hasTrial,
    fee: fee,
    dataCode: dataCode,
  );
}

ProbeLyric parseProbeLyric(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int?;
  if (code != null && code != 200) {
    throw mapNeteaseCode(code, message: 'lyric code=$code');
  }
  String pick(String key) {
    final node = root[key];
    if (node is Map) return '${node['lyric'] ?? ''}';
    return '';
  }

  return ProbeLyric(
    lrc: pick('lrc'),
    yrc: pick('yrc'),
    tlyric: pick('tlyric'),
    romalrc: pick('romalrc'),
  );
}

/// 解析 weapi/v3/song/detail 的第一首歌名。
String? parseProbeDetailTitle(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final songs = root['songs'] as List?;
  if (songs == null || songs.isEmpty) return null;
  final s = songs.first;
  return s is Map ? '${s['name']}' : null;
}

/// 账号 / 我喜欢 / 详情的轻量摘要（探针打印用）。
Map<String, Object?> parseProbeAccount(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final profile = root['profile'] as Map<String, dynamic>?;
  final account = root['account'] as Map<String, dynamic>?;
  return {
    'code': root['code'],
    'userId': profile?['userId'] ?? account?['id'],
    'nickname': profile?['nickname'],
  };
}

Map<String, Object?> parseProbeUserPlaylists(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final list = root['playlist'] as List? ?? const [];
  String? likedId;
  for (final item in list) {
    if (item is! Map) continue;
    final special = (item['specialType'] as num?)?.toInt() ?? 0;
    final name = '${item['name'] ?? ''}';
    if (special == 5 || name.contains('我喜欢')) {
      likedId = '${item['id']}';
      break;
    }
  }
  return {
    'code': root['code'],
    'count': list.length,
    'likedPlaylistId': likedId,
    'first': list.isEmpty ? null : '${(list.first as Map)['name']}',
  };
}

Map<String, Object?> parseProbePlaylistDetail(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final playlist = root['playlist'] as Map<String, dynamic>?;
  final tracks = playlist?['tracks'] as List? ?? const [];
  return {
    'code': root['code'],
    'name': playlist?['name'],
    'trackCount': playlist?['trackCount'] ?? tracks.length,
    'loaded': tracks.length,
  };
}

Map<String, Object?> parseProbeAlbumDetail(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final album = root['album'] as Map<String, dynamic>?;
  final songs = root['songs'] as List? ?? const [];
  final artist = album?['artist'];
  return {
    'code': root['code'],
    'name': album?['name'],
    'artist': artist is Map ? artist['name'] : null,
    'songs': songs.length,
  };
}

Map<String, Object?> parseProbeArtistDetail(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final data = root['data'] as Map<String, dynamic>?;
  final artist = (data?['artist'] ?? data) as Map<String, dynamic>?;
  return {
    'code': root['code'] ?? root['status'],
    'name': artist?['name'],
    'musicSize': artist?['musicSize'] ?? artist?['songNum'],
    'albumSize': artist?['albumSize'] ?? artist?['albumNum'],
  };
}

/// G 组推荐/发现摘要。
Map<String, Object?> parseProbeRecommend(String raw, {String label = ''}) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'];
  Object? count;
  Object? first;
  // personalized/playlist → result[]
  // highquality → playlists[]
  // playlist/list → playlists[]
  // recommend/songs → data.dailySongs[] / recommend[]
  // recommend/resource → recommend[]
  // newsong → result[]
  // radio/get → data[]
  final result = root['result'];
  final data = root['data'];
  List? list;
  if (result is List) {
    list = result;
  } else if (result is Map) {
    list = (result['songs'] ?? result['tracks'] ?? result['dailySongs']) as List?;
  }
  list ??= (root['playlists'] as List?) ??
      (root['recommend'] as List?) ??
      (data is List ? data : null) ??
      (data is Map ? (data['dailySongs'] as List?) : null);
  count = list?.length;
  if (list != null && list.isNotEmpty) {
    final e0 = list.first;
    if (e0 is Map) {
      first = e0['name'] ?? e0['songName'] ?? e0['title'] ?? e0['id'];
    }
  }
  return {'code': code, 'label': label, 'count': count, 'first': first};
}
