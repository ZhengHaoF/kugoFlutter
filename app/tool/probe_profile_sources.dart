// Probe relation get_my_userinfo vs usercenter get_my_info vs get_union_vip.
// Run: dart run tool/probe_profile_sources.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../lib/core/api/kugo_crypto.dart';
import '../lib/core/api/kugo_sign.dart';

const token =
    '4a02e46fe7546861f9db29c410801e32141fb1a380691618c35ec8e9d7aa6a44';
const userId = '2511133520';
const guid = '0c2cce11844dcf0a99f2b16a9b4e2766';
const dfid = '2ToTpi4Ik7qM14tvGJ17uxvN';

void dump(String tag, Object? raw) {
  stdout.writeln('\n===== $tag =====');
  final text = raw?.toString() ?? '';
  if (text.isEmpty) {
    stdout.writeln('(empty)');
    return;
  }
  try {
    final decoded = jsonDecode(text);
    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert(decoded));
  } catch (_) {
    stdout.writeln(text);
  }
}

Map<String, dynamic> flattenLeaves(Map<String, dynamic> json) {
  final out = <String, dynamic>{};
  void walk(Object? node, String path) {
    if (node is Map) {
      for (final e in node.entries) {
        walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
      }
    } else if (node is List) {
      out[path] = 'List(${node.length})';
      if (node.isNotEmpty) walk(node.first, '$path[0]');
    } else if (node != null) {
      out[path] = node;
    }
  }

  walk(json, '');
  return out;
}

void summarize(String tag, Object? raw) {
  stdout.writeln('\n----- $tag keys of interest -----');
  try {
    final decoded = jsonDecode(raw?.toString() ?? '');
    if (decoded is! Map) {
      stdout.writeln('not a map');
      return;
    }
    final leaves = flattenLeaves(Map<String, dynamic>.from(decoded));
    const wanted = [
      'nickname', 'username', 'userid', 'pic', 'userpic', 'gender', 'sex',
      'descri', 'signature', 'province', 'city', 'loc', 'follows', 'fans',
      'hvisitors', 'rtime', 'd_sec', 'duration', 'p_grade', 'p_current_point',
      'p_next_grade', 'p_next_grade_point', 'busi_vip', 'is_vip', 'product_type',
      'vip_begin_time', 'vip_end_time', 'vip_type',
    ];
    for (final k in leaves.keys) {
      final lower = k.toLowerCase();
      if (wanted.any(lower.endsWith) ||
          lower.contains('extend') ||
          lower.contains('detail') ||
          lower.contains('vip') ||
          lower.contains('grade') ||
          lower.contains('follow') ||
          lower.contains('fan') ||
          lower.contains('visit') ||
          lower.contains('listen') ||
          lower.contains('rtime') ||
          lower.contains('gender')) {
        stdout.writeln('$k = ${leaves[k]}');
      }
    }
    stdout.writeln('top-level keys: ${decoded.keys.toList()}');
  } catch (e) {
    stdout.writeln('summarize failed: $e');
  }
}

Future<void> main() async {
  final mid = KugoSign.calculateMid(guid);
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      validateStatus: (c) => c != null && c > 0,
    ),
  );
  final cookie = [
    'token=$token',
    'userid=$userId',
    'dfid=$dfid',
    'KUGOU_API_MID=$mid',
    'KUGOU_API_GUID=$guid',
    'KUGOU_API_DEV=kugoFlutter',
  ].join(';');
  final auth = {
    'User-Agent': KugoSign.userAgent,
    'Content-Type': 'application/json',
    'dfid': dfid,
    'mid': mid,
    'Cookie': cookie,
    'Authorization': cookie,
  };

  // 1) relation get_my_userinfo
  try {
    final clienttime = DateTime.now().millisecondsSinceEpoch;
    final p = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'clienttime': clienttime, 'token': token}),
    ).toUpperCase();
    final dataMap = {
      'p': p,
      'appid': int.parse(KugoSign.appId),
      'mid': mid,
      'clientver': int.parse(KugoSign.clientVer),
      'source': 0,
      'clienttime': clienttime,
      'uuid': '-',
      'userid': int.parse(userId),
      'key': KugoSign.signParamsKey('$clienttime'),
    };
    final bodyJson = jsonEncode(dataMap);
    final query = {
      ...KugoSign.defaultParams(dfid: dfid, mid: mid),
      'token': token,
      'userid': int.parse(userId),
    };
    query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
    final res = await dio.post<dynamic>(
      'http://relation.user.kugou.com/v1/get_my_userinfo',
      data: dataMap,
      queryParameters: query,
      options: Options(
        headers: {
          ...auth,
          'Host': 'relation.user.kugou.com',
        },
      ),
    );
    dump('relation get_my_userinfo', res.data);
    summarize('relation', res.data);
  } catch (e) {
    stdout.writeln('[relation] ERR $e');
  }

  // 2) usercenter get_my_info
  try {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pk = KugoCrypto.rsaEncryptRaw(
      jsonEncode({'token': token, 'clienttime': clienttime}),
    ).toUpperCase();
    final dataMap = {
      'visit_time': clienttime,
      'usertype': 1,
      'p': pk,
      'userid': int.parse(userId),
    };
    final bodyJson = jsonEncode(dataMap);
    final query = {
      ...KugoSign.defaultParams(dfid: dfid, mid: mid),
      'plat': 1,
      'token': token,
      'userid': int.parse(userId),
    };
    query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com/v3/get_my_info',
      data: dataMap,
      queryParameters: query,
      options: Options(
        headers: {
          ...auth,
          'x-router': 'usercenter.kugou.com',
        },
      ),
    );
    dump('usercenter get_my_info', res.data);
    summarize('usercenter', res.data);
  } catch (e) {
    stdout.writeln('[usercenter] ERR $e');
  }

  // 3) get_union_vip (Echo /user/vip/detail)
  try {
    final query = {
      ...KugoSign.defaultParams(dfid: dfid, mid: mid),
      'busi_type': 'concept',
      'token': token,
      'userid': int.parse(userId),
    };
    query['signature'] = KugoSign.signatureAndroidParams(query);
    final res = await dio.get<dynamic>(
      'https://kugouvip.kugou.com/v1/get_union_vip',
      queryParameters: query,
      options: Options(headers: auth),
    );
    dump('get_union_vip', res.data);
    summarize('union_vip', res.data);
  } catch (e) {
    stdout.writeln('[union_vip] ERR $e');
  }

  // 4) grade info query mode
  try {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final appKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
    final clientVer = '10597';
    final key = KugoSign.md5Hex(
      '${KugoSign.appId}$appKey$clientVer$clienttime',
    );
    final inner = jsonEncode({'clienttime': clienttime, 'userid': int.parse(userId)});
    final p = KugoCrypto.rsaEncryptRaw(inner).toUpperCase();
    final dataMap = {
      'mid': mid,
      'type': 1,
      'uuid': guid,
      'userid': int.parse(userId),
      'p': p,
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(clientVer),
      'clienttime': clienttime,
      'key': key,
    };
    final res = await dio.post<dynamic>(
      'http://userinfo.user.kugou.com/v2/get_grade_info',
      data: jsonEncode(dataMap),
      queryParameters: {'dfid': dfid},
      options: Options(
        headers: {
          ...auth,
          'Content-Type': 'text/plain; charset=ISO-8859-1',
          'User-Agent':
              'Android15-1070-$clientVer-201-0-get_user_grade_info-wifi',
          'KG-THash': KugoCrypto.randomAlnum(7, lower: true),
          'KG-Rec': '1',
          'KG-RC': '1',
        },
      ),
    );
    dump('get_grade_info', res.data);
    summarize('grade', res.data);
  } catch (e) {
    stdout.writeln('[grade] ERR $e');
  }

  exit(0);
}
