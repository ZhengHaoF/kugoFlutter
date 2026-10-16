import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/api/kugou/kugou_client.dart';
import 'package:overtone/data/repositories/playlist_repository.dart';

/// 按尝试次数回放的 [KugouClient]：不发 HTTP，只验证重试与抛出策略。
class _ScriptedKugouClient extends KugouClient {
  _ScriptedKugouClient(this._onAttempt) : super(dio: Dio());

  final dynamic Function(int attempt) _onAttempt;
  int calls = 0;

  @override
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query}) async {
    return _onAttempt(calls++);
  }
}

/// Dart HttpClient keep-alive 竞态的典型形态：连接已被服务端关掉。
KugouApiException _transportError() => KugouApiException(
      'Connection closed before full header was received',
      cause: DioException(
        requestOptions: RequestOptions(path: '/api/v3/rank/list'),
        type: DioExceptionType.connectionError,
      ),
    );

Map<String, dynamic> _rankListBody() => {
      'data': {
        'info': [
          {'rankname': 'TOP500', 'rankid': 8888},
          {'rankname': '飙升榜', 'rankid': 6666},
        ],
      },
    };

void main() {
  test('瞬时传输错误：短重试后成功取到榜单', () async {
    final client = _ScriptedKugouClient(
      (attempt) => switch (attempt) {
        0 => throw _transportError(),
        1 => throw _transportError(),
        _ => _rankListBody(),
      },
    );
    final repo = PlaylistRepository(client: client);

    final ranks = await repo.fetchRankList();

    expect(client.calls, 3);
    expect(ranks.map((r) => r.id), ['8888', '6666']);
  });

  test('瞬时传输错误持续：三次后抛出，不再吞成空列表', () async {
    final client = _ScriptedKugouClient((_) => throw _transportError());
    final repo = PlaylistRepository(client: client);

    await expectLater(repo.fetchRankList(), throwsA(isA<KugouApiException>()));
    expect(client.calls, 3);
  });

  test('确定性失败（URL过滤等）不重试，直接抛出', () async {
    final client = _ScriptedKugouClient(
      (_) => throw KugouApiException('网络网关拦截（URL过滤），无法访问酷狗接口'),
    );
    final repo = PlaylistRepository(client: client);

    await expectLater(repo.fetchRankList(), throwsA(isA<KugouApiException>()));
    expect(client.calls, 1);
  });

  test('成功路径只发一次请求', () async {
    final client = _ScriptedKugouClient((_) => _rankListBody());
    final repo = PlaylistRepository(client: client);

    final ranks = await repo.fetchRankList();

    expect(client.calls, 1);
    expect(ranks.length, 2);
  });
}
