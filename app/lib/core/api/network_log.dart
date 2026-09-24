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
    required this.id,
    required this.type,
    required this.timestamp,
    required this.method,
    required this.url,
    this.headers,
    this.data,
    this.statusCode,
    this.errorMessage,
    this.duration,
  });

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
    return buf.toString().trimRight();
  }
}

const int maxLogDataChars = 2048;

Map<String, dynamic> sanitizeHeaders(Map<String, dynamic>? headers) {
  if (headers == null) return const {};
  final result = Map<String, dynamic>.from(headers);
  result.forEach((key, value) {
    if (key.toLowerCase() == 'authorization' ||
        key.toLowerCase() == 'cookie') {
      result[key] = '***';
    }
  });
  return result;
}

dynamic truncateLogData(dynamic data) {
  if (data == null) return null;
  final str = data.toString();
  if (str.length <= maxLogDataChars) return data;
  return '${str.substring(0, maxLogDataChars)}\n…(已截断，原长度 ${str.length} 字符)';
}
