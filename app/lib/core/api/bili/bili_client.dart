import 'dart:convert';

import 'package:dio/dio.dart';

import '../../source/music_source.dart';
import '../network_log.dart';
import 'bili_endpoints.dart';
import 'bili_failures.dart';
import 'bili_sign.dart';

/// B 站 Web API 客户端（B1 探针范围）。
///
/// 覆盖：匿名设备指纹（I3）、WBI 签名材料（I1）+ WebTicket 兜底（I2）、
/// 搜索视频（A1）、分 P 列表（B2）、视频信息（C1）、取流（B1）。
/// 扫码登录（G1/G2）与内容面（D/E 组）属 B3/B4，本类先留端点不建方法。
///
/// 对齐 NeriPlayer `core/api/bili/BiliClient.kt` 的请求形态：
/// Web UA + `Referer: https://www.bilibili.com` + Set-Cookie 吸收合并。
class BiliClient {
  BiliClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json, text/plain, */*',
                  'Accept-Language': 'zh-CN,zh-Hans;q=0.9',
                  // 避免 br：Dio 默认不解 brotli。
                  'Accept-Encoding': 'gzip, deflate',
                  'Referer': BiliEndpoints.referer,
                  'User-Agent': BiliEndpoints.webUA,
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
              data: truncateLogData(options.queryParameters),
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

  final Dio _dio;
  final Map<String, String> _cookies = {};

  String? _mixinKey;
  int _mixinKeyAt = 0;
  static const _mixinKeyTtl = Duration(minutes: 10);

  Map<String, String>? _anonCookies;
  int _anonCookiesAt = 0;
  static const _anonCookiesTtl = Duration(hours: 1);

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  /// 是否带登录 Cookie（只看 SESSDATA，方案 §3.3）。
  bool get hasLogin => (_cookies['SESSDATA'] ?? '').isNotEmpty;

  /// 探针 / B3 落盘恢复用：灌入 Cookie。
  void seedCookies(Map<String, String> cookies) => _cookies.addAll(cookies);

  void clearCookies() {
    _cookies.clear();
    _anonCookies = null;
    _mixinKey = null;
  }

  /// 内容接口统一复用 Cookie、错误映射与 WBI 管线。
  Future<Map<String, dynamic>> content(
    String path,
    Map<String, String> params, {
    bool signed = false,
  }) =>
      signed
          ? _getWbiJson(path, params, path)
          : _getJson(path, params, path);

  // ── 基础设施 ──────────────────────────────────────────────

  /// I3 匿名设备指纹。未登录也要能请求；缓存 1 小时（方案 §3.3）。
  ///
  /// **2026-10 实测口径变化**：`spi` 现在只在 **JSON body** 里给
  /// `b_3` / `b_4`（`buvid_fp` 系列字段已不再返回，也没有 Set-Cookie 头），
  /// 所以要把 body 里的值**种进 [_cookies]**，后续请求才会带上。
  Future<Map<String, String>> ensureAnonCookies({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _anonCookies != null &&
        now - _anonCookiesAt < _anonCookiesTtl.inMilliseconds) {
      return _anonCookies!;
    }
    final data = await _getJson(BiliEndpoints.fingerSpi, const {}, 'I3 spi');
    final picked = <String, String>{};
    for (final key in const ['b_3', 'b_4', 'buvid_fp', 'buvid_fp_plain']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) picked[key] = v;
    }
    if (picked.isEmpty) {
      throw StateError('I3 spi: 未返回 buvid 系列字段');
    }
    _anonCookies = picked;
    _anonCookiesAt = now;
    // body 直取 → 手动种入 Cookie（该口没有 Set-Cookie）。
    _cookies.addAll(picked);
    return picked;
  }

  /// I1 WBI 签名材料。缓存 10 分钟（方案 §3.1）。
  ///
  /// **2026-10 实测口径**：`nav` 对匿名请求返回 `code=-101`（账号未登录），
  /// 但 `data.wbi_img` **照常返回**——所以这里不能走 [BiliFailures] 的
  /// code 校验，要手动解包，只要有 wbi_img 就用。
  Future<String> mixinKey({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _mixinKey != null &&
        now - _mixinKeyAt < _mixinKeyTtl.inMilliseconds) {
      return _mixinKey!;
    }
    final res = await _dio.get<dynamic>('${BiliEndpoints.apiHost}${BiliEndpoints.nav}');
    final body =
        res.data is String ? jsonDecode(res.data as String) : res.data;
    if (body is! Map<String, dynamic>) {
      throw const UpstreamChanged('I1 nav: 响应不是 JSON 对象');
    }
    final data = body['data'];
    final img = data is Map<String, dynamic> ? data['wbi_img'] : null;
    if (img is! Map<String, dynamic>) {
      throw const UpstreamChanged('I1 nav: 缺少 wbi_img');
    }
    final imgUrl = img['img_url'];
    final subUrl = img['sub_url'];
    if (imgUrl is! String || subUrl is! String) {
      throw const UpstreamChanged('I1 nav: wbi_img 缺少 img_url/sub_url');
    }
    final key = BiliSign.mixinKeyFromUrls(imgUrl, subUrl);
    _mixinKey = key;
    _mixinKeyAt = now;
    return key;
  }

  // ── 业务 ──────────────────────────────────────────────────

  /// A1 搜索视频（`search_type=video`）。一个视频 = 一条候选曲目（默认 P1）。
  ///
  /// 注意：该接口**不返回 cid**（方案 §5.3 #5），故搜索态身份用裸 bvid，
  /// cid 在取流时经 [pages] 懒取。
  Future<BiliVideoPage> searchVideos(
    String keyword, {
    int page = 1,
    String order = 'totalrank',
    int duration = 0,
    int? tids,
  }) async {
    final params = <String, String>{
      'search_type': 'video',
      'keyword': keyword,
      'order': order,
      'duration': duration.toString(),
      'page': page.toString(),
    };
    if (tids != null) params['tids'] = tids.toString();

    final data = await _getWbiJson(BiliEndpoints.searchType, params, 'A1 search');
    final result = data['result'];
    final items = <BiliVideoItem>[];
    if (result is List) {
      for (final raw in result) {
        if (raw is! Map<String, dynamic>) continue;
        // result 里混有非视频卡片（如直播间/番剧），按 type 过滤。
        if (raw['type'] != 'video') continue;
        items.add(BiliVideoItem.fromJson(raw));
      }
    }
    return BiliVideoPage(
      items: items,
      numResults: _asInt(data['numResults']) ?? items.length,
      numPages: _asInt(data['numPages']) ?? 1,
      page: _asInt(data['page']) ?? page,
    );
  }

  /// B2 分 P 列表：裸 bvid → 各 P 的 cid（不带签名）。
  /// 注意：该接口的 `data` 直接就是分 P **数组**。
  Future<List<BiliPage>> pages(String bvid) async {
    final list = await _getJsonList(
      BiliEndpoints.pagelist,
      {'bvid': bvid},
      'B2 pagelist',
    );
    final pages = <BiliPage>[];
    for (final raw in list) {
      if (raw is Map<String, dynamic>) pages.add(BiliPage.fromJson(raw));
    }
    return pages;
  }

  /// C1 视频信息（bvid → 标题/UP 主/分 P 数等）。返回原始 data，
  /// 探针按需打印（B2 建 mapper 时再收敛字段）。
  Future<Map<String, dynamic>> videoBasicInfo(String bvid) =>
      _getWbiJson(BiliEndpoints.view, {'bvid': bvid}, 'C1 view');

  /// B1 取流。默认 `fnval=272`（DASH + 杜比，方案 §3.5）。
  ///
  /// [tryLook]=1 让游客态也试拉较高码率（对齐 NeriPlayer PlayOptions）。
  Future<BiliPlayInfo> playUrl({
    required String bvid,
    required int cid,
    int fnval = BiliEndpoints.fnvalDefault,
    String platform = 'pc',
    int? tryLook,
  }) async {
    final params = <String, String>{
      'bvid': bvid,
      'cid': cid.toString(),
      'fnval': fnval.toString(),
      'fnver': '0',
      'fourk': '0',
      'platform': platform,
    };
    if (tryLook != null) params['try_look'] = tryLook.toString();

    final data =
        await _getWbiJson(BiliEndpoints.playurl, params, 'B1 playurl');
    return BiliPlayInfo.fromJson(data);
  }

  /// G3 登录校验：复用 `nav`（登录态下 `data.isLogin/mid/uname` 才有值）。
  /// 未登录返回 null（匿名时 nav 的 code 是 -101，见 [mixinKey] 注）。
  Future<BiliAccount?> currentAccount() async {
    final res = await _dio
        .get<dynamic>('${BiliEndpoints.apiHost}${BiliEndpoints.nav}');
    final body =
        res.data is String ? jsonDecode(res.data as String) : res.data;
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic> || data['isLogin'] != true) return null;
    return BiliAccount(
      mid: data['mid'] is int ? data['mid'] as int : 0,
      uname: data['uname'] is String ? data['uname'] as String : '',
    );
  }

  // ── HTTP 内部 ─────────────────────────────────────────────

  /// 明文 GET（不带 WBI）：body → `data` 对象（code 校验）。
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> params,
    String what,
  ) async {
    final res = await _dio.get<dynamic>(
      '${BiliEndpoints.apiHost}$path',
      queryParameters: params.isEmpty ? null : params,
    );
    return _decode(res, what, BiliFailures.requireOkMap);
  }

  /// 明文 GET（data 为数组的接口用，如 `pagelist`）。
  Future<List<dynamic>> _getJsonList(
    String path,
    Map<String, String> params,
    String what,
  ) async {
    final res = await _dio.get<dynamic>(
      '${BiliEndpoints.apiHost}$path',
      queryParameters: params.isEmpty ? null : params,
    );
    return _decode(res, what, BiliFailures.requireOkList);
  }

  /// WBI GET：自动取 mixinKey → 加 `wts` → 过滤值 → 排序 → `w_rid`。
  Future<Map<String, dynamic>> _getWbiJson(
    String path,
    Map<String, String> params,
    String what,
  ) async {
    final key = await mixinKey();
    // 先过滤值，保证「发出的请求」与「被签名的内容」一致。
    final filtered = {
      for (final e in params.entries) e.key: BiliSign.filterValue(e.value),
    };
    final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final wRid = BiliSign.wrid(filtered, key, wts: wts);

    final query = <String, String>{...filtered, 'wts': '$wts', 'w_rid': wRid};
    final res = await _dio.get<dynamic>(
      '${BiliEndpoints.apiHost}$path',
      queryParameters: query,
    );
    return _decode(res, what, BiliFailures.requireOkMap);
  }

  T _decode<T>(
    Response<dynamic> res,
    String what,
    T Function(Object? body, String what) decode,
  ) {
    final body =
        res.data is String ? jsonDecode(res.data as String) : res.data;
    if (res.statusCode != null && res.statusCode! >= 400) {
      // HTTP 层错误（如 412 风控可能不带 JSON body）。
      throw BiliFailures.fromCode(
        res.statusCode == 412 ? -412 : -403,
        '$what：HTTP ${res.statusCode}',
      );
    }
    return decode(body, what);
  }

  void _absorbSetCookie(Response<dynamic> res) {
    final setCookies = res.headers.map['set-cookie'];
    if (setCookies == null) return;
    for (final sc in setCookies) {
      final first = sc.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      _cookies[first.substring(0, eq)] = first.substring(eq + 1);
    }
  }

  String _cookieHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  static int? _asInt(Object? v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);
}

/// 账号摘要（nav 登录态字段）。
class BiliAccount {
  const BiliAccount({required this.mid, required this.uname});

  final int mid;
  final String uname;

  @override
  String toString() => 'mid=$mid uname=$uname';
}

/// 搜索视频条目（一个视频 = 一首候选歌，默认 P1）。
class BiliVideoItem {
  const BiliVideoItem({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.titleRaw,
    required this.author,
    required this.mid,
    required this.coverUrl,
    required this.durationSec,
    this.play,
    this.pubdate,
    this.raw = const {},
  });

  final String bvid;
  final int aid;

  /// 剥壳后的标题（`<em class="keyword">` 已剥离 + 实体解码）。
  final String title;

  /// 原始标题（带高亮标签）——探针核对「必答项 #3」用。
  final String titleRaw;
  final String author;
  final int mid;
  final String coverUrl;
  final int durationSec;
  final int? play;
  final int? pubdate;

  /// 原始条目 JSON（探针核对「必答项 #2：搜索是否返回 cid」用）。
  final Map<String, dynamic> raw;

  static BiliVideoItem fromJson(Map<String, dynamic> j) => BiliVideoItem(
        bvid: j['bvid'] is String ? j['bvid'] as String : '',
        aid: j['aid'] is int ? j['aid'] as int : 0,
        title: biliStripHtml(j['title'] is String ? j['title'] as String : ''),
        titleRaw: j['title'] is String ? j['title'] as String : '',
        author: j['author'] is String ? j['author'] as String : '',
        mid: j['mid'] is int ? j['mid'] as int : 0,
        coverUrl: _ensureHttps(j['pic'] is String ? j['pic'] as String : ''),
        durationSec: biliParseDurationSeconds(
          j['duration'] is String ? j['duration'] as String : '',
        ),
        play: j['play'] is int ? j['play'] as int : null,
        pubdate: j['pubdate'] is int ? j['pubdate'] as int : null,
        raw: j,
      );

  @override
  String toString() =>
      'bvid=$bvid title="$title" author=$author '
      'duration=${_fmtDuration(durationSec)} play=$play';
}

class BiliVideoPage {
  const BiliVideoPage({
    required this.items,
    required this.numResults,
    required this.numPages,
    required this.page,
  });

  final List<BiliVideoItem> items;
  final int numResults;
  final int numPages;
  final int page;
}

/// 分 P（cid 才是可听的原子单位，方案 §2）。
class BiliPage {
  const BiliPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.durationSec,
  });

  final int cid;
  final int page;
  final String part;
  final int durationSec;

  static BiliPage fromJson(Map<String, dynamic> j) => BiliPage(
        cid: j['cid'] is int ? j['cid'] as int : 0,
        page: j['page'] is int ? j['page'] as int : 0,
        part: j['part'] is String ? j['part'] as String : '',
        durationSec: j['duration'] is int ? j['duration'] as int : 0,
      );

  @override
  String toString() => 'P$page cid=$cid part="$part" dur=${durationSec}s';
}

/// DASH 音轨（普通 / 杜比 / Hi-Res 三处同构）。
class BiliAudioTrack {
  const BiliAudioTrack({
    required this.id,
    required this.qualityTag,
    required this.bandwidth,
    required this.mimeType,
    required this.codecs,
    required this.baseUrl,
    required this.backupUrls,
  });

  final int id;

  /// `null` = 普通轨；`dolby` / `hires` 见 `dash.dolby.audio` / `dash.flac.audio`。
  /// B1 必答项 #4 要记录的就是这个字段的实际取值集合。
  final String? qualityTag;
  final int bandwidth;
  final String mimeType;
  final String codecs;
  final String baseUrl;
  final List<String> backupUrls;

  static BiliAudioTrack fromJson(Map<String, dynamic> j) => BiliAudioTrack(
        id: j['id'] is int ? j['id'] as int : 0,
        qualityTag: j['qualityTag'] is String ? j['qualityTag'] as String : null,
        bandwidth: j['bandwidth'] is int ? j['bandwidth'] as int : 0,
        mimeType: j['mimeType'] is String ? j['mimeType'] as String : '',
        codecs: j['codecs'] is String ? j['codecs'] as String : '',
        baseUrl: _firstString(j, const ['baseUrl', 'base_url']),
        backupUrls: _firstStringList(j, const ['backupUrl', 'backup_url']),
      );

  @override
  String toString() =>
      'id=$id tag=${qualityTag ?? '-'} ${(bandwidth / 1024).round()}kb/s '
      '$mimeType/$codecs';
}

/// 取流结果（B1 探针视角：三组音轨 + durl 计数 + 原始 data 兜底）。
class BiliPlayInfo {
  const BiliPlayInfo({
    required this.audio,
    required this.dolby,
    required this.flac,
    required this.durlCount,
    required this.durlUrls,
    required this.raw,
  });

  final List<BiliAudioTrack> audio;
  final List<BiliAudioTrack> dolby;
  final List<BiliAudioTrack> flac;

  /// `durl`（MP4 整段）条数；>0 说明该视频只有渐进流（或 DASH 为空）。
  final int durlCount;

  /// `durl[].url` + 备份直链（`platform=html5` 兜底路径用，方案 §3.5）。
  final List<String> durlUrls;
  final Map<String, dynamic> raw;

  static BiliPlayInfo fromJson(Map<String, dynamic> data) {
    List<BiliAudioTrack> tracks(Object? node) {
      if (node is! Map<String, dynamic>) return const [];
      final audio = node['audio'];
      if (audio is! List) return const [];
      return audio
          .whereType<Map<String, dynamic>>()
          .map(BiliAudioTrack.fromJson)
          .toList();
    }

    final dash = data['dash'];
    final durl = data['durl'];
    final durlUrls = <String>[];
    if (durl is List) {
      for (final item in durl) {
        if (item is! Map<String, dynamic>) continue;
        final url = _firstString(item, const ['url']);
        if (url.isNotEmpty) durlUrls.add(url);
        durlUrls.addAll(_firstStringList(item, const ['backup_url', 'backupUrl']));
      }
    }
    return BiliPlayInfo(
      audio: tracks(dash),
      dolby: tracks(dash is Map<String, dynamic> ? dash['dolby'] : null),
      flac: tracks(dash is Map<String, dynamic> ? dash['flac'] : null),
      durlCount: durl is List ? durl.length : 0,
      durlUrls: durlUrls,
      raw: data,
    );
  }
}

// ── 文本小工具 ────────────────────────────────────────────────
// B1 探针直接用；B2 建 `bili_mappers.dart` 时迁走（方案 §7.1）。

final _tagPattern = RegExp(r'<[^>]+>');

/// 搜索结果 title 剥壳：去掉 `<em class="keyword">` 高亮标签并做 HTML
/// 实体解码（方案 §5.3 必答项 #3）。
String biliStripHtml(String html) => _decodeEntities(html.replaceAll(_tagPattern, '')).trim();

/// `"mm:ss"` / `"h:mm:ss"` / `"ss"` → 秒。空串 / 解析失败回 0。
int biliParseDurationSeconds(String raw) {
  if (raw.isEmpty) return 0;
  final parts = raw.split(':');
  if (parts.isEmpty || parts.length > 3) return 0;
  var seconds = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null) return 0;
    seconds = seconds * 60 + n;
  }
  return seconds;
}

String _fmtDuration(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAllMapped(
      RegExp(r'&#(x?[0-9a-fA-F]+);'),
      (m) {
        final body = m.group(1)!;
        final code = body.startsWith('x') || body.startsWith('X')
            ? int.tryParse(body.substring(1), radix: 16)
            : int.tryParse(body);
        return (code != null && code > 0 && code <= 0x10FFFF)
            ? String.fromCharCode(code)
            : m.group(0)!;
      },
    );

String _ensureHttps(String url) =>
    url.startsWith('//') ? 'https:$url' : url;

String _firstString(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is String && v.isNotEmpty) return v;
  }
  return '';
}

List<String> _firstStringList(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is String && v.isNotEmpty) return [v];
    if (v is List) {
      return v.whereType<String>().toList();
    }
  }
  return const [];
}
