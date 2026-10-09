import 'dart:convert';

import 'package:dio/dio.dart';

import '../../source/capabilities.dart';
import '../../source/music_source.dart';
import 'bili_endpoints.dart';

/// B 站扫码登录客户端（G1 生成 / G2 轮询，账号阶段探针用）。
///
/// 对齐 NeriPlayer `core/api/bili/BiliQrLoginClient.kt`：
/// - 生成：`GET passport/x/passport-login/web/qrcode/generate`（无参数）
///   → `data.qrcode_key` + `data.url`（二维码内容）；
/// - 轮询：`GET .../qrcode/poll?qrcode_key=…`，root `code=0` 表示请求本身
///   成功，**扫码状态在 `data.code`**：86101 等待 / 86090 已扫待确认 /
///   86038 过期 / 0 成功（Set-Cookie 带 SESSDATA 等）；
/// - Referer 用扫码专用登录页（不是 www 站）。
///
/// B 站扫码是**纯 HTTP**（不像网易依赖隐藏 WebView 跑 `yd_token`），
/// Windows 桌面壳可直接用（方案 §5.3 #7）。
class BiliQrLoginClient {
  BiliQrLoginClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json, text/plain, */*',
                  'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
                  'Cache-Control': 'no-cache',
                  'Pragma': 'no-cache',
                  'Referer': BiliEndpoints.loginPageUrl,
                  'User-Agent': BiliEndpoints.webUA,
                },
                responseType: ResponseType.plain,
                validateStatus: (c) => c != null && c >= 200 && c < 500,
              ),
            ) {
    // 扫码成功时 SESSDATA 等在**轮询响应**的 Set-Cookie 里，必须吸收。
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_cookies.isNotEmpty) {
            options.headers['Cookie'] = _cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
          }
          handler.next(options);
        },
        onResponse: (res, handler) {
          _absorbSetCookie(res);
          handler.next(res);
        },
      ),
    );
  }

  final Dio _dio;
  final Map<String, String> _cookies = {};

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// 是否已登录（只看 SESSDATA，方案 §3.3）。
  bool get hasLogin => (_cookies['SESSDATA'] ?? '').isNotEmpty;

  void reset() => _cookies.clear();

  /// G1 生成扫码会话。
  Future<BiliQrLoginSession> createSession() async {
    final res = await _dio.get<dynamic>(
      '${BiliEndpoints.passportHost}${BiliEndpoints.qrcodeGenerate}',
    );
    final body = _decode(res, 'G1 qrcode/generate');
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const UpstreamChanged('G1: 响应缺少 data');
    }
    final key = data['qrcode_key'];
    final url = data['url'];
    if (key is! String || key.isEmpty || url is! String || url.isEmpty) {
      throw const UpstreamChanged('G1: 响应缺少 qrcode_key/url');
    }
    return BiliQrLoginSession(key: key, qrContent: url);
  }

  /// G2 轮询扫码状态。root `code != 0` 说明请求本身失败（抛异常）；
  /// 否则看 [BiliQrLoginPoll.code]（= `data.code`）。
  Future<BiliQrLoginPoll> pollLogin(BiliQrLoginSession session) async {
    final res = await _dio.get<dynamic>(
      '${BiliEndpoints.passportHost}${BiliEndpoints.qrcodePoll}',
      queryParameters: {'qrcode_key': session.key},
    );
    final body = _decode(res, 'G2 qrcode/poll');
    final data = body['data'];
    final code = data is Map<String, dynamic> ? data['code'] : null;
    final message = data is Map<String, dynamic> ? data['message'] : null;
    return BiliQrLoginPoll(
      code: code is int ? code : -1,
      message: message is String ? message : '',
      // 成功时 Set-Cookie 已被拦截器收进 [_cookies]。
      cookies: Map.unmodifiable(_cookies),
    );
  }

  /// B3 落盘恢复用：灌入 Cookie。
  void seedCookies(Map<String, String> cookies) => _cookies.addAll(cookies);

  /// 轮询码 → 契约层 [LoginQrStatus]（纯函数，单测覆盖）。
  static LoginQrStatus statusFromCode(int code) => switch (code) {
        0 => LoginQrStatus.confirmed,
        86090 => LoginQrStatus.scanned,
        86101 => LoginQrStatus.waiting,
        86038 => LoginQrStatus.expired,
        _ => LoginQrStatus.unknown,
      };

  Map<String, dynamic> _decode(Response<dynamic> res, String what) {
    final body =
        res.data is String ? jsonDecode(res.data as String) : res.data;
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw NetworkFailure('$what：HTTP ${res.statusCode}');
    }
    if (body is! Map<String, dynamic>) {
      throw UpstreamChanged('$what：响应不是 JSON 对象');
    }
    final code = body['code'];
    if (code is! int || code != 0) {
      throw UpstreamChanged(
        '$what：code=${code ?? "缺失"} message=${body['message']}',
      );
    }
    return body;
  }

  void _absorbSetCookie(Response<dynamic> res) {
    final setCookies = res.headers.map['set-cookie'];
    if (setCookies == null) return;
    for (final sc in setCookies) {
      final first = sc.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      _cookies[first.substring(0, eq)] = first.substring(eq + 1);
    }
  }
}

/// 扫码会话。
class BiliQrLoginSession {
  const BiliQrLoginSession({required this.key, required this.qrContent});

  final String key;

  /// 二维码内容（`data.url`，形如 `https://passport.bilibili.com/x/…`）。
  final String qrContent;
}

/// 一次轮询结果。[code] 是 `data.code`（0=成功）。
class BiliQrLoginPoll {
  const BiliQrLoginPoll({
    required this.code,
    required this.message,
    required this.cookies,
  });

  final int code;
  final String message;

  /// 轮询期间吸收的 Cookie（成功时含 SESSDATA / bili_jct / DedeUserID）。
  final Map<String, String> cookies;

  bool get isConfirmed => code == 0;

  LoginQrStatus get status => BiliQrLoginClient.statusFromCode(code);

  @override
  String toString() => 'code=$code($status) message=$message '
      'cookieKeys=${cookies.keys.join(',')}';
}
