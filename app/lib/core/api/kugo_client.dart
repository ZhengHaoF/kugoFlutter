import 'dart:convert';

import 'package:dio/dio.dart';

import '../../features/auth/auth_token_holder.dart';
import 'network_log.dart';

class KugoApiException implements Exception {
  KugoApiException(this.message, {this.code, this.cause, this.filtered = false});

  final String message;
  final int? code;
  final Object? cause;

  /// True when a middlebox returned an HTML deny page with HTTP 200.
  final bool filtered;

  @override
  String toString() => 'KugoApiException($code): $message';
}

bool looksLikeUrlFilter(dynamic body) {
  if (body == null) return false;
  final s = body is String ? body : body.toString();
  return s.contains('URL过滤') ||
      s.contains('access control policy') ||
      s.contains('disable.htm') ||
      s.contains('plc_name') ||
      s.contains('Access Deny');
}

/// Kugou often serves JSON with `Content-Type: text/html`.
/// Dio keeps those bodies as [String]; decode when possible.
dynamic decodeKugoBody(dynamic data) {
  if (data is! String) return data;
  final trimmed = data.trim();
  if (trimmed.isEmpty) return data;
  if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return data;
  try {
    return jsonDecode(trimmed);
  } on FormatException {
    return data;
  }
}

typedef NetworkLogSink = void Function(NetworkLog log);

/// Thin Dio wrapper with mobile-friendly headers, timeout, and log hooks.
class KugoClient {
  KugoClient({Dio? dio, NetworkLogSink? onLog}) : _dio = dio ?? _createDio() {
    _onLog = onLog;
    if (dio == null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['User-Agent'] = _ua;
            options.headers['Referer'] ??= 'http://www.kugou.com/';
            // Inject kugou-style auth if logged in; guests skip.
            final auth = AuthTokenHolder.instance;
            if (auth.hasToken) {
              options.headers['Authorization'] = auth.authorizationHeader;
            }
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
          onError: (err, handler) {
            if (err.response?.statusCode == 401) {
              AuthTokenHolder.instance.clear();
            }
            final start = err.requestOptions.extra['__start'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
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
                errorMessage: err.toString().split('\n').first,
                duration: Duration(
                  milliseconds: DateTime.now().millisecondsSinceEpoch - start,
                ),
              ),
            );
            handler.next(err);
          },
        ),
      );
    }
  }

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final Dio _dio;
  NetworkLogSink? _onLog;

  void setLogSink(NetworkLogSink? sink) => _onLog = sink;

  void _emit(NetworkLog log) => _onLog?.call(log);

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        validateStatus: (code) => code != null && code >= 200 && code < 400,
      ),
    );
  }

  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(url, queryParameters: query);
      if (looksLikeUrlFilter(res.data)) {
        final denied = res.data is String &&
            (res.data as String).contains('Access Deny');
        throw KugoApiException(
          denied ? '接口拒绝访问（Access Deny）' : '网络网关拦截（URL过滤），无法访问酷狗接口',
          code: res.statusCode,
          filtered: !denied,
        );
      }
      return decodeKugoBody(res.data);
    } on DioException catch (e) {
      throw KugoApiException(
        e.message ?? 'network error',
        code: e.response?.statusCode,
        cause: e,
      );
    } on KugoApiException {
      rethrow;
    }
  }

  Future<String> getText(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<String>(
        url,
        queryParameters: query,
        options: Options(responseType: ResponseType.plain),
      );
      if (looksLikeUrlFilter(res.data)) {
        throw KugoApiException(
          '网络网关拦截（URL过滤），无法访问酷狗接口',
          code: res.statusCode,
          filtered: true,
        );
      }
      return res.data ?? '';
    } on DioException catch (e) {
      throw KugoApiException(
        e.message ?? 'network error',
        code: e.response?.statusCode,
        cause: e,
      );
    } on KugoApiException {
      rethrow;
    }
  }
}

final kugoClient = KugoClient();

String buildUrl(String base, String path, [Map<String, dynamic>? query]) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = path.startsWith('/') ? path : '/$path';
  final uri = Uri.parse('$b$p').replace(
    queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
  );
  return uri.toString();
}
