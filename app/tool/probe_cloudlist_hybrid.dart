// Hybrid cloudlist protocol (playlist_del style) for /v7/get_all_list.
// Run: dart run tool/probe_cloudlist_hybrid.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../lib/core/api/kugo_crypto.dart';
import '../lib/core/api/kugo_sign.dart';

const token =
    '4a02e46fe7546861f9db29c410801e32fa2680b2a90cb991468660db572d54f7';
const userId = '2511133520';
const guid = '2b9c607bf85a801ca492f2d95bb4e67b';
const dfid = '0QeBfz1rwip04Bv9cF415aed';

Future<void> main() async {
  final mid = KugoSign.calculateMid(guid);
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final dataMap = <String, dynamic>{
    'userid': userId,
    'token': token,
    'total_ver': 979,
    'type': 2,
    'page': 1,
    'pagesize': 30,
  };
  final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
  final p = KugoCrypto
      .rsaEncryptPkcs1(jsonEncode({'aes': aes.key, 'uid': userId, 'token': token}))
      .toUpperCase();

  final query = <String, dynamic>{
    'dfid': dfid,
    'mid': mid,
    'uuid': '-',
    'appid': int.parse(KugoSign.appId),
    'clientver': int.parse(KugoSign.clientVer),
    'clienttime': clienttime,
    'plat': 1,
    'userid': int.parse(userId),
    'token': token,
    'key': KugoSign.signParamsKey('$clienttime'),
    'last_area': 'gztx',
    'last_time': clienttime,
    'p': p,
  };
  query['signature'] = KugoSign.signatureAndroidParams(query, data: aes.str);

  final dio = Dio(
    BaseOptions(
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c > 0,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<void> hit(String label, String path, Object body, {bool signBody = true}) async {
    final q = Map<String, dynamic>.from(query);
    if (!signBody) {
      q['signature'] = KugoSign.signatureAndroidParams(q, data: '');
    }
    final res = await dio.post<List<int>>(
      'https://gateway.kugou.com$path',
      queryParameters: q,
      data: body,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'mid': mid,
          'clienttime': '$clienttime',
          'x-router': 'cloudlist.service.kugou.com',
          'Cookie':
              'token=$token; userid=$userId; dfid=$dfid; KUGOU_API_MID=$mid; KUGOU_API_GUID=$guid; KUGOU_API_DEV=kugoFlutter',
          'kg-rc': '1',
          'kg-thash': '5d816a0',
          'kg-rec': '1',
          'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        },
      ),
    );
    final bytes = res.data ?? const <int>[];
    final raw = String.fromCharCodes(bytes);
    String? decrypted;
    try {
      decrypted = KugoCrypto.playlistAesDecrypt(
        base64.encode(bytes),
        aes.key,
      );
    } catch (e) {
      decrypted = 'DEC_FAIL $e';
    }
    stdout.writeln('[$label] ${res.statusCode}');
    stdout.writeln('  raw: ${raw.substring(0, raw.length.clamp(0, 250))}');
    stdout.writeln('  dec: ${decrypted?.substring(0, (decrypted?.length ?? 0).clamp(0, 400))}');
  }

  await hit('aes_b64', '/v7/get_all_list', aes.str);
  // also plain body but with key+p
  final plain = jsonEncode(dataMap);
  final query2 = Map<String, dynamic>.from(query)
    ..remove('key')
    ..remove('p')
    ..remove('last_area')
    ..remove('last_time');
  query2['signature'] = KugoSign.signatureAndroidParams(query2, data: plain);
  // reuse hit is bound to query; do inline
  final res2 = await dio.post<List<int>>(
    'https://gateway.kugou.com/v7/get_all_list',
    queryParameters: query2,
    data: plain,
    options: Options(
      headers: {
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': dfid,
        'mid': mid,
        'clienttime': '$clienttime',
        'x-router': 'cloudlist.service.kugou.com',
        'Cookie':
            'token=$token; userid=$userId; dfid=$dfid; KUGOU_API_MID=$mid; KUGOU_API_GUID=$guid; KUGOU_API_DEV=kugoFlutter',
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      },
    ),
  );
  stdout.writeln('[plain_again] ${String.fromCharCodes(res2.data ?? const [])}');

  // body as number userid + aes
  final dataMap2 = Map<String, dynamic>.from(dataMap)
    ..['userid'] = int.parse(userId);
  final aes2 = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap2));
  final p2 = KugoCrypto
      .rsaEncryptPkcs1(
        jsonEncode({'aes': aes2.key, 'uid': int.parse(userId), 'token': token}),
      )
      .toUpperCase();
  final q3 = <String, dynamic>{
    'dfid': dfid,
    'mid': mid,
    'uuid': '-',
    'appid': int.parse(KugoSign.appId),
    'clientver': int.parse(KugoSign.clientVer),
    'clienttime': clienttime,
    'plat': 1,
    'userid': int.parse(userId),
    'token': token,
    'key': KugoSign.signParamsKey('$clienttime'),
    'last_area': 'gztx',
    'last_time': clienttime,
    'p': p2,
  };
  q3['signature'] = KugoSign.signatureAndroidParams(q3, data: aes2.str);
  final res3 = await dio.post<List<int>>(
    'https://gateway.kugou.com/v7/get_all_list',
    queryParameters: q3,
    data: aes2.str,
    options: Options(
      headers: {
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': dfid,
        'mid': mid,
        'clienttime': '$clienttime',
        'x-router': 'cloudlist.service.kugou.com',
        'Cookie':
            'token=$token; userid=$userId; dfid=$dfid; KUGOU_API_MID=$mid; KUGOU_API_GUID=$guid; KUGOU_API_DEV=kugoFlutter',
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      },
    ),
  );
  final raw3 = String.fromCharCodes(res3.data ?? const []);
  stdout.writeln('[aes_uid_num] $raw3');
  stdout.writeln(
    '  dec: ${KugoCrypto.playlistAesDecrypt(base64.encode(res3.data ?? const []), aes2.key)}',
  );

  exit(0);
}
