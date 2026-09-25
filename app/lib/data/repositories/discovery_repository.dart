import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart';
import '../../core/api/network_log.dart';
import '../../core/models/catalog_models.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

/// Artist list item with optional avatar / counts (richer than search/singer).
class DiscoveryArtist {
  const DiscoveryArtist({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.songCount = 0,
    this.fansCount = 0,
    this.letter = '',
  });

  final String id;
  final String name;
  final String avatarUrl;
  final int songCount;
  final int fansCount;

  /// Group title from `artist/lists` (`热门` / `A` / `#` …).
  final String letter;
}

class DiscoverySection<T> {
  const DiscoverySection({this.items = const [], this.error = '', this.total = 0});

  final List<T> items;
  final String error;
  final int total;

  bool get isEmpty => items.isEmpty;
}

/// Exploration catalog: playlist tags, new songs, new albums, artist lists.
///
/// Ports KuGouMusicApi `playlist_tags.js` / `top_song.js` / `top_album.js` /
/// `artist_lists.js` using the same android signature as [RecommendRepository].
class DiscoveryRepository {
  DiscoveryRepository({Dio? dio}) : _dio = dio ?? _createDio() {
    if (dio == null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
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
                    ? options.data
                    : truncateLogData({
                        'query': options.queryParameters,
                        'body': options.data,
                      }),
              ),
            );
            handler.next(options);
          },
          onResponse: (response, handler) {
            final id = response.requestOptions.extra['__id'] as String?;
            if (id != null) {
              _emit(
                NetworkLog(
                  id: id,
                  type: NetworkLogType.response,
                  timestamp: DateTime.now(),
                  method: response.requestOptions.method,
                  url: response.requestOptions.uri.toString(),
                  statusCode: response.statusCode,
                  data: truncateLogData(response.data?.toString() ?? ''),
                ),
              );
            }
            handler.next(response);
          },
          onError: (e, handler) {
            final id = e.requestOptions.extra['__id'] as String?;
            if (id != null) {
              _emit(
                NetworkLog(
                  id: id,
                  type: NetworkLogType.response,
                  timestamp: DateTime.now(),
                  method: e.requestOptions.method,
                  url: e.requestOptions.uri.toString(),
                  statusCode: e.response?.statusCode,
                  data: truncateLogData(e.message ?? e.toString()),
                ),
              );
            }
            handler.next(e);
          },
        ),
      );
    }
  }

    static void _emit(NetworkLog log) => NetworkLogHub.emit(log);

  final Dio _dio;
  String lastError = '';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  /// Album region tabs (EchoMusic / MoeKoeMusic `/top/album`).
  static const albumTypes = <({String id, String label})>[
    (id: 'all', label: '全部'),
    (id: 'chn', label: '华语'),
    (id: 'eur', label: '欧美'),
    (id: 'jpn', label: '日本'),
    (id: 'kor', label: '韩国'),
  ];

  /// Artist filters (EchoMusic `/artist/lists` enu_list).
  static const artistSexTypes = <({String id, String label})>[
    (id: '0', label: '全部'),
    (id: '1', label: '男'),
    (id: '2', label: '女'),
    (id: '3', label: '组合'),
  ];

  static const artistTypes = <({String id, String label})>[
    (id: '0:0', label: '全部'),
    (id: '1:0', label: '流行'),
    (id: '2:0', label: '嘻哈'),
    (id: '3:0', label: '摇滚'),
    (id: '4:0', label: '电子'),
    (id: '5:0', label: '民谣'),
    (id: '6:0', label: '爵士'),
    (id: '7:0', label: '古典'),
  ];

  /// KuGouMusicApi `playlist_tags.js` → `POST /pubsongs/v1/get_tags_by_type`.
  Future<DiscoverySection<PlaylistTagGroup>> fetchPlaylistTags() async {
    lastError = '';
    final body = <String, dynamic>{
      'tag_type': 'collection',
      'tag_id': 0,
      'source': 3,
    };
    final decoded = await _signedRequest(
      method: 'POST',
      path: KugoEndpoints.playlistTags,
      body: body,
      label: '歌单分类',
    );
    if (decoded == null) {
      return DiscoverySection(error: _sectionError('歌单分类'));
    }

    final groups = extractPlaylistTagGroups(decoded);
    if (groups.isEmpty) {
      return DiscoverySection(error: lastError.isNotEmpty ? lastError : '暂无歌单分类');
    }
    return DiscoverySection(items: groups);
  }

  /// KuGouMusicApi `top_song.js` → `POST musicadservice /container/v1/newsong_publish`.
  Future<DiscoverySection<Track>> fetchNewSongs({
    int page = 1,
    int pageSize = 30,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    final body = <String, dynamic>{
      'rank_id': 21608,
      'userid': int.tryParse(auth.userId) ?? 0,
      'page': page,
      'pagesize': pageSize,
      'tags': <dynamic>[],
    };
    final decoded = await _signedRequest(
      method: 'POST',
      baseUrl: KugoEndpoints.musicAdService,
      path: KugoEndpoints.newSongPublish,
      body: body,
      label: '新歌速递',
    );
    if (decoded == null) {
      return DiscoverySection(error: _sectionError('新歌速递'));
    }

    final tracks = <Track>[];
    final seen = <String>{};
    for (final item in extractEverydayList(decoded)) {
      if (item is! Map) continue;
      final track = mapEverydaySong(Map<String, dynamic>.from(item));
      final key = track.id.isNotEmpty ? track.id : track.hash;
      if (key.isEmpty || !seen.add(key)) continue;
      tracks.add(track);
    }
    final total = extractListTotal(decoded);
    if (tracks.isEmpty) {
      return DiscoverySection(error: lastError.isNotEmpty ? lastError : '暂无新歌');
    }
    return DiscoverySection(items: tracks, total: total > 0 ? total : tracks.length);
  }

  /// KuGouMusicApi `top_album.js` → `POST musicadservice /v1/mobile_newalbum_sp`.
  Future<DiscoverySection<AlbumBrief>> fetchNewAlbums({
    String type = 'all',
    int page = 1,
    int pageSize = 30,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    final body = <String, dynamic>{
      'apiver': 1,
      'token': auth.token,
      'page': page,
      'pagesize': pageSize,
      'withpriv': 1,
    };
    final decoded = await _signedRequest(
      method: 'POST',
      baseUrl: KugoEndpoints.musicAdService,
      path: KugoEndpoints.mobileNewAlbum,
      body: body,
      label: '新碟上架',
    );
    if (decoded == null) {
      return DiscoverySection(error: _sectionError('新碟上架'));
    }

    final albums = extractAlbumsByType(decoded, type: type);
    if (albums.isEmpty) {
      return DiscoverySection(error: lastError.isNotEmpty ? lastError : '暂无新碟');
    }
    return DiscoverySection(items: albums, total: albums.length);
  }

  /// KuGouMusicApi `artist_lists.js` → `GET /ocean/v6/singer/list`.
  Future<DiscoverySection<DiscoveryArtist>> fetchArtists({
    int sextype = 0,
    int type = 0,
    int musician = 0,
    int hotsize = 30,
  }) async {
    lastError = '';
    final decoded = await _signedRequest(
      method: 'GET',
      path: KugoEndpoints.singerList,
      extraQuery: {
        'musician': musician,
        'sextypes': sextype,
        'showtype': 2,
        'type': type,
        'hotsize': hotsize,
      },
      label: '歌手列表',
    );
    if (decoded == null) {
      return DiscoverySection(error: _sectionError('歌手列表'));
    }

    final artists = extractDiscoveryArtists(decoded);
    if (artists.isEmpty) {
      return DiscoverySection(error: lastError.isNotEmpty ? lastError : '暂无歌手');
    }
    return DiscoverySection(items: artists, total: artists.length);
  }

  String _sectionError(String label) {
    final filtered = lastError.contains('拦截') || lastError.contains('URL过滤');
    return filtered
        ? '当前网络被网关拦截（URL过滤），无法访问酷狗'
        : (lastError.isNotEmpty ? lastError : '$label加载失败');
  }

  Future<Map<String, dynamic>?> _signedRequest({
    required String method,
    required String path,
    String? baseUrl,
    Map<String, dynamic> extraQuery = const {},
    Map<String, dynamic>? body,
    String label = '探索接口',
  }) async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final useToken = auth.hasToken;
    final userId =
        auth.userId.isNotEmpty && auth.userId != '0' ? auth.userId : '';
    final userIdNum = int.tryParse(userId) ?? 0;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bodyJson = body == null ? '' : jsonEncode(body);
    final isGet = method.toUpperCase() == 'GET';

    final params = <String, dynamic>{
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      if (useToken) 'token': auth.token,
      if (userIdNum != 0) 'userid': userIdNum,
      ...extraQuery,
    };
    params['signature'] = KugoSign.signatureAndroidParams(
      params,
      data: isGet ? '' : bodyJson,
    );

    final headers = <String, dynamic>{
      'User-Agent': KugoSign.userAgent,
      if (!isGet) 'Content-Type': 'application/json',
      'dfid': device.dfid,
      'clienttime': '$clienttime',
      'mid': device.mid,
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      'Cookie': [
        if (useToken) 'token=${auth.token}',
        if (userId.isNotEmpty) 'userid=$userId',
        if (auth.t1.isNotEmpty) 't1=${auth.t1}',
        'dfid=${device.dfid}',
        'KUGOU_API_MID=${device.mid}',
        'KUGOU_API_GUID=${device.guid}',
        'KUGOU_API_DEV=${device.dev}',
      ].join(';'),
    };

    final host = baseUrl ?? KugoEndpoints.gateway;
    final url = '$host$path';
    final logId = '${DateTime.now().microsecondsSinceEpoch}-$url';
    _emit(
      NetworkLog(
        id: logId,
        type: NetworkLogType.request,
        timestamp: DateTime.now(),
        method: method,
        url: url,
        headers: sanitizeHeaders(headers),
        data: truncateLogData({'query': params, if (!isGet) 'body': bodyJson}),
      ),
    );

    try {
      final Response<dynamic> res;
      if (isGet) {
        res = await _dio.get<dynamic>(
          url,
          queryParameters: params,
          options: Options(headers: headers),
        );
      } else {
        res = await _dio.post<dynamic>(
          url,
          queryParameters: params,
          data: bodyJson,
          options: Options(headers: headers),
        );
      }

      final raw = res.data?.toString() ?? '';
      _emit(
        NetworkLog(
          id: logId,
          type: NetworkLogType.response,
          timestamp: DateTime.now(),
          method: method,
          url: url,
          statusCode: res.statusCode,
          data: truncateLogData(raw),
        ),
      );

      if (looksLikeUrlFilter(raw)) {
        lastError = '网络网关拦截（URL过滤），无法访问酷狗';
        return null;
      }
      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        lastError = raw.isEmpty ? '$label响应为空' : '$label响应无法解析';
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = map['status'];
      final ok = status == 1 || status == '1' || status == true;
      if (!ok) {
        final msg =
            (map['msg'] ?? map['message'] ?? map['error'] ?? '').toString();
        lastError = msg.isEmpty ? '$label返回失败' : msg;
        return null;
      }
      lastError = '';
      return map;
    } on DioException catch (e) {
      lastError = e.message ?? '$label网络错误';
      return null;
    } catch (e) {
      lastError = '$label异常：$e';
      return null;
    }
  }
}

/// Flatten `playlist/tags` into display groups.
List<PlaylistTagGroup> extractPlaylistTagGroups(dynamic body) {
  final map = body is Map ? Map<String, dynamic>.from(body) : const {};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  final list = data['info'] ?? data['list'] ?? data['data'] ?? map['info'];
  if (list is! List) return const [];

  final groups = <PlaylistTagGroup>[];
  for (final item in list) {
    if (item is! Map) continue;
    final g = Map<String, dynamic>.from(item);
    final groupName = _s(g['tag_name'], _s(g['name'], _s(g['title'])));
    final sons = g['son'] ?? g['child'] ?? g['list'];
    if (sons is! List) continue;
    final child = <PlaylistTag>[];
    for (final son in sons) {
      if (son is! Map) continue;
      final t = Map<String, dynamic>.from(son);
      final id = _s(t['tag_id'], _s(t['id']));
      final name = _s(t['tag_name'], _s(t['name']));
      if (id.isEmpty || name.isEmpty) continue;
      child.add(PlaylistTag(id: id, name: name, group: groupName));
    }
    if (child.isEmpty) continue;
    groups.add(PlaylistTagGroup(name: groupName, child: child));
  }
  return groups;
}

/// `/top/album` items are bucketed by region (`chn`/`eur`/`jpn`/`kor`).
List<AlbumBrief> extractAlbumsByType(dynamic body, {String type = 'all'}) {
  final map = body is Map ? Map<String, dynamic>.from(body) : const {};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  List<dynamic> read(Object? v) => v is List ? v : const [];

  final raw = type == 'all' || type.isEmpty
      ? <dynamic>[
          ...read(data['chn']),
          ...read(data['eur']),
          ...read(data['jpn']),
          ...read(data['kor']),
          ...read(data['list']),
          ...read(data['info']),
          ...read(map['list']),
          ...read(map['info']),
        ]
      : <dynamic>[
          ...read(data[type]),
          ...read(data['list']),
          ...read(data['info']),
        ];

  final albums = <AlbumBrief>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final brief = mapAlbumBrief(Map<String, dynamic>.from(item));
    if (brief.id.isEmpty || !seen.add(brief.id)) continue;
    albums.add(brief);
  }
  return albums;
}

/// `/ocean/v6/singer/list` — flat `info[]` or grouped `info[].singer[]`.
List<DiscoveryArtist> extractDiscoveryArtists(dynamic body) {
  final map = body is Map ? Map<String, dynamic>.from(body) : const {};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  final list = data['info'] ?? data['list'] ?? data['data'] ?? map['info'];
  if (list is! List) return const [];

  final artists = <DiscoveryArtist>[];
  final seen = <String>{};
  for (final item in list) {
    if (item is! Map) continue;
    final g = Map<String, dynamic>.from(item);
    final nested = g['singer'] ?? g['list'] ?? g['info'];
    if (nested is List) {
      final letter = _s(g['title'], _s(g['name'], _s(g['letter'])));
      for (final raw in nested) {
        if (raw is! Map) continue;
        final a = _mapDiscoveryArtist(Map<String, dynamic>.from(raw), letter);
        if (a.id.isEmpty || !seen.add(a.id)) continue;
        artists.add(a);
      }
      continue;
    }
    final a = _mapDiscoveryArtist(g, '');
    if (a.id.isEmpty || !seen.add(a.id)) continue;
    artists.add(a);
  }
  return artists;
}

DiscoveryArtist _mapDiscoveryArtist(Map<String, dynamic> json, String letter) {
  final id = _s(json['singerid'], _s(json['singer_id'], _s(json['id'])));
  final name = _s(
    json['singername'],
    _s(json['singer_name'], _s(json['name'], _s(json['author_name']))),
  );
  final avatarRaw = _s(
    json['sizable_avatar'],
    _s(json['avatar'], _s(json['pic'], _s(json['imgurl'], _s(json['photo'])))),
  );
  return DiscoveryArtist(
    id: id,
    name: name,
    avatarUrl: normalizeCoverUrl(avatarRaw.isEmpty ? (id.isEmpty ? name : id) : avatarRaw),
    songCount: _i2(json['song_count'], json['songcount']),
    fansCount: _i2(json['fans_count'], json['fans']),
    letter: letter,
  );
}

int extractListTotal(dynamic body) {
  final map = body is Map ? Map<String, dynamic>.from(body) : const {};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  return _i2(map['total'], _i2(data['total'], _i2(data['count'], 0)));
}

String _s(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? fallback : t;
}

int _i2(Object? a, Object? b) {
  int parse(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(_s(v)) ?? 0;
  }

  final x = parse(a);
  return x != 0 ? x : parse(b);
}

final discoveryRepository = DiscoveryRepository();
