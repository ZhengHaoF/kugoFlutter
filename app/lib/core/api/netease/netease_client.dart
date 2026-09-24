import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../source/music_source.dart';
import 'netease_crypto.dart';
import 'netease_endpoints.dart';
import 'netease_failures.dart';
import '../network_log.dart';

/// 一期探针用网易客户端：加密 + Cookie 会话 + A1–A4。
///
/// 对齐 NeriPlayer `NeteaseClient` 的请求形态；不做完整 CookieJar 持久化。
class NeteaseClient {
  NeteaseClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                // 避免 br：一期用 gzip/deflate 即可。
                headers: {
                  'Accept': '*/*',
                  'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
                  'Accept-Encoding': 'gzip, deflate',
                  'Connection': 'keep-alive',
                  'Referer': NeteaseEndpoints.mainHost,
                  'User-Agent': _ua,
                },
                responseType: ResponseType.plain,
                validateStatus: (c) => c != null && c >= 200 && c < 500,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['__start'] = DateTime.now().millisecondsSinceEpoch;
          options.extra['__id'] =
              '${DateTime.now().microsecondsSinceEpoch}-${options.uri}';
          if (_cookies.isNotEmpty) {
            options.headers['Cookie'] = _cookieHeader();
          }
          NetworkLogHub.emit(
            NetworkLog(
              id: options.extra['__id'] as String,
              type: NetworkLogType.request,
              timestamp: DateTime.now(),
              method: options.method,
              url: options.uri.toString(),
              headers: sanitizeHeaders(options.headers),
              data: truncateLogData(options.data ?? options.queryParameters),
            ),
          );
          handler.next(options);
        },
        onResponse: (res, handler) {
          _absorbSetCookie(res);
          NetworkLogHub.emit(
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
                milliseconds: DateTime.now().millisecondsSinceEpoch -
                    (res.requestOptions.extra['__start'] as int? ??
                        DateTime.now().millisecondsSinceEpoch),
              ),
            ),
          );
          handler.next(res);
        },
      ),
    );
  }

  static const _ua =
      'Mozilla/5.0 (Linux; Android 10; kugo-netease-probe) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final Dio _dio;
  final Map<String, String> _cookies = {
    'os': 'pc',
    'appver': '8.10.35',
    '__remember_me': 'true',
    '_ntes_nuid': _randomHex(32),
    'NMTID': _randomHex(32),
  };
  bool _preheated = false;

  static final Random _rnd = Random.secure();

  static String _randomHex(int len) {
    final sb = StringBuffer();
    for (var i = 0; i < len; i++) {
      sb.write(_rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  bool get hasLogin => (_cookies['MUSIC_U'] ?? '').isNotEmpty;

  String get csrf => _cookies['__csrf'] ?? '';

  void reset() {
    _cookies
      ..clear()
      ..addAll({
        'os': 'pc',
        'appver': '8.10.35',
        '__remember_me': 'true',
        '_ntes_nuid': _randomHex(32),
        'NMTID': _randomHex(32),
      });
    _preheated = false;
  }

  String _cookieHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _absorbSetCookie(Response res) {
    final raw = res.headers.map['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      final first = line.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty || value == 'deleted') {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  /// GET 首页拿 `__csrf`（WEAPI 前预热）。
  Future<void> ensureWeapiSession() async {
    if (_preheated && csrf.isNotEmpty) return;
    try {
      final res = await _dio.get<String>(
        '${NeteaseEndpoints.mainHost}/',
        options: Options(responseType: ResponseType.plain),
      );
      // eslint-disable-next-line — debug: status + set-cookie 数量
      // ignore: avoid_print
      print('[preheat] status=${res.statusCode} '
          'setCookie=${res.headers.map['set-cookie']?.length ?? 0}');
    } catch (e) {
      // ignore: avoid_print
      print('[preheat] failed: $e');
    }
    _preheated = true;
  }

  Future<String> callWeApi(
    String path,
    Map<String, dynamic> params, {
    bool usePersistedCookies = true,
  }) {
    final p = path.startsWith('/') ? path : '/$path';
    final full = p.startsWith('/weapi') ? p : '/weapi$p';
    return _request(
      url: '${NeteaseEndpoints.mainHost}$full',
      params: params,
      weapi: true,
      usePersistedCookies: usePersistedCookies,
    );
  }

  Future<String> callEApi(
    String path,
    Map<String, dynamic> params, {
    bool usePersistedCookies = true,
  }) {
    final p = path.startsWith('/') ? path : '/$path';
    final full = p.startsWith('/eapi') ? p : '/eapi$p';
    return _request(
      url: '${NeteaseEndpoints.interfaceHost}$full',
      params: params,
      weapi: false,
      usePersistedCookies: usePersistedCookies,
    );
  }

  Future<String> _request({
    required String url,
    required Map<String, dynamic> params,
    required bool weapi,
    bool usePersistedCookies = true,
  }) async {
    if (weapi && usePersistedCookies) {
      await ensureWeapiSession();
    }
    final uri = Uri.parse(url);
    var reqUri = uri;
    final Map<String, String> body;
    if (weapi) {
      body = NeteaseCrypto.weApiEncrypt(params);
      reqUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'csrf_token': usePersistedCookies ? csrf : '',
        },
      );
    } else {
      body = NeteaseCrypto.eApiEncrypt(uri.path, params);
    }

    // 显式 UTF-8 表单体，避免 Dio 对 Map 的编码差异。
    final form = body.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final res = await _dio.post<String>(
      reqUri.toString(),
      data: form,
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=utf-8',
        responseType: ResponseType.plain,
        headers: {'Origin': NeteaseEndpoints.mainHost},
      ),
    );
    return res.data ?? '';
  }

  // ── A1 搜索 ──────────────────────────────────────────────

  Future<String> searchSongsRaw({
    required String keyword,
    int limit = 10,
    int offset = 0,
    int type = 1,
  }) {
    // 默认旧口 search/get（cloudsearch 实测 50000005）。
    return callWeApi(NeteaseEndpoints.search, {
      's': keyword,
      'type': type.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  /// 探针用：逐个试搜索路径/参数，定位 50000005。
  Future<String> searchSongsDebug(String keyword) async {
    Future<String> tryCall(String label, Future<String> Function() call) async {
      try {
        final raw = await call();
        final code = RegExp(r'"code"\s*:\s*(-?\d+)').firstMatch(raw)?.group(1);
        // ignore: avoid_print
        print('[A1-try $label] code=$code len=${raw.length} '
            '${raw.substring(0, raw.length.clamp(0, 140))}');
        if (code == '200') return raw;
      } catch (err) {
        // ignore: avoid_print
        print('[A1-try $label] ERR $err');
      }
      return '';
    }

    final body = {
      's': keyword,
      'type': '1',
      'limit': '5',
      'offset': '0',
      'total': 'true',
    };

    final raw = await tryCall(
      'weapi/cloudsearch',
      () => callWeApi('/weapi/cloudsearch/get/web', body),
    );
    if (raw.isNotEmpty) return raw;

    final raw2 = await tryCall(
      'weapi/search/get',
      () => callWeApi('/weapi/search/get', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
      }),
    );
    if (raw2.isNotEmpty) return raw2;

    final raw3 = await tryCall(
      'eapi/cloudsearch/pc',
      () => callEApi('/eapi/cloudsearch/pc', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
        'total': 'true',
      }),
    );
    if (raw3.isNotEmpty) return raw3;

    final raw4 = await tryCall(
      'eapi/search/get',
      () => callEApi('/eapi/search/get', {
        's': keyword,
        'type': '1',
        'limit': '5',
        'offset': '0',
      }),
    );
    if (raw4.isNotEmpty) return raw4;

    // interface3 host + cloudsearch
    final raw5 = await tryCall('iface3-cloudsearch', () async {
      final uri = Uri.parse(
        'https://interface3.music.163.com/weapi/cloudsearch/get/web',
      ).replace(queryParameters: {'csrf_token': csrf});
      final enc = NeteaseCrypto.weApiEncrypt(body);
      final form = enc.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final res = await _dio.post<String>(
        uri.toString(),
        data: form,
        options: Options(
          contentType: 'application/x-www-form-urlencoded; charset=utf-8',
          responseType: ResponseType.plain,
        ),
      );
      return res.data ?? '';
    });
    if (raw5.isNotEmpty) return raw5;

    throw const UpstreamChanged('all search variants failed');
  }

  // ── A2 播放 URL ──────────────────────────────────────────

  Future<String> songPlayUrlRaw(
    int songId, {
    String level = 'exhigh',
  }) {
    return callEApi(NeteaseEndpoints.songPlayUrlV1, {
      'ids': '[$songId]',
      'level': level,
      'encodeType': 'flac',
    });
  }

  Future<String> songPlayUrlWeapiRaw(int songId, {int br = 320000}) {
    return callWeApi(NeteaseEndpoints.songPlayUrlWeapi, {
      'ids': '[$songId]',
      'br': br.toString(),
    });
  }

  // ── A3 歌词 ──────────────────────────────────────────────

  Future<String> songLyricRaw(int songId) {
    return callEApi(NeteaseEndpoints.songLyricV1, {
      'id': songId.toString(),
      'cp': 'false',
      'lv': 0,
      'tv': 1,
      'rv': 0,
      'yv': 1,
      'ytv': 1,
      'yrv': 0,
    });
  }

  Future<String> songLyricPlainRaw(int songId) async {
    final res = await _dio.get<String>(
      NeteaseEndpoints.plainUrl(NeteaseEndpoints.songLyricPlain),
      queryParameters: {
        'id': songId,
        'lv': -1,
        'tv': -1,
        'rv': -1,
        'yv': -1,
        'ytv': -1,
        'yrv': -1,
      },
    );
    return res.data ?? '';
  }

  // ── A4 详情 ──────────────────────────────────────────────

  Future<String> songDetailRaw(List<int> ids) {
    final idsCsv = ids.join(',');
    final c = [for (final id in ids) '{"id":$id}'].join(',');
    return callWeApi(NeteaseEndpoints.songDetail, {
      'c': '[$c]',
      'ids': '[$idsCsv]',
    });
  }
}

// ── 轻量解析 DTO（探针/一期用） ────────────────────────────

class ProbeSong {
  const ProbeSong({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.durationMs,
    this.picUrl = '',
  });

  final int id;
  final String name;
  final String artists;
  final String album;
  final int durationMs;
  final String picUrl;

  @override
  String toString() =>
      'ProbeSong($id, $name, $artists, $album, ${durationMs}ms)';
}

class ProbePlayUrl {
  const ProbePlayUrl({
    required this.url,
    this.type = '',
    this.level = '',
    this.size = 0,
    this.isPreviewClip = false,
    this.fee = 0,
    this.dataCode = 200,
  });

  final String url;
  final String type;
  final String level;
  final int size;
  final bool isPreviewClip;
  final int fee;
  final int dataCode;
}

class ProbeLyric {
  const ProbeLyric({
    this.lrc = '',
    this.yrc = '',
    this.tlyric = '',
    this.romalrc = '',
  });

  final String lrc;
  final String yrc;
  final String tlyric;
  final String romalrc;

  bool get isEmpty => lrc.isEmpty && yrc.isEmpty;
}

List<ProbeSong> parseProbeSongs(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int?;
  if (code != null && code != 200) {
    throw mapNeteaseCode(code, message: 'search failed code=$code');
  }
  final result = root['result'] as Map<String, dynamic>?;
  final songs = result?['songs'] as List? ?? const [];
  return [
    for (final item in songs)
      if (item is Map)
        (() {
          final m = Map<String, dynamic>.from(item);
          final artists = m['ar'] ?? m['artists'] ?? const [];
          final album = m['al'] ?? m['album'] ?? const {};
          var albumName = album is Map ? '${album['name'] ?? ''}' : '';
          var pic = album is Map ? '${album['picUrl'] ?? ''}' : '';
          // 旧 search/get：album.artist / album.picUrl 等。
          if (album is Map) {
            albumName = albumName.isEmpty ? '${album['name'] ?? ''}' : albumName;
            pic = pic.isEmpty ? '${album['picUrl'] ?? album['blurPicUrl'] ?? ''}' : pic;
          }
          final artistList = <String>[];
          if (artists is List) {
            for (final a in artists) {
              if (a is Map) artistList.add('${a['name'] ?? ''}');
            }
          }
          if (artistList.isEmpty && album is Map && album['artist'] is Map) {
            artistList.add('${(album['artist'] as Map)['name'] ?? ''}');
          }
          if (artistList.isEmpty && m['artist'] is Map) {
            artistList.add('${(m['artist'] as Map)['name'] ?? ''}');
          }
          return ProbeSong(
            id: (m['id'] as num?)?.toInt() ?? 0,
            name: '${m['name'] ?? ''}',
            artists: artistList.join('/'),
            album: albumName,
            durationMs: ((m['dt'] ?? m['duration'] ?? 0) as num).toInt(),
            picUrl: pic,
          );
        })(),
  ];
}

ProbePlayUrl parseProbePlayUrl(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int? ?? -1;
  if (code == 301) {
    throw const LoginRequired('code=301');
  }
  if (code != 200) {
    throw mapNeteaseCode(code, message: 'play url code=$code');
  }
  final data = root['data'];
  final item = data is List && data.isNotEmpty
      ? data.first
      : (data is Map ? data : null);
  if (item is! Map) {
    throw const NotFound('play url data empty');
  }
  final m = Map<String, dynamic>.from(item);
  final url = '${m['url'] ?? ''}';
  final fee = (m['fee'] as num?)?.toInt() ?? 0;
  final dataCode = (m['code'] as num?)?.toInt() ?? 200;
  final freeTrial = m['freeTrialInfo'];
  final hasTrial = freeTrial != null && freeTrial != false;
  if (url.isEmpty || url == 'null') {
    final cannot = (m['freeTrialPrivilege'] is Map)
        ? ((m['freeTrialPrivilege'] as Map)['cannotListenReason'] as num?)
            ?.toInt()
        : null;
    throw mapNeteasePlayFailure(
      dataCode: dataCode,
      fee: fee,
      cannotListenReason: cannot,
    );
  }
  return ProbePlayUrl(
    url: url,
    type: '${m['type'] ?? ''}',
    level: '${m['level'] ?? ''}',
    size: (m['size'] as num?)?.toInt() ?? 0,
    isPreviewClip: hasTrial,
    fee: fee,
    dataCode: dataCode,
  );
}

ProbeLyric parseProbeLyric(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final code = root['code'] as int?;
  if (code != null && code != 200) {
    throw mapNeteaseCode(code, message: 'lyric code=$code');
  }
  String pick(String key) {
    final node = root[key];
    if (node is Map) return '${node['lyric'] ?? ''}';
    return '';
  }

  return ProbeLyric(
    lrc: pick('lrc'),
    yrc: pick('yrc'),
    tlyric: pick('tlyric'),
    romalrc: pick('romalrc'),
  );
}

/// 解析 weapi/v3/song/detail 的第一首歌名。
String? parseProbeDetailTitle(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final songs = root['songs'] as List?;
  if (songs == null || songs.isEmpty) return null;
  final s = songs.first;
  return s is Map ? '${s['name']}' : null;
}
