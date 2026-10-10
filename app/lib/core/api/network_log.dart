import 'dart:convert';

typedef NetworkLogSink = void Function(NetworkLog log);

/// 全局网络日志汇聚点。各 Repository 只 `NetworkLogHub.emit`，
/// 由 main 单点挂到 UI（networkLogProvider），避免 N 套 logSink。
abstract final class NetworkLogHub {
  static NetworkLogSink? sink;

  static void emit(NetworkLog log) => sink?.call(log);

  static void bind(NetworkLogSink? s) => sink = s;
}

enum NetworkLogType { request, response, error }

class NetworkLog {
  NetworkLog({
    required String id,
    required this.type,
    required this.timestamp,
    required this.method,
    required String url,
    Map<String, dynamic>? headers,
    dynamic data,
    this.statusCode,
    String? errorMessage,
    this.duration,
  }) : id = sanitizeLogText(id),
       url = sanitizeLogUrl(url),
       headers = headers == null
           ? null
           : Map.unmodifiable(sanitizeHeaders(headers)),
       data = _isAuthenticationUrl(url) && data != null
           ? '[认证接口内容已省略]'
           : truncateLogData(data),
       errorMessage = errorMessage == null
           ? null
           : sanitizeLogText(errorMessage);

  final String id;
  final NetworkLogType type;
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, dynamic>? headers;
  final dynamic data;
  final int? statusCode;
  final String? errorMessage;
  final Duration? duration;

  String get typeLabel {
    switch (type) {
      case NetworkLogType.request:
        return 'REQUEST';
      case NetworkLogType.response:
        return 'RESPONSE';
      case NetworkLogType.error:
        return 'ERROR';
    }
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String toCopyText() {
    final buf = StringBuffer()
      ..writeln('[$typeLabel] $method $url')
      ..writeln('time=$formattedTime');
    if (statusCode != null) buf.writeln('status=$statusCode');
    if (duration != null) buf.writeln('duration=${duration!.inMilliseconds}ms');
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      buf.writeln('error=$errorMessage');
    }
    if (data != null) buf.writeln('body=$data');
    if (headers != null && headers!.isNotEmpty) {
      buf.writeln('headers=$headers');
    }
    return sanitizeLogText(buf.toString().trimRight());
  }
}

const int maxLogDataChars = 2048;

Map<String, dynamic> sanitizeHeaders(Map<String, dynamic>? headers) {
  if (headers == null) return const {};
  return {
    for (final e in headers.entries)
      sanitizeLogText(e.key): isSensitiveLogKey(e.key)
          ? '***'
          : sanitizeLogData(e.value),
  };
}

dynamic truncateLogData(dynamic data) {
  if (data == null) return null;
  final safe = sanitizeLogData(data);
  final str = safe.toString();
  if (str.length <= maxLogDataChars) return safe;
  return '${str.substring(0, maxLogDataChars)}\n…(已截断，原长度 ${str.length} 字符)';
}

/// Normalize separators/case so provider-specific credentials share one policy.
bool isSensitiveLogKey(String key) {
  try {
    key = Uri.decodeComponent(key);
  } catch (_) {
    return true;
  }
  final k = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return k.contains('token') ||
      k.contains('password') ||
      k.contains('secret') ||
      k.contains('signature') ||
      const {
        'authorization',
        'proxyauthorization',
        'cookie',
        'setcookie',
        'passwd',
        'pwd',
        't1',
        'sessdata',
        'musicu',
        'bilijct',
        'csrf',
        'csrftoken',
        'session',
        'sessionid',
        'key',
        'ticket',
        'qrcode',
        'unikey',
        'mobile',
        'phone',
        'sign',
        'sig',
        'upsig',
        'wrid',
      }.contains(k);
}

bool _isAuthenticationUrl(String value) {
  final path = Uri.tryParse(value)?.path.toLowerCase() ?? '';
  return RegExp(
    r'login|passport|oauth|captcha|qrcode|send_mobile_code',
  ).hasMatch(path);
}

String sanitizeLogUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) return _redactAssignments(value);
  try {
    return uri
        .replace(
          userInfo: uri.userInfo.isEmpty ? '' : '***',
          queryParameters: uri.hasQuery
              ? {
                  for (final e in uri.queryParametersAll.entries)
                    e.key: isSensitiveLogKey(e.key)
                        ? const ['***']
                        : e.value.map(_redactAssignments).toList(),
                }
              : null,
          fragment: uri.hasFragment ? _redactAssignments(uri.fragment) : null,
        )
        .toString();
  } catch (_) {
    // Malformed diagnostic URLs should not defeat redaction or logging.
    return '[无法安全解析的 URL 已省略]';
  }
}

dynamic sanitizeLogData(dynamic data, [int depth = 0]) {
  if (data == null || data is num || data is bool) return data;
  if (depth > 10) return '[嵌套内容已省略]';
  if (data is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final e in data.entries.take(100))
        sanitizeLogText('${e.key}'): isSensitiveLogKey('${e.key}')
            ? '***'
            : sanitizeLogData(e.value, depth + 1),
    });
  }
  if (data is Iterable) {
    return List<dynamic>.unmodifiable(
      data.take(100).map((e) => sanitizeLogData(e, depth + 1)),
    );
  }
  final text = data.toString();
  final uri = Uri.tryParse(text);
  if (uri != null && const {'http', 'https'}.contains(uri.scheme)) {
    return sanitizeLogUrl(text);
  }
  if (text.trimLeft().startsWith('{') || text.trimLeft().startsWith('[')) {
    try {
      return sanitizeLogData(jsonDecode(text), depth + 1);
    } catch (_) {
      // Incomplete JSON/error text still goes through assignment redaction.
    }
  }
  if (text.contains('=')) {
    try {
      final form = Uri.splitQueryString(text);
      if (form.keys.any(isSensitiveLogKey)) {
        return sanitizeLogData(form, depth + 1);
      }
    } catch (_) {
      return '[无法安全解析的表单已省略]';
    }
  }
  return sanitizeLogText(text);
}

String sanitizeLogText(String text) {
  final safe = text
      .replaceAll(
        RegExp(
          r'\b(?:authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]+',
          caseSensitive: false,
        ),
        '[凭据头已省略]',
      )
      .replaceAllMapped(
        RegExp(r'https?://[^\s"<>]+'),
        (m) => sanitizeLogUrl(m.group(0)!),
      );
  return _redactAssignments(safe);
}

String _redactAssignments(String text) {
  var safe = text.replaceAllMapped(
    RegExp(
      r'''(["']?)([A-Za-z0-9_%-]+)\1\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^&;\s,}\]]+)''',
    ),
    (m) => isSensitiveLogKey(m.group(2)!)
        ? '${m.group(1)}${m.group(2)}${m.group(1)}=***'
        : m.group(0)!,
  );
  safe = safe.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer ***',
  );
  return safe;
}
