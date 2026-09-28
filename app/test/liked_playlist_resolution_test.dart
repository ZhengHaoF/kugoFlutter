import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/data/repositories/user_repository.dart';
import 'package:kugo/features/profile/source_library_controller.dart';

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

PlaylistBrief _brief(
  String id,
  String name, {
  bool isDefault = false,
  int type = 0,
  int trackCount = 0,
}) =>
    PlaylistBrief(
      id: id,
      name: name,
      coverUrl: '',
      isDefault: isDefault,
      type: type,
      trackCount: trackCount,
    );

void main() {
  setUp(() {
    // 设备身份已注册，避免 fetchUserPlaylists 走真实 /risk 注册请求。
    SharedPreferences.setMockInitialValues({
      'kugo_device_dfid_registered': true,
      'kugo_device_dfid': 'test_dfid',
      'kugo_device_guid': 'test_guid',
      'kugo_device_dev': 'kugoFlutter',
    });
  });

  group('findLikedPlaylist', () {
    // 真机 `/v7/get_all_list` 实测顺序：默认收藏(is_def=1, 空) 在前，
    // 我喜欢(is_def=2, 973 首) 在后。两者 mapper 都会打 isDefault。
    final kugouRealOrder = [
      _brief('1', '默认收藏', isDefault: true),
      _brief('2', '我喜欢', isDefault: true, trackCount: 973),
      _brief('3', 'MZHENGHF喜欢的音乐', trackCount: 985),
    ];

    test('酷狗：默认收藏排在前面时仍选「我喜欢」', () {
      final liked = findLikedPlaylist(kugouRealOrder);
      expect(liked?.id, '2');
      expect(liked?.name, '我喜欢');
      expect(liked?.trackCount, 973);
    });

    test('UserPlaylistsPage.likedPlaylist 与之一致', () {
      final page = UserPlaylistsPage(
        created: kugouRealOrder.take(2).toList(),
        collected: [kugouRealOrder.last],
      );
      expect(page.likedPlaylist?.id, '2');
    });

    test('SourceLibraryState.likedPlaylist 与之一致', () {
      final s = SourceLibraryState(
        createdPlaylists: kugouRealOrder,
        collectedPlaylists: const [],
      );
      expect(s.likedPlaylist?.id, '2');
      expect(s.likedPlaylist?.name, '我喜欢');
    });

    test('精确「我喜欢的音乐」优先（网易口径）', () {
      final liked = findLikedPlaylist([
        _brief('9', '默认收藏', isDefault: true),
        _brief('5', '我喜欢的音乐', isDefault: true, trackCount: 1009),
      ]);
      expect(liked?.id, '5');
    });

    test('用户名前缀的默认单：isDefault 兜底优先于含「喜欢」的普通单', () {
      final liked = findLikedPlaylist([
        _brief('7', '我的喜欢歌单', type: 1),
        _brief('8', 'MZHENGHF喜欢的音乐', isDefault: true, trackCount: 1009),
      ]);
      expect(liked?.id, '8');
    });

    test('只有「默认收藏」时兜底选中它', () {
      final liked = findLikedPlaylist([
        _brief('1', '默认收藏', isDefault: true),
      ]);
      expect(liked?.id, '1');
    });
  });

  group('fetchUserPlaylists + likedPlaylist（真机响应形状）', () {
    test('解析 3 条歌单并定位 listid=2 的「我喜欢」', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeDioAdapter((options) async {
        if (options.path.contains('/v7/get_all_list')) {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 1,
              'data': {
                'info': [
                  {
                    'listid': 1,
                    'list_create_listid': 1,
                    'name': '默认收藏',
                    'source': 1,
                    'type': 0,
                    'is_def': 1,
                    'count': 0,
                    'list_create_userid': '2511133520',
                  },
                  {
                    'listid': 2,
                    'list_create_listid': 2,
                    'name': '我喜欢',
                    'source': 1,
                    'type': 0,
                    'is_def': 2,
                    'count': 973,
                    'list_create_userid': '2511133520',
                  },
                  {
                    'listid': 3,
                    'list_create_listid': 3,
                    'name': 'MZHENGHF喜欢的音乐',
                    'source': 1,
                    'type': 0,
                    'count': 985,
                    'list_create_userid': '2511133520',
                  },
                ],
              },
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
        return ResponseBody.fromString(
          jsonEncode({'status': 1, 'data': {'lists': []}}),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      });

      final page = await UserRepository(dio: dio).fetchUserPlaylists(
        userId: '2511133520',
        token: 'test_token',
      );

      expect(page.error, isEmpty);
      expect(page.created.map((p) => p.name), ['默认收藏', '我喜欢', 'MZHENGHF喜欢的音乐']);
      expect(page.created[0].isDefault, isTrue);
      expect(page.created[1].isDefault, isTrue);

      final liked = UserPlaylistsPage(
        created: page.created,
        collected: page.collected,
      ).likedPlaylist;
      expect(liked, isNotNull);
      expect(liked!.name, '我喜欢');
      // track API 优先用 /user/playlist 的 listid。
      expect(liked.listId.isNotEmpty ? liked.listId : liked.id, '2');
      expect(liked.trackCount, 973);
    });
  });
}