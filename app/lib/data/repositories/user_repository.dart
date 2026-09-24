import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_crypto.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

/// Maps Kugou gateway error_code to a user-facing message.
String describeKugoErrorCode(int? code, {String fallback = '请求失败'}) {
  switch (code) {
    case 20006:
      return '签名校验失败（20006）';
    case 20010:
      return '请求参数缺失（20010）';
    case 20017:
      return '云端歌单鉴权失败（20017），请退出后重新登录';
    case 20018:
      return '登录态无效（20018），请退出后重新登录';
    case 20028:
      return '触发安全校验（SSA 20028），请重新登录后再试';
    default:
      return code == null ? fallback : '$fallback（$code）';
  }
}

class UserPlaylistsResult {
  const UserPlaylistsResult({
    this.created = const [],
    this.collected = const [],
    this.albums = const [],
    this.error = '',
  });

  final List<PlaylistBrief> created;
  final List<PlaylistBrief> collected;
  final List<AlbumBrief> albums;
  final String error;

  int get totalPlaylists => created.length + collected.length;
}

class UserFollowResult {
  const UserFollowResult({
    this.singers = const [],
    this.error = '',
  });

  final List<ArtistBrief> singers;
  final String error;
}

class UserPlaylistTracksResult {
  const UserPlaylistTracksResult({
    this.tracks = const [],
    this.total = 0,
    this.error = '',
  });

  final List<Track> tracks;
  final int total;
  final String error;
}

class UserRepository {
  UserRepository({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  /// Fetches user playlists from Kugou gateway (`/v7/get_all_list`).
  ///
  /// Splits into:
  /// - [created]: user owned playlists (source != 2 && owner)
  /// - [collected]: favorited playlists (source != 2 && !owner)
  /// - [albums]: favorited albums (source == 2)
  Future<UserPlaylistsResult> fetchUserPlaylists({
    required String userId,
    required String token,
    int page = 1,
    int pageSize = 50,
  }) async {
    if (userId.isEmpty || token.isEmpty) {
      return const UserPlaylistsResult(error: '未登录');
    }

    try {
      final device = await DeviceIdentity.ensure();
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final query = <String, dynamic>{
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
        'plat': 1,
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
      };
      final dataMap = <String, dynamic>{
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
        'total_ver': 979,
        'type': 2,
        'page': page,
        'pagesize': pageSize,
      };
      final bodyJson = jsonEncode(dataMap);
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

      final cookieParts = <String>[
        'token=$token',
        'userid=$userId',
        if (AuthTokenHolder.instance.t1.isNotEmpty)
          't1=${AuthTokenHolder.instance.t1}',
        'dfid=${device.dfid}',
        'KUGOU_API_MID=${device.mid}',
        'KUGOU_API_GUID=${device.guid}',
        'KUGOU_API_DEV=${device.dev}',
      ];

      final headers = <String, dynamic>{
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': device.dfid,
        'mid': device.mid,
        'clienttime': '$clienttime',
        'x-router': 'cloudlist.service.kugou.com',
        'Cookie': cookieParts.join(';'),
      };

      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}/v7/get_all_list',
        queryParameters: query,
        data: bodyJson,
        options: Options(headers: headers),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        return const UserPlaylistsResult(error: '网络网关拦截（URL过滤），无法访问酷狗');
      }

      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        return const UserPlaylistsResult(error: '解析用户歌单响应失败');
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg = (map['msg'] ?? map['error'] ?? map['message'] ?? '').toString();
        final code = int.tryParse(
          '${map['error_code'] ?? map['err_code'] ?? map['errcode'] ?? ''}',
        );
        return UserPlaylistsResult(
          error: msg.isNotEmpty
              ? msg
              : describeKugoErrorCode(code, fallback: '获取用户歌单失败'),
        );
      }

      final dataNode = map['data'];
      final infoNode = dataNode is Map
          ? (dataNode['info'] ?? dataNode['lists'] ?? dataNode['list'])
          : (map['info'] ?? map['list']);
      final rawList = infoNode is List ? infoNode : (dataNode is List ? dataNode : const []);

      final created = <PlaylistBrief>[];
      final collected = <PlaylistBrief>[];
      final albums = <AlbumBrief>[];

      for (final item in rawList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final listKind = int.tryParse('${m['source'] ?? 1}') ?? 1;
        if (listKind == 2) {
          // Album
          final albumId = '${m['list_create_listid'] ?? m['listid'] ?? m['id'] ?? ''}';
          final name = '${m['name'] ?? m['specialname'] ?? ''}';
          final cover = normalizeCoverUrl('${m['pic'] ?? m['imgurl'] ?? m['cover'] ?? ''}');
          final artist = '${m['nickname'] ?? m['list_create_username'] ?? ''}';
          final trackCount = int.tryParse('${m['count'] ?? m['songcount'] ?? 0}') ?? 0;
          albums.add(
            AlbumBrief(
              id: albumId,
              name: name,
              coverUrl: cover,
              artist: artist,
              trackCount: trackCount,
            ),
          );
        } else {
          // Playlist
          // Prefer /user/playlist listid for track APIs; never use public specialid.
          final rawListId = '${m['listid'] ?? ''}';
          final listId = rawListId.isNotEmpty && rawListId != '0'
              ? rawListId
              : '${m['list_create_listid'] ?? m['id'] ?? ''}';
          final name = '${m['name'] ?? m['specialname'] ?? ''}';
          final cover = normalizeCoverUrl('${m['pic'] ?? m['imgurl'] ?? m['cover'] ?? ''}');
          final creator = '${m['nickname'] ?? m['list_create_username'] ?? ''}';
          final trackCount = int.tryParse('${m['count'] ?? m['songcount'] ?? m['song_count'] ?? 0}') ?? 0;
          final isDef = m['is_def'] == 1 || m['is_default'] == 1 || m['is_def'] == 2;
          final typeVal = int.tryParse('${m['type'] ?? 0}') ?? 0;
          final createUserId = '${m['list_create_userid'] ?? ''}';
          final brief = PlaylistBrief(
            id: listId,
            name: name,
            coverUrl: cover,
            creator: creator,
            trackCount: trackCount,
            listKind: listKind,
            userId: createUserId,
            isDefault: isDef,
            type: typeVal,
            listId: rawListId.isNotEmpty && rawListId != '0' ? rawListId : listId,
          );
          if (createUserId == userId || (createUserId.isEmpty && isDef)) {
            created.add(brief);
          } else {
            collected.add(brief);
          }
        }
      }

      return UserPlaylistsResult(
        created: created,
        collected: collected,
        albums: albums,
      );
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return UserPlaylistsResult(
        error: msg.contains('URL过滤') ? '网络网关拦截（URL过滤），无法访问酷狗' : '网络请求失败',
      );
    } catch (e) {
      return UserPlaylistsResult(error: e.toString());
    }
  }

  /// Fetches followed singers from Kugou gateway (`/v4/follow_list`).
  Future<UserFollowResult> fetchUserFollow({
    required String userId,
    required String token,
    int page = 1,
    int pageSize = 50,
  }) async {
    if (userId.isEmpty || token.isEmpty) {
      return const UserFollowResult(error: '未登录');
    }

    try {
      final device = await DeviceIdentity.ensure();
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final p = KugoCrypto.rsaEncryptRaw(
        jsonEncode({'clienttime': clienttime, 'token': token}),
      ).toUpperCase();

      final query = <String, dynamic>{
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
        'plat': 1,
      };
      final dataMap = <String, dynamic>{
        'merge': 2,
        'need_iden_type': 1,
        'ext_params': 'k_pic,jumptype,singerid,score',
        'userid': int.tryParse(userId) ?? userId,
        'type': 0,
        'id_type': 0,
        'p': p,
      };
      final bodyJson = jsonEncode(dataMap);
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

      final cookieParts = <String>[
        'token=$token',
        'userid=$userId',
        if (AuthTokenHolder.instance.t1.isNotEmpty)
          't1=${AuthTokenHolder.instance.t1}',
        'dfid=${device.dfid}',
        'KUGOU_API_MID=${device.mid}',
        'KUGOU_API_GUID=${device.guid}',
        'KUGOU_API_DEV=${device.dev}',
      ];

      final headers = <String, dynamic>{
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': device.dfid,
        'mid': device.mid,
        'clienttime': '$clienttime',
        'x-router': 'relationuser.kugou.com',
        'Cookie': cookieParts.join(';'),
      };

      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}/v4/follow_list',
        queryParameters: query,
        data: bodyJson,
        options: Options(headers: headers),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        return const UserFollowResult(error: '网络网关拦截（URL过滤），无法访问酷狗');
      }

      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        return const UserFollowResult(error: '解析关注列表响应失败');
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg = (map['msg'] ?? map['error'] ?? map['message'] ?? '').toString();
        final code = int.tryParse(
          '${map['error_code'] ?? map['err_code'] ?? map['errcode'] ?? ''}',
        );
        return UserFollowResult(
          error: msg.isNotEmpty
              ? msg
              : describeKugoErrorCode(code, fallback: '获取关注列表失败'),
        );
      }

      final dataNode = map['data'];
      final listsNode = dataNode is Map ? (dataNode['lists'] ?? dataNode['list']) : map['lists'];
      final rawList = listsNode is List ? listsNode : const [];

      final singers = <ArtistBrief>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final singerId = '${m['singerid'] ?? m['id'] ?? m['userid'] ?? ''}';
        final name = '${m['nickname'] ?? m['singername'] ?? m['name'] ?? ''}';
        final pic = normalizeCoverUrl('${m['pic'] ?? m['k_pic'] ?? m['imgurl'] ?? ''}');
        final sourceDesc = '${m['source_desc'] ?? ''}';
        final fansCount = int.tryParse('${m['fans_count'] ?? m['fanscount'] ?? 0}') ?? 0;
        final songCount = int.tryParse('${m['songcount'] ?? m['song_count'] ?? 0}') ?? 0;
        singers.add(
          ArtistBrief(
            id: singerId,
            name: name,
            avatarUrl: pic,
            sourceDesc: sourceDesc,
            fansCount: fansCount,
            songCount: songCount,
          ),
        );
      }

      return UserFollowResult(singers: singers);
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return UserFollowResult(
        error: msg.contains('URL过滤') ? '网络网关拦截（URL过滤），无法访问酷狗' : '网络请求失败',
      );
    } catch (e) {
      return UserFollowResult(error: e.toString());
    }
  }

  /// Fetches songs in a user playlist (自建 / 收藏 / 默认我喜欢) from Kugou gateway (`/v4/get_list_all_file_v3`).
  ///
  /// - [type]: 0 for user created playlists (including default "我喜欢"), 1 for collected playlists.
  Future<UserPlaylistTracksResult> fetchUserPlaylistTracks({
    required String listId,
    required String userId,
    required String token,
    int type = 0,
    int page = 1,
    int pageSize = 300,
  }) async {
    if (userId.isEmpty || token.isEmpty) {
      return const UserPlaylistTracksResult(error: '未登录');
    }

    try {
      final device = await DeviceIdentity.ensure();
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final query = <String, dynamic>{
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
        'plat': 1,
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
      };
      final dataMap = <String, dynamic>{
        'listid': int.tryParse(listId) ?? listId,
        'userid': int.tryParse(userId) ?? userId,
        'type': type,
        'page': page,
        'pagesize': pageSize,
        'area_code': 1,
        'allplatform': 1,
        'show_cover': 1,
        'token': token,
      };
      final bodyJson = jsonEncode(dataMap);
      query['signature'] =
          KugoSign.signatureAndroidParams(query, data: bodyJson);

      final cookieParts = <String>[
        'token=$token',
        'userid=$userId',
        if (AuthTokenHolder.instance.t1.isNotEmpty)
          't1=${AuthTokenHolder.instance.t1}',
        'dfid=${device.dfid}',
        'KUGOU_API_MID=${device.mid}',
        'KUGOU_API_GUID=${device.guid}',
        'KUGOU_API_DEV=${device.dev}',
      ];

      final headers = <String, dynamic>{
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': device.dfid,
        'mid': device.mid,
        'clienttime': '$clienttime',
        'x-router': 'cloudlist.service.kugou.com',
        'Cookie': cookieParts.join(';'),
      };

      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}/v4/get_list_all_file_v3',
        queryParameters: query,
        data: bodyJson,
        options: Options(headers: headers),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        return const UserPlaylistTracksResult(error: '网络网关拦截（URL过滤），无法访问酷狗');
      }

      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        return const UserPlaylistTracksResult(error: '解析用户歌单歌曲响应失败');
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg =
            (map['msg'] ?? map['error'] ?? map['message'] ?? '').toString();
        final code = int.tryParse(
          '${map['error_code'] ?? map['err_code'] ?? map['errcode'] ?? ''}',
        );
        return UserPlaylistTracksResult(
          error: msg.isNotEmpty
              ? msg
              : describeKugoErrorCode(code, fallback: '获取用户歌单歌曲失败'),
        );
      }

      final dataNode = map['data'];
      final infoNode = dataNode is Map
          ? (dataNode['info'] ??
              dataNode['lists'] ??
              dataNode['list'] ??
              dataNode['songs'])
          : (map['info'] ?? map['list'] ?? map['songs']);
      final rawList = infoNode is List
          ? infoNode
          : (dataNode is List ? dataNode : const []);

      final total = dataNode is Map
          ? (int.tryParse('${dataNode['total'] ?? dataNode['count'] ?? 0}') ??
              rawList.length)
          : rawList.length;

      final tracks = <Track>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final t = mapMobileSearchSong(Map<String, dynamic>.from(item));
        if (t.hash.isNotEmpty || t.name.isNotEmpty) {
          tracks.add(t);
        }
      }

      return UserPlaylistTracksResult(
        tracks: tracks,
        total: total,
      );
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return UserPlaylistTracksResult(
        error: msg.contains('URL过滤') ? '网络网关拦截（URL过滤），无法访问酷狗' : '网络请求失败',
      );
    } catch (e) {
      return UserPlaylistTracksResult(error: e.toString());
    }
  }

  /// Adds a song to a cloud playlist (including default 「我喜欢」).
  ///
  /// Ported from KuGouMusicApi `playlist_tracks_add.js` → `/cloudlist.service/v6/add_song`.
  Future<({bool ok, String error})> addPlaylistTrack({
    required String listId,
    required String userId,
    required String token,
    required String name,
    required String hash,
    required String albumId,
    required String mixSongId,
  }) async {
    if (userId.isEmpty || token.isEmpty) {
      return (ok: false, error: '未登录');
    }
    try {
      final device = await DeviceIdentity.ensure();
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final query = <String, dynamic>{
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
        'plat': 1,
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
      };
      final dataMap = <String, dynamic>{
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
        'listid': int.tryParse(listId) ?? listId,
        'list_ver': 0,
        'type': 0,
        'slow_upload': 1,
        'scene': 'false;null',
        'data': [
          {
            'number': 1,
            'name': name,
            'hash': hash,
            'size': 0,
            'sort': 0,
            'timelen': 0,
            'bitrate': 0,
            'album_id': int.tryParse(albumId) ?? 0,
            'mixsongid': int.tryParse(mixSongId) ?? 0,
          },
        ],
      };
      final bodyJson = jsonEncode(dataMap);
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
      query['last_time'] = clienttime;
      query['last_area'] = 'gztx';

      final headers = _authHeaders(device: device, token: token, userId: userId, clienttime: clienttime);
      headers['x-router'] = 'cloudlist.service.kugou.com';

      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}/v6/add_song',
        queryParameters: query,
        data: bodyJson,
        options: Options(headers: headers),
      );
      return _parseCloudOp(res, '添加到我喜欢失败');
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return (
        ok: false,
        error: msg.contains('URL过滤')
            ? '网络网关拦截（URL过滤），无法访问酷狗'
            : '网络请求失败',
      );
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Removes songs from a cloud playlist by fileid (mixsongid).
  ///
  /// Ported from KuGouMusicApi `playlist_tracks_del.js` → `/v4/delete_songs`.
  Future<({bool ok, String error})> deletePlaylistTracks({
    required String listId,
    required String userId,
    required String token,
    required List<String> fileIds,
  }) async {
    if (userId.isEmpty || token.isEmpty) {
      return (ok: false, error: '未登录');
    }
    if (fileIds.isEmpty) {
      return (ok: true, error: '');
    }
    try {
      final device = await DeviceIdentity.ensure();
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final query = <String, dynamic>{
        ...KugoSign.defaultParams(dfid: device.dfid, mid: device.mid),
        'plat': 1,
        'userid': int.tryParse(userId) ?? userId,
        'token': token,
      };
      final dataMap = <String, dynamic>{
        'listid': int.tryParse(listId) ?? listId,
        'userid': int.tryParse(userId) ?? userId,
        'data': [
          for (final id in fileIds) {'fileid': int.tryParse(id) ?? 0},
        ],
        'type': 0,
        'token': token,
        'list_ver': 0,
      };
      final bodyJson = jsonEncode(dataMap);
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

      final headers = _authHeaders(device: device, token: token, userId: userId, clienttime: clienttime);
      headers['x-router'] = 'cloudlist.service.kugou.com';

      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.gateway}/v4/delete_songs',
        queryParameters: query,
        data: bodyJson,
        options: Options(headers: headers),
      );
      return _parseCloudOp(res, '从我喜欢移除失败');
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return (
        ok: false,
        error: msg.contains('URL过滤')
            ? '网络网关拦截（URL过滤），无法访问酷狗'
            : '网络请求失败',
      );
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  Map<String, dynamic> _authHeaders({
    required dynamic device,
    required String token,
    required String userId,
    required int clienttime,
  }) {
    final cookieParts = <String>[
      'token=$token',
      'userid=$userId',
      if (AuthTokenHolder.instance.t1.isNotEmpty)
        't1=${AuthTokenHolder.instance.t1}',
      'dfid=${device.dfid}',
      'KUGOU_API_MID=${device.mid}',
      'KUGOU_API_GUID=${device.guid}',
      'KUGOU_API_DEV=${device.dev}',
    ];
    return <String, dynamic>{
      'User-Agent': KugoSign.userAgent,
      'Content-Type': 'application/json',
      'dfid': device.dfid,
      'mid': device.mid,
      'clienttime': '$clienttime',
      'Cookie': cookieParts.join(';'),
    };
  }

  ({bool ok, String error}) _parseCloudOp(Response<dynamic> res, String fallback) {
    final raw = res.data?.toString() ?? '';
    if (looksLikeUrlFilter(raw)) {
      return (ok: false, error: '网络网关拦截（URL过滤），无法访问酷狗');
    }
    final decoded = decodeKugoBody(res.data);
    if (decoded is! Map) {
      return (ok: false, error: fallback);
    }
    final map = Map<String, dynamic>.from(decoded);
    final status = map['status'];
    final ok = status == 1 || status == '1' || status == true;
    if (ok) return (ok: true, error: '');
    final msg = (map['msg'] ?? map['error'] ?? map['message'] ?? '').toString();
    return (ok: false, error: msg.isNotEmpty ? msg : fallback);
  }
}

final userRepository = UserRepository();
