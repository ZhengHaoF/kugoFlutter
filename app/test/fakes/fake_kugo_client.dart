import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kugo/core/api/kugou/kugo_client.dart';

/// 脚本化 [KugoClient]：按 URL 关键字回放响应体，并记录调用。
///
/// 与 `_FakeNeteaseClient extends NeteaseClient` 同一套路——仓库的 HTTP 层
/// 用注入的 client 换掉，测试只覆盖「URL 拼装 + 响应映射 + 兜底顺序」。
/// 注意 `super(dio: Dio())`：传了 dio 就不会挂 NetworkLog 拦截器。
class FakeKugoClient extends KugoClient {
  FakeKugoClient({this.onJson, this.onText}) : super(dio: Dio());

  /// 返回 `null` 表示抛错（模拟网络失败 / 网关拦截）。
  final dynamic Function(String url)? onJson;
  final dynamic Function(String url)? onText;

  final List<String> jsonCalls = [];
  final List<String> textCalls = [];

  @override
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query}) async {
    jsonCalls.add(url);
    final body = onJson?.call(url);
    if (body == null) {
      throw KugoApiException('scripted failure', code: 500);
    }
    // 允许脚本直接给解码后的对象；给 String 时走一遍真实解码路径。
    return body is String ? decodeKugoBody(body) : body;
  }

  @override
  Future<String> getText(String url, {Map<String, dynamic>? query}) async {
    textCalls.add(url);
    final body = onText?.call(url);
    if (body == null) {
      throw KugoApiException('scripted failure', code: 500);
    }
    return body is String ? body : jsonEncode(body);
  }
}

/// 一次性 [HttpClientAdapter]：按 FIFO 回放响应，并把请求记下来。
///
/// 给 `DeviceRepository` / `LoginRepository` 这类自己持 Dio 的仓库用。
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._responses);

  final List<dynamic> _responses;
  int _i = 0;

  final List<RequestOptions> requests = [];

  dynamic get lastRequest => requests.isEmpty ? null : requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final scripted = _i < _responses.length ? _responses[_i] : null;
    _i++;
    if (scripted == null) {
      return ResponseBody.fromBytes(const [], 500);
    }
    if (scripted is DioException) throw scripted;
    final (int status, String body, String contentType) = scripted;
    // content-type 必须给对：dio 的 transformer 靠它决定要不要 JSON 解码。
    // responseType=bytes 的仓库（DeviceRepository / CoverCache）自己解字节，
    // 此时若标成 application/json，dio 仍会尝试 jsonDecode 非 JSON 体。
    return ResponseBody.fromBytes(
      utf8.encode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  /// 「JSON 200」脚本项。
  static (int, String, String) json(Object value) => (
        200,
        value is String ? value : jsonEncode(value),
        Headers.jsonContentType,
      );

  /// 「纯文本 200」脚本项。
  static (int, String, String) text(String value) =>
      (200, value, 'text/plain');

  /// 任意状态码 + 纯文本（测错误分支用）。
  static (int, String, String) raw(int status, String body) =>
      (status, body, 'text/plain');
}
