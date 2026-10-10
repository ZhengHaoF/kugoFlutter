import 'dart:convert';

import 'package:dio/dio.dart';

/// Fail closed for account credentials. Public HTTP media remains available.
/// Redirects of credential-bearing requests are never followed automatically.
void installKugouCredentialGuard(Dio dio, {bool requireHttps = false}) {
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final uri = options.uri;
        final credentials =
            uri.userInfo.isNotEmpty ||
            _hasCredentials(options.headers) ||
            _hasCredentials(options.queryParameters) ||
            _hasCredentials(uri.queryParameters) ||
            _hasCredentials(options.data);
        if ((credentials || requireHttps) &&
            (uri.scheme != 'https' || !isKugouCredentialHost(uri.host))) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: '安全策略阻止向不安全或非酷狗目标发送账号信息',
            ),
          );
          return;
        }
        if (credentials || requireHttps) {
          options.followRedirects = false;
          options.maxRedirects = 0;
        }
        handler.next(options);
      },
    ),
  );
}

bool isKugouCredentialHost(String host) {
  final h = host.toLowerCase();
  return h == 'kugou.com' || h.endsWith('.kugou.com');
}

/// Upgrade a provider-selected upload origin, never downgrade TLS. The
/// credential guard still verifies the host before any bytes reach the wire.
String secureKugouUploadBase(String host) {
  final uri = Uri.tryParse(host.contains('://') ? host : 'https://$host');
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      !isKugouCredentialHost(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw StateError('云盘返回了不安全的上传目标，已停止上传');
  }
  return uri.replace(scheme: 'https', path: '').toString();
}

bool _credentialKey(String key) {
  final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return k.contains('token') ||
      k.contains('password') ||
      const {
        'authorization',
        'proxyauthorization',
        'cookie',
        'setcookie',
        't1',
        'sessdata',
        'musicu',
        'passwd',
        'pwd',
      }.contains(k);
}

bool _hasCredentials(dynamic data) {
  if (data is Map) {
    return data.entries.any(
      (e) =>
          (_credentialKey('${e.key}') &&
              e.value != null &&
              '${e.value}'.isNotEmpty) ||
          _hasCredentials(e.value),
    );
  }
  if (data is Iterable) return data.any(_hasCredentials);
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map || decoded is List) return _hasCredentials(decoded);
    } catch (_) {
      // Not JSON: scan form/header-style key-value data below.
    }
    try {
      if (data.contains('=') && _hasCredentials(Uri.splitQueryString(data))) {
        return true;
      }
    } catch (_) {
      return true; // malformed credential-like form data fails closed
    }
  }
  return false;
}
