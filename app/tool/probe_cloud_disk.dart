// Probe Kugou music-cloud-disk (音乐云盘) protocol.
//
// Ports KuGouMusicApi modules:
//   user_cloud.js        → POST https://mcloudservice.kugou.com/v1/get_list
//   user_cloud_url.js    → GET  https://gateway.kugou.com/bsstrackercdngz/v2/query_musicclound_url
//   user_cloud_del.js    → POST https://mcloudservice.kugou.com/v1/del_files
//   user_cloud_match.js  → POST http://kmr.service.kugou.com/v2/album_audio/audio
//
// Run (from app/):
//   dart run tool/probe_cloud_disk.dart --suite list
//   dart run tool/probe_cloud_disk.dart --suite url --hash <HASH>
//   dart run tool/probe_cloud_disk.dart --suite match --hash <HASH>
//   dart run tool/probe_cloud_disk.dart --suite del --fileid <KV_ID> --confirm
//
// Credentials (CLI overrides env):
//   --token / KUGO_TOKEN, --userid / KUGO_USERID, --guid / KUGO_GUID, --dfid / KUGO_DFID
//
// Dumps full JSON field trees so api-notes.md can record the real payload shape.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:kugo/core/api/kugou/kugo_crypto.dart';
import 'package:kugo/core/api/kugou/kugo_sign.dart';

const _mcloudBase = 'https://mcloudservice.kugou.com';
const _gateway = 'https://gateway.kugou.com';
const _kmrBase = 'http://kmr.service.kugou.com';

class Creds {
  Creds({
    required this.token,
    required this.userId,
    required this.guid,
    required this.dfid,
  });

  final String token;
  final String userId;
  final String guid;
  final String dfid;

  String get mid => KugoSign.calculateMid(guid);

  bool get hasLogin => token.isNotEmpty && userId.isNotEmpty && userId != '0';

  String get cookie => [
        'token=$token',
        'userid=$userId',
        'dfid=$dfid',
        'KUGOU_API_MID=$mid',
        'KUGOU_API_GUID=$guid',
        'KUGOU_API_DEV=kugoFlutter',
      ].join(';');
}

void main(List<String> args) async {
  final opts = _parseArgs(args);
  final suite = opts['suite'] ?? 'all';
  final token = opts['token'] ?? Platform.environment['KUGO_TOKEN'] ?? '';
  final userId = opts['userid'] ?? Platform.environment['KUGO_USERID'] ?? '';
  final guid =
      opts['guid'] ?? Platform.environment['KUGO_GUID'] ?? KugoSign.randomAlnum(32);
  final dfid = opts['dfid'] ?? Platform.environment['KUGO_DFID'] ?? '-';
  final hash = (opts['hash'] ?? '').toLowerCase();
  final fileid = opts['fileid'] ?? '';
  final page = int.tryParse(opts['page'] ?? '1') ?? 1;
  final pageSize = int.tryParse(opts['pagesize'] ?? '30') ?? 30;
  final confirm = opts.containsKey('confirm');
  final dumpPath = opts['dump'];

  if (token.isEmpty || userId.isEmpty) {
    stderr.writeln(
      '缺少登录凭证。用法示例：\n'
      '  dart run tool/probe_cloud_disk.dart --suite list '
      '--token <T> --userid <U>\n'
      '或设置环境变量 KUGO_TOKEN / KUGO_USERID。'
    );
    exit(2);
  }

  final creds = Creds(
    token: token,
    userId: userId,
    guid: guid,
    dfid: dfid,
  );
  stdout.writeln('creds: userid=${creds.userId} guid=$guid dfid=$dfid '
      'mid=${creds.mid} login=${creds.hasLogin}');

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c > 0,
    ),
  );

  final dumps = <String, dynamic>{};
  final wantAll = suite == 'all';

  if (wantAll || suite == 'list') {
    dumps['list'] = await probeList(dio, creds, page: page, pageSize: pageSize);
  }
  if (wantAll || suite == 'url') {
    final h = hash.isNotEmpty ? hash : (_firstHashFromList(dumps['list']) ?? '');
    if (h.isEmpty) {
      stdout.writeln('[url] SKIP — 需要 --hash，或先跑 list');
    } else {
      dumps['url'] = await probeUrl(dio, creds, hash: h);
    }
  }
  if (wantAll || suite == 'match') {
    final h = hash.isNotEmpty ? hash : (_firstHashFromList(dumps['list']) ?? '');
    if (h.isEmpty) {
      stdout.writeln('[match] SKIP — 需要 --hash，或先跑 list');
    } else {
      dumps['match'] = await probeMatch(dio, creds, hash: h);
    }
  }
  if (wantAll || suite == 'del') {
    final id =
        fileid.isNotEmpty ? fileid : (_firstFileIdFromList(dumps['list']) ?? '');
    if (id.isEmpty) {
      stdout.writeln('[del] SKIP — 需要 --fileid，或先跑 list');
    } else if (!confirm) {
      stdout.writeln('[del] DRY-RUN fileid=$id （加 --confirm 才会真删）');
      dumps['del_dry_run'] = {'fileid': id, 'confirmed': false};
    } else {
      dumps['del'] = await probeDel(dio, creds, fileid: id);
    }
  }

  final encoded = const JsonEncoder.withIndent('  ').convert(dumps);
  if (dumpPath != null && dumpPath.isNotEmpty) {
    File(dumpPath).writeAsStringSync(encoded);
    stdout.writeln('\n--- dump written to $dumpPath ---');
  } else {
    stdout.writeln('\n--- dump ---');
    stdout.writeln(encoded);
  }
  exit(0);
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    if (key == 'confirm') {
      out[key] = '1';
      continue;
    }
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[key] = args[++i];
    } else {
      out[key] = '1';
    }
  }
  return out;
}

// ── shared mcloud request (AES body + RSA p) ──────────────────────────

({Uint8List body, Map<String, dynamic> query, String aesKey}) buildMcloudEnvelope({
  required Creds creds,
  required Map<String, dynamic> dataMap,
}) {
  final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
  // userid 在 p 里用字符串（user_cloud.js 从 cookie 读出来就是 string）
  final p = KugoCrypto
      .rsaEncryptPkcs1(
        jsonEncode({'aes': aes.key, 'uid': creds.userId, 'token': creds.token}),
      )
      .toUpperCase();
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final query = <String, dynamic>{
    'clienttime': clienttime,
    'mid': creds.mid,
    'key': KugoSign.signParamsKey('$clienttime'),
    'clientver': int.parse(KugoSign.clientVer),
    'appid': int.parse(KugoSign.appId),
    'p': p,
  };
  return (
    body: Uint8List.fromList(base64.decode(aes.str)),
    query: query,
    aesKey: aes.key,
  );
}

Map<String, dynamic> decodeMcloudBody(List<int>? bytes, String aesKey) {
  if (bytes == null || bytes.isEmpty) return {'_error': 'empty body'};
  final decrypted = KugoCrypto.playlistAesDecrypt(base64.encode(bytes), aesKey);
  final raw = utf8.decode(bytes, allowMalformed: true);
  for (final candidate in [decrypted, raw]) {
    if (candidate == null || candidate.isEmpty) continue;
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return {'_raw': raw.substring(0, raw.length.clamp(0, 500)), '_decrypted': decrypted};
}

Map<String, dynamic> describeShape(dynamic node, {String prefix = '', int depth = 0}) {
  if (depth > 4) return {'_truncated': true};
  if (node is Map) {
    final out = <String, dynamic>{};
    node.forEach((k, v) {
      out['$prefix$k'] = _typeLabel(v);
      if (v is Map || (v is List && v.isNotEmpty && v.first is Map)) {
        out.addAll(describeShape(v, prefix: '$prefix$k.', depth: depth + 1));
      }
    });
    return out;
  }
  if (node is List && node.isNotEmpty) {
    return describeShape(node.first, prefix: '$prefix[]', depth: depth + 1);
  }
  return {prefix: _typeLabel(node)};
}

String _typeLabel(dynamic v) {
  if (v == null) return 'null';
  if (v is Map) return 'object(${v.length})';
  if (v is List) return 'array(${v.length})';
  if (v is String) return 'string(${v.length})';
  return v.runtimeType.toString();
}

void printSection(String title, Map<String, dynamic> body) {
  stdout.writeln('\n=== $title ===');
  stdout.writeln('status=${body['status']} error_code=${body['error_code']} '
      'msg=${body['msg'] ?? body['error'] ?? ''}');
  final data = body['data'];
  if (data != null) {
    stdout.writeln('data keys: ${data is Map ? data.keys.toList() : data.runtimeType}');
  }
  stdout.writeln('shape:');
  final shape = describeShape(body);
  shape.forEach((k, v) => stdout.writeln('  $k: $v'));
  // Also dump one list item fully (first record) — this is what mapper work needs.
  final list = _pickList(body);
  if (list.isNotEmpty && list.first is Map) {
    stdout.writeln('first list item:');
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(list.first),
    );
  }
}

List<dynamic> _pickList(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is Map) {
    for (final key in ['list', 'info', 'songs', 'match_list']) {
      final v = data[key];
      if (v is List) return v;
      // `get_list` 的 list 是 JSON 字符串（空盘为 ""），不是原生数组。
      if (v is String) {
        final decoded = _decodeListString(v);
        if (decoded != null) return decoded;
      }
    }
  }
  for (final key in ['list', 'info', 'match_list']) {
    final v = body[key];
    if (v is List) return v;
    if (v is String) {
      final decoded = _decodeListString(v);
      if (decoded != null) return decoded;
    }
  }
  return const [];
}

List<dynamic>? _decodeListString(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (!text.startsWith('[')) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _firstHashFromList(dynamic listResult) {
  if (listResult is! Map) return null;
  final items = _pickList(Map<String, dynamic>.from(listResult));
  for (final item in items) {
    if (item is! Map) continue;
    final hash = (item['hash'] ?? item['audio_info']?['hash'] ?? '').toString();
    if (hash.isNotEmpty) return hash.toLowerCase();
  }
  return null;
}

String? _firstFileIdFromList(dynamic listResult) {
  if (listResult is! Map) return null;
  final items = _pickList(Map<String, dynamic>.from(listResult));
  for (final item in items) {
    if (item is! Map) continue;
    for (final key in ['kv_id', 'kvid', 'fileid', 'cloud_file_id']) {
      final v = item[key];
      final s = v?.toString() ?? '';
      if (s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s) && !RegExp(r'^0+$').hasMatch(s)) {
        return s;
      }
    }
  }
  return null;
}

// ── suites ────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> probeList(
  Dio dio,
  Creds creds, {
  int page = 1,
  int pageSize = 30,
}) async {
  // user_cloud.js dataMap — auth only in RSA `p` + Cookie.
  final env = buildMcloudEnvelope(
    creds: creds,
    dataMap: {
      'page': page,
      'pagesize': pageSize,
      'getkmr': 1,
    },
  );
  try {
    final res = await dio.post<List<int>>(
      '$_mcloudBase/v1/get_list',
      queryParameters: env.query,
      data: env.body,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'Cookie': creds.cookie,
          'KG-RC': '1',
          'KG-THash': '5d816a0',
          'KG-Rec': '1',
        },
      ),
    );
    final body = decodeMcloudBody(res.data, env.aesKey);
    printSection('list HTTP ${res.statusCode} page=$page/$pageSize', body);
    return body;
  } catch (e) {
    stdout.writeln('[list] ERR $e');
    return {'_error': '$e'};
  }
}

Future<Map<String, dynamic>> probeUrl(
  Dio dio,
  Creds creds, {
  required String hash,
}) async {
  // user_cloud_url.js — gateway + android signature, defaults injected.
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final h = hash.toLowerCase();
  const pid = 20026;
  final params = <String, dynamic>{
    'dfid': creds.dfid,
    'mid': creds.mid,
    'uuid': '-',
    'appid': int.parse(KugoSign.appId),
    'clientver': int.parse(KugoSign.clientVer),
    'clienttime': clienttime,
    if (creds.hasLogin) 'token': creds.token,
    if (creds.hasLogin) 'userid': int.tryParse(creds.userId) ?? creds.userId,
    // module dataMap
    'hash': h,
    'ssa_flag': 'is_fromtrack',
    'version': '20102',
    'ssl': 0,
    'album_audio_id': 0,
    'pid': pid,
    'audio_id': 0,
    'kv_id': 2,
    'key': KugoSign.signCloudKey(h, pid),
    'bucket': 'musicclound',
    'name': '',
    'with_res_tag': 0,
  };
  params['signature'] = KugoSign.signatureAndroidParams(params);

  try {
    final res = await dio.get<dynamic>(
      '$_gateway/bsstrackercdngz/v2/query_musicclound_url',
      queryParameters: params,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'dfid': creds.dfid,
          'clienttime': '$clienttime',
          'mid': creds.mid,
          'kg-rc': '1',
          'kg-thash': '5d816a0',
          'kg-rec': '1',
          'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
          'Cookie': creds.cookie,
        },
        responseType: ResponseType.plain,
      ),
    );
    final raw = res.data?.toString() ?? '';
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      body = {'_raw': raw.substring(0, raw.length.clamp(0, 500))};
    }
    printSection('url HTTP ${res.statusCode} hash=$h', body);
    return body;
  } catch (e) {
    stdout.writeln('[url] ERR $e');
    return {'_error': '$e'};
  }
}

Future<Map<String, dynamic>> probeMatch(
  Dio dio,
  Creds creds, {
  required String hash,
}) async {
  // user_cloud_match.js — kmr.service album_audio lookup by file-md5 / hash_std.
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final dataMap = <String, dynamic>{
    'appid': int.parse(KugoSign.appId),
    'clienttime': clienttime,
    'clientver': int.parse(KugoSign.clientVer),
    'data': [
      {'hash': hash.toLowerCase()},
    ],
    'dfid': creds.dfid,
    'key': KugoSign.signParamsKey('$clienttime'),
    'mid': creds.mid,
    'show_privilege': 0,
    'show_author_alias': 0,
    'show_rel_album_audio_info': 0,
    'show_remarks': 0,
  };

  try {
    final res = await dio.post<dynamic>(
      '$_kmrBase/v2/album_audio/audio',
      data: jsonEncode(dataMap),
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'x-router': 'kmr.service.kugou.com',
          'Cookie': creds.cookie,
        },
        responseType: ResponseType.plain,
      ),
    );
    final raw = res.data?.toString() ?? '';
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      body = {'_raw': raw.substring(0, raw.length.clamp(0, 500))};
    }
    printSection('match HTTP ${res.statusCode} hash=$hash', body);
    return body;
  } catch (e) {
    stdout.writeln('[match] ERR $e');
    return {'_error': '$e'};
  }
}

Future<Map<String, dynamic>> probeDel(
  Dio dio,
  Creds creds, {
  required String fileid,
  String albumAudioId = '0',
}) async {
  // user_cloud_del.js dataMap.
  final env = buildMcloudEnvelope(
    creds: creds,
    dataMap: {
      'data': [
        {
          'kv_id': int.tryParse(fileid) ?? fileid,
          'album_audio_id': int.tryParse(albumAudioId) ?? 0,
        },
      ],
    },
  );
  try {
    final res = await dio.post<List<int>>(
      '$_mcloudBase/v1/del_files',
      queryParameters: env.query,
      data: env.body,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'Cookie': creds.cookie,
          'KG-RC': '1',
          'KG-THash': '5d816a0',
          'KG-Rec': '1',
        },
      ),
    );
    final body = decodeMcloudBody(res.data, env.aesKey);
    printSection('del HTTP ${res.statusCode} fileid=$fileid', body);
    return body;
  } catch (e) {
    stdout.writeln('[del] ERR $e');
    return {'_error': '$e'};
  }
}


