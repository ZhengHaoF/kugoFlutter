// Probe get_all_list with AES body (register_dev style) + more shapes.
// Run: dart run tool/probe_get_all_list_aes.dart
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

Future<void> hit(
  Dio dio,
  String label, {
  required String path,
  required Map<String, dynamic> queryBase,
  required Object body,
  Map<String, dynamic>? headerExtra,
  String router = 'cloudlist.service.kugou.com',
}) async {
  final mid = KugoSign.calculateMid(guid);
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final bodyJson = body is String ? body : jsonEncode(body);
  final query = <String, dynamic>{
    ...KugoSign.defaultParams(dfid: dfid, mid: mid),
    ...queryBase,
  };
  query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
  final cookie = [
    'token=$token',
    'userid=$userId',
    'dfid=$dfid',
    'KUGOU_API_MID=$mid',
    'KUGOU_API_GUID=$guid',
    'KUGOU_API_DEV=kugoFlutter',
  ].join(';');
  try {
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com$path',
      queryParameters: query,
      data: bodyJson,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': body is String ? 'text/plain' : 'application/json',
          'dfid': dfid,
          'mid': mid,
          'clienttime': '$clienttime',
          'x-router': router,
          'Cookie': cookie,
          if (headerExtra != null) ...headerExtra,
        },
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c > 0,
      ),
    );
    final raw = res.data?.toString() ?? '';
    stdout.writeln(
      '[$label] ${res.statusCode} ${raw.substring(0, raw.length.clamp(0, 350))}',
    );
  } catch (e) {
    stdout.writeln('[$label] ERR $e');
  }
}

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  final mid = KugoSign.calculateMid(guid);
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final uid = int.parse(userId);

  final dataMap = <String, dynamic>{
    'userid': uid,
    'token': token,
    'total_ver': 979,
    'type': 2,
    'page': 1,
    'pagesize': 50,
  };
  final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
  final p = KugoCrypto.rsaEncryptPkcs1(
    jsonEncode({'aes': aes.key, 'uid': uid, 'token': token}),
  );

  await hit(
    dio,
    'aes_raw_p_query',
    path: '/v7/get_all_list',
    queryBase: {
      'plat': 1,
      'userid': uid,
      'token': token,
      'part': 1,
      'platid': 1,
      'p': p,
    },
    body: aes.str,
    headerExtra: {
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
    },
  );

  await hit(
    dio,
    'aes_body_key',
    path: '/v7/get_all_list',
    queryBase: {'plat': 1, 'userid': uid, 'token': token},
    body: {'data': aes.str, 'key': aes.key, 'p': p},
  );

  for (final tv in [1, 2, 10, 100, 979, 2000, 11440]) {
    await hit(
      dio,
      'tv_$tv',
      path: '/v7/get_all_list',
      queryBase: {'plat': 1, 'userid': uid, 'token': token},
      body: {
        'userid': uid,
        'token': token,
        'total_ver': tv,
        'type': 2,
        'page': 1,
        'pagesize': 50,
      },
    );
  }

  exit(0);
}
