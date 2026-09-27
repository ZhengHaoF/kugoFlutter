/// 酷狗 MV / 视频仓库：搜索、歌曲关联、详情、取流。
///
/// 协议对齐 KuGouMusicApi `search.js` / `kmr_audio_mv.js` / `video_detail.js` /
/// `video_url.js`，探测记录见 `tool/probe_mv.dart` 与 `docs/api-notes.md`。
///
/// ID 坑（已踩）：
/// - `kmr/audio/mv` 的 `album_audio_id` 必须是 **MixSongID**，不是 AudioID/mixsongid
/// - 播放 hash 用 **MvHash / 分档 hash**，不是歌曲搜索里的 `mvhash`（那是 h264.qhd）
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugou/kugo_client.dart';
import '../../core/api/kugou/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl, formatCount;
import '../../core/models/mv_models.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/source/music_source.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

class MvRepository {
  MvRepository({KugoClient? client, Dio? dio})
      : _client = client ?? kugoClient,
        _dio = dio ?? _createDio();

  final KugoClient _client;
  final Dio _dio;

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

  // ── 搜索 ──────────────────────────────────────────────────────

  /// `search/mv`（mobilecdn 简版）+ gateway 富版合并。
  /// 富版字段更全（MvID / MixSongID），优先用它；简版兜底。
  Future<SearchPageResult<MvBrief>> searchMvs(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async {
    // 先打富版（需要签名）。
    try {
      final rich = await _searchMvRich(keyword, page: page, pageSize: pageSize);
      if (rich.items.isNotEmpty) return rich;
    } on SourceFailure {
      // 回落简版。
    } catch (_) {
      // 回落简版。
    }
    return _searchMvSimple(keyword, page: page, pageSize: pageSize);
  }

  Future<SearchPageResult<MvBrief>> _searchMvSimple(
    String keyword, {
    required int page,
    required int pageSize,
  }) async {
    final body = await _client.getJson(
      '${KugoEndpoints.mobileCdn}${KugoEndpoints.searchMv}',
      query: {
        'format': 'json',
        'keyword': keyword,
        'page': page,
        'pagesize': pageSize,
      },
    );
    final map = body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};
    final items = _infoListRows(map)
        .map(_mapSimpleSearchItem)
        .where((m) => m.hash.isNotEmpty || m.name.isNotEmpty)
        .toList();
    return SearchPageResult(items: items, total: _totalOf(map));
  }

  Future<SearchPageResult<MvBrief>> _searchMvRich(
    String keyword, {
    required int page,
    required int pageSize,
  }) async {
    final query = await _defaultQuery()
      ..addAll({
        'albumhide': 0,
        'iscorrection': 1,
        'keyword': keyword,
        'nocollect': 0,
        'page': page,
        'pagesize': pageSize,
        'platform': 'AndroidFilter',
      });
    query['signature'] = KugoSign.signatureAndroidParams(query);

    final body = await _signedGet(
      KugoEndpoints.searchMvRich,
      query: query,
      router: KugoEndpoints.complexSearchRouter,
    );
    final lists = (body['data'] is Map)
        ? ((body['data'] as Map)['lists'] as List? ?? const [])
        : const [];
    final items = lists
        .whereType<Map>()
        .map((e) => _mapRichSearchItem(Map<String, dynamic>.from(e)))
        .where((m) => m.hash.isNotEmpty || m.name.isNotEmpty)
        .toList();
    final total = (body['data'] is Map)
        ? ((body['data'] as Map)['total'] as num?)?.toInt()
        : null;
    return SearchPageResult(items: items, total: total);
  }

  // ── 歌曲关联 MV ───────────────────────────────────────────────

  /// `POST /kmr/v1/audio/mv`。[track.mixSongId] 是唯一合法入参（见文件头）。
  Future<List<MvBrief>> songMvs(Track track) async {
    final albumAudioId = track.mixSongId.trim();
    if (albumAudioId.isEmpty) return const [];

    final body = <String, dynamic>{
      'data': [
        {'album_audio_id': albumAudioId},
      ],
      'fields': 'mkv,tags,h264,h265,authors',
    };
    final bodyJson = jsonEncode(body);
    final query = await _defaultQuery();
    query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

    final res = await _signedPost(
      KugoEndpoints.kmrAudioMv,
      query: query,
      body: body,
      router: KugoEndpoints.openApiRouter,
      kgTid: '38',
    );

    // 响应 `data` 是 `[[{...}, ...]]` 或 `[{...}]` 或 `[{}]`。
    final data = res['data'];
    final rows = <Map<String, dynamic>>[];
    if (data is List) {
      for (final entry in data) {
        if (entry is List) {
          rows.addAll(entry.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        } else if (entry is Map && entry.isNotEmpty) {
          rows.add(Map<String, dynamic>.from(entry));
        }
      }
    }
    return rows.map(_mapKmrItem).where((m) => m.hash.isNotEmpty).toList();
  }

  // ── 详情 + 取流 ───────────────────────────────────────────────

  /// `POST /v1/video`。鉴权字段在 body（KuGouMusicApi `clearDefaultParams`）。
  Future<MvDetail?> fetchMvDetail(MvBrief brief) async {
    final videoId = brief.id.trim();
    if (videoId.isEmpty) return null;

    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      'mid': device.mid,
      'uuid': KugoSign.md5Hex('${device.dfid}${device.mid}'),
      'dfid': device.dfid,
      'token': AuthTokenHolder.instance.token,
      'key': KugoSign.signParamsKey('$clienttime'),
      'show_resolution': 1,
      'data': [
        {'video_id': videoId},
      ],
    };
    final bodyJson = jsonEncode(body);
    // 探针确认 A/B 两种签名都通；用 A（query 空 + signature 覆 body）。
    final query = <String, dynamic>{};
    query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

    final res = await _signedPost(
      KugoEndpoints.videoDetail,
      query: query,
      body: body,
      router: KugoEndpoints.kmrServiceRouter,
    );
    final data = res['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) return null;
    final map = Map<String, dynamic>.from(first);
    return _mapDetail(map, brief);
  }

  /// `GET /v2/interface/index` + `x-router: trackermv.kugou.com`。
  /// `key = signKey(hash, mid)`，响应 `data[hash].downurl` + `backupdownurl[]`。
  Future<MvPlayUrlResult> resolveMvPlayUrl(String hash) async {
    final h = hash.trim().toLowerCase();
    if (h.isEmpty) {
      throw const NotFound('缺少视频 hash');
    }
    final device = await DeviceIdentity.ensure();
    final query = await _defaultQuery()
      ..addAll({
        'backupdomain': 1,
        'cmd': 123,
        'ext': 'mp4',
        'ismp3': 0,
        'hash': h,
        'pid': 1,
        'type': 1,
      });
    query['key'] = KugoSign.signKey(h, device.mid);
    query['signature'] = KugoSign.signatureAndroidParams(query);

    final res = await _signedGet(
      KugoEndpoints.videoUrl,
      query: query,
      router: KugoEndpoints.trackerMvRouter,
    );
    final data = res['data'];
    final entry = (data is Map) ? data[h] ?? data[hash.trim()] : null;
    if (entry is! Map) {
      throw const NotFound('视频地址为空');
    }
    final map = Map<String, dynamic>.from(entry);
    final url = '${map['downurl'] ?? map['url'] ?? map['play_url'] ?? ''}';
    final backup = (map['backupdownurl'] as List? ?? const [])
        .map((e) => '$e')
        .where((s) => s.isNotEmpty)
        .toList();
    if (url.isEmpty && backup.isEmpty) {
      throw const NotFound('视频地址为空');
    }
    final filesize = int.tryParse('${map['filesize'] ?? 0}') ?? 0;
    return MvPlayUrlResult(
      url: url.isEmpty ? backup.first : url,
      backupUrls: url.isEmpty ? backup.skip(1).toList() : backup,
      filesize: filesize,
    );
  }

  // ── mapper ────────────────────────────────────────────────────

  MvBrief _mapSimpleSearchItem(Map<String, dynamic> m) {
    final hash = '${m['hash'] ?? ''}'.trim().toLowerCase();
    final name = '${m['filename'] ?? m['MvName'] ?? ''}';
    final picRaw = '${m['imgurl'] ?? m['pic'] ?? ''}';
    final durationSec = int.tryParse('${m['duration'] ?? 0}') ?? 0;
    return MvBrief(
      id: '',
      hash: hash,
      name: name,
      coverUrl: normalizeCoverUrl(picRaw.isEmpty ? hash : picRaw),
      artist: '${m['singername'] ?? ''}',
      durationMs: durationSec * 1000,
      publishDate: '${m['publishdate'] ?? ''}',
    );
  }

  MvBrief _mapRichSearchItem(Map<String, dynamic> m) {
    final hash = '${m['MvHash'] ?? m['hash'] ?? ''}'.trim().toLowerCase();
    final id = '${m['MvID'] ?? m['video_id'] ?? ''}';
    final picRaw = '${m['Pic'] ?? m['pic'] ?? ''}';
    final durationSec = int.tryParse('${m['Duration'] ?? m['duration'] ?? 0}') ?? 0;
    final singers = (m['Singers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => '${e['name'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    final singerId = (m['SingerID'] is List && (m['SingerID'] as List).isNotEmpty)
        ? '${(m['SingerID'] as List).first}'
        : '';
    return MvBrief(
      id: id,
      hash: hash,
      name: '${m['MvName'] ?? m['FileName'] ?? ''}',
      coverUrl: normalizeCoverUrl(picRaw.isEmpty ? hash : picRaw),
      artist: singers.isEmpty ? '${m['SingerName'] ?? ''}' : singers.join(' / '),
      artistId: singerId,
      durationMs: durationSec * 1000,
      publishDate: '${m['PublishDate'] ?? ''}',
      qualityMark: '${m['MvHashMark'] ?? ''}',
      mixSongId: '${m['MixSongID'] ?? ''}',
      audioHash: '${m['FileHash'] ?? ''}'.toLowerCase(),
    );
  }

  MvBrief _mapKmrItem(Map<String, dynamic> m) {
    final mkv = m['mkv'] is Map ? Map<String, dynamic>.from(m['mkv'] as Map) : const <String, dynamic>{};
    final h264 = m['h264'] is Map ? Map<String, dynamic>.from(m['h264'] as Map) : const <String, dynamic>{};
    final hash = ('${mkv['sd_hash'] ?? h264['sd_hash'] ?? m['hash'] ?? ''}')
        .trim()
        .toLowerCase();
    final thumbRaw = '${m['thumb'] ?? m['hdpic'] ?? m['cover'] ?? ''}';
    final durationMs = int.tryParse('${m['timelength'] ?? 0}') ??
        ((int.tryParse('${m['audio_timelength'] ?? 0}') ?? 0) > 1000
            ? int.tryParse('${m['audio_timelength'] ?? 0}') ?? 0
            : (int.tryParse('${m['audio_timelength'] ?? 0}') ?? 0) * 1000);
    final authors = (m['authors'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => '${e['author_name'] ?? e['name'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    return MvBrief(
      id: '${m['video_id'] ?? m['id'] ?? ''}',
      hash: hash,
      name: '${m['video_name'] ?? m['name'] ?? ''}',
      coverUrl: normalizeCoverUrl(thumbRaw.isEmpty ? hash : thumbRaw),
      artist: authors.isEmpty ? '${m['user_name'] ?? ''}' : authors.join(' / '),
      durationMs: durationMs,
      publishDate: '${m['publish_date'] ?? ''}',
      mixSongId: '${m['album_audio_id'] ?? m['audio_id'] ?? ''}',
      audioHash: '${m['audio_hash'] ?? ''}'.toLowerCase(),
    );
  }

  MvDetail _mapDetail(Map<String, dynamic> m, MvBrief brief) {
    final sources = _extractSources(m);
    sources.sort((a, b) => b.isClearerThan(a) ? 1 : (a.isClearerThan(b) ? -1 : 0));
    final playTimes = int.tryParse('${m['play_times'] ?? m['playTimes'] ?? 0}') ?? 0;
    final downloads = int.tryParse('${m['download_total'] ?? 0}') ?? 0;
    final authors = <String>[
      if ('${m['author_name'] ?? ''}'.isNotEmpty) '${m['author_name']}',
      ...brief.artist.split(' / ').where((s) => s.isNotEmpty),
    ];
    final name = '${m['video_name'] ?? brief.name}';
    final coverRaw = '${m['hdpic'] ?? m['thumb'] ?? brief.coverUrl}';
    return MvDetail(
      brief: MvBrief(
        id: brief.id.isEmpty ? '${m['video_id'] ?? ''}' : brief.id,
        hash: brief.hash.isEmpty
            ? ('${m['sd_hash'] ?? m['hash'] ?? ''}').toLowerCase()
            : brief.hash,
        name: name,
        coverUrl: normalizeCoverUrl(coverRaw),
        artist: authors.isNotEmpty ? authors.first : brief.artist,
        artistId: brief.artistId,
        durationMs: brief.durationMs,
        publishDate: '${m['publish_date'] ?? brief.publishDate}',
        qualityMark: brief.qualityMark,
        mixSongId: '${m['audio_id'] ?? brief.mixSongId}',
        audioHash: '${m['audio_hash'] ?? ''}'.toLowerCase(),
      ),
      sources: sources,
      description: '${m['topic'] ?? m['remark'] ?? m['intro'] ?? ''}',
      playCountLabel: playTimes > 0 ? formatCount(playTimes) : '',
      downloadCountLabel: downloads > 0 ? formatCount(downloads) : '',
      authors: authors.toSet().toList(),
    );
  }

  /// 从 `video/detail` 的扁平字段 / `kmr/audio/mv` 的嵌套 `h264`/`h265`/`mkv`
  /// 抽出片源。字段命名：`{codec}_{quality}_hash` 或嵌套 `{codec}.{quality}_hash`。
  List<MvPlaySource> _extractSources(Map<String, dynamic> m) {
    final out = <MvPlaySource>[];

    void add(String hash, String label, String codec, {int w = 0, int h = 0, int size = 0, int br = 0}) {
      final v = hash.trim().toLowerCase();
      if (v.isEmpty) return;
      out.add(MvPlaySource(
        hash: v,
        label: label,
        codec: codec,
        width: w,
        height: h,
        filesize: size,
        bitrate: br,
      ));
    }

    // 扁平形态（video/detail）：ld/sd/qhd/hd/fhd + 可选 _265。
    const qualityOf = {
      'fhd': ('1080P', 1080, 1920),
      'hd': ('720P', 720, 1280),
      'qhd': ('540P', 540, 960),
      'sd': ('432P', 432, 768),
      'ld': ('270P', 270, 480),
    };
    for (final e in qualityOf.entries) {
      final q = e.key;
      final (label, h, w) = e.value;
      add(
        '${m['${q}_hash'] ?? ''}',
        label,
        'h264',
        w: w,
        h: h,
        size: int.tryParse('${m['${q}_filesize'] ?? 0}') ?? 0,
        br: int.tryParse('${m['${q}_bitrate'] ?? 0}') ?? 0,
      );
      add(
        '${m['${q}_hash_265'] ?? ''}',
        label,
        'h265',
        w: w,
        h: h,
        size: int.tryParse('${m['${q}_filesize_265'] ?? 0}') ?? 0,
        br: int.tryParse('${m['${q}_bitrate_265'] ?? 0}') ?? 0,
      );
      add(
        '${m['mkv_${q}_hash'] ?? ''}',
        label,
        'mkv',
        w: int.tryParse('${m['mkv_${q}_width'] ?? w}') ?? w,
        h: int.tryParse('${m['mkv_${q}_height'] ?? h}') ?? h,
        size: int.tryParse('${m['mkv_${q}_filesize'] ?? 0}') ?? 0,
        br: int.tryParse('${m['mkv_${q}_bitrate'] ?? 0}') ?? 0,
      );
    }

    // 嵌套形态（kmr/audio/mv）：{h264,h265,mkv}.{q}_hash。
    for (final codec in const ['h264', 'h265', 'mkv']) {
      final nested = m[codec];
      if (nested is! Map) continue;
      final n = Map<String, dynamic>.from(nested);
      for (final e in qualityOf.entries) {
        final q = e.key;
        final (label, h, w) = e.value;
        add(
          '${n['${q}_hash'] ?? ''}',
          label,
          codec,
          w: int.tryParse('${n['${q}_width'] ?? w}') ?? w,
          h: int.tryParse('${n['${q}_height'] ?? h}') ?? h,
          size: int.tryParse('${n['${q}_filesize'] ?? 0}') ?? 0,
          br: int.tryParse('${n['${q}_bitrate'] ?? 0}') ?? 0,
        );
      }
    }

    // 去重（同 hash 保留第一档）。
    final seen = <String>{};
    return out.where((s) => seen.add(s.hash)).toList();
  }

  // ── 网络 ──────────────────────────────────────────────────────

  Map<String, dynamic> _infoList(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final info = data['info'] ?? data['lists'];
      if (info is List) return {'info': info, 'total': data['total']};
    }
    return const {};
  }

  List<Map<String, dynamic>> _infoListRows(Map<String, dynamic> body) {
    final info = _infoList(body)['info'];
    return (info as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int? _totalOf(Map<String, dynamic> body) {
    final t = _infoList(body)['total'];
    return t is num ? t.toInt() : null;
  }

  Future<Map<String, dynamic>> _defaultQuery() async {
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final userId = auth.userId.isNotEmpty && auth.userId != '0' ? auth.userId : '';
    final userIdNum = int.tryParse(userId) ?? 0;
    return {
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      if (auth.hasToken) 'token': auth.token,
      if (userIdNum != 0) 'userid': userIdNum,
    };
  }

  Map<String, String> _headers({
    required String dfid,
    required String mid,
    required String guid,
    String? router,
    String? kgTid,
    bool json = false,
  }) {
    return {
      'User-Agent': KugoSign.userAgent,
      if (json) 'Content-Type': 'application/json',
      'dfid': dfid,
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'mid': mid,
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      'x-router': ?router,
      'kg-tid': ?kgTid,
      'Cookie': [
        'dfid=$dfid',
        'KUGOU_API_MID=$mid',
        'KUGOU_API_GUID=$guid',
      ].join(';'),
    };
  }

  Future<Map<String, dynamic>> _signedGet(
    String path, {
    required Map<String, dynamic> query,
    String? router,
    String baseUrl = KugoEndpoints.gateway,
  }) async {
    final device = await DeviceIdentity.ensure();
    try {
      final res = await _dio.get<dynamic>(
        '$baseUrl$path',
        queryParameters: query,
        options: Options(
          headers: _headers(
            dfid: device.dfid,
            mid: device.mid,
            guid: device.guid,
            router: router,
          ),
          responseType: ResponseType.plain,
        ),
      );
      return _asMap(res.data);
    } on KugoApiException catch (e) {
      throw _mapFailure(e);
    } on DioException catch (e) {
      throw NetworkFailure(e.message ?? '网络错误');
    }
  }

  Future<Map<String, dynamic>> _signedPost(
    String path, {
    required Map<String, dynamic> query,
    required Map<String, dynamic> body,
    String? router,
    String? kgTid,
    String baseUrl = KugoEndpoints.gateway,
  }) async {
    final device = await DeviceIdentity.ensure();
    try {
      final res = await _dio.post<dynamic>(
        '$baseUrl$path',
        queryParameters: query,
        data: jsonEncode(body),
        options: Options(
          headers: _headers(
            dfid: device.dfid,
            mid: device.mid,
            guid: device.guid,
            router: router,
            kgTid: kgTid,
            json: true,
          ),
          responseType: ResponseType.plain,
        ),
      );
      return _asMap(res.data);
    } on KugoApiException catch (e) {
      throw _mapFailure(e);
    } on DioException catch (e) {
      throw NetworkFailure(e.message ?? '网络错误');
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    final decoded = decodeKugoBody(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const UpstreamChanged('MV 接口响应无法解析');
  }

  SourceFailure _mapFailure(KugoApiException e) {
    if (e.filtered) return NetworkFailure(e.message, filtered: true);
    final code = e.code;
    if (code == 20028) return LoginRequired('需要登录/安全验证');
    if (code == 20006) return UpstreamChanged('签名失败（20006）');
    return UpstreamChanged(e.message);
  }
}

/// 全局单例（与其它 repository 一致）。
final MvRepository mvRepository = MvRepository();
