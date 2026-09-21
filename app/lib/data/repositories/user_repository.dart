import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_crypto.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../storage/device_identity.dart';

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
        return UserPlaylistsResult(error: msg.isNotEmpty ? msg : '获取用户歌单失败');
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
        final source = int.tryParse('${m['source'] ?? 1}') ?? 1;
        if (source == 2) {
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
          final listId = '${m['listid'] ?? m['specialid'] ?? m['id'] ?? ''}';
          final name = '${m['name'] ?? m['specialname'] ?? ''}';
          final cover = normalizeCoverUrl('${m['pic'] ?? m['imgurl'] ?? m['cover'] ?? ''}');
          final creator = '${m['nickname'] ?? m['list_create_username'] ?? ''}';
          final trackCount = int.tryParse('${m['count'] ?? m['songcount'] ?? m['song_count'] ?? 0}') ?? 0;
          final isDef = m['is_def'] == 1 || m['is_default'] == 1 || m['is_def'] == 2;
          final createUserId = '${m['list_create_userid'] ?? ''}';
          final brief = PlaylistBrief(
            id: listId,
            name: name,
            coverUrl: cover,
            creator: creator,
            trackCount: trackCount,
            source: source,
            userId: createUserId,
            isDefault: isDef,
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
        return UserFollowResult(error: msg.isNotEmpty ? msg : '获取关注列表失败');
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
        return UserPlaylistTracksResult(
          error: msg.isNotEmpty ? msg : '获取用户歌单歌曲失败',
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
}

final userRepository = UserRepository();
