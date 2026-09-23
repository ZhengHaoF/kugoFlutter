// Probe get_all_list variants: plain / +p RSA / AES body.
// Run: dart run tool/probe_get_all_list.dart
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
const dev = 'kugoFlutter';

Future<void> hit(
  Dio dio,
  String label, {
  required String path,
  required String router,
  required Map<String, dynamic> body,
  Map<String, dynamic>? queryExtra,
  Map<String, dynamic>? headerExtra,
  bool signBody = true,
}) async {
  final mid = KugoSign.calculateMid(guid);
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final bodyJson = jsonEncode(body);
  final query = <String, dynamic>{
    ...KugoSign.defaultParams(dfid: dfid, mid: mid),
    'plat': 1,
    'userid': int.tryParse(userId) ?? userId,
    'token': token,
    if (queryExtra != null) ...queryExtra,
  };
  query['signature'] = KugoSign.signatureAndroidParams(
    query,
    data: signBody ? bodyJson : '',
  );
  final cookie = [
    'token=$token',
    'userid=$userId',
    'dfid=$dfid',
    'KUGOU_API_MID=$mid',
    'KUGOU_API_GUID=$guid',
    'KUGOU_API_DEV=$dev',
  ].join(';');
  final headers = <String, dynamic>{
    'User-Agent': KugoSign.userAgent,
    'Content-Type': 'application/json',
    'dfid': dfid,
    'mid': mid,
    'clienttime': '$clienttime',
    'x-router': router,
    'Cookie': cookie,
    if (headerExtra != null) ...headerExtra,
  };
  try {
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com$path',
      queryParameters: query,
      data: bodyJson,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c > 0,
      ),
    );
    final raw = res.data?.toString() ?? '';
    stdout.writeln('[$label] HTTP ${res.statusCode} ${raw.substring(0, raw.length.clamp(0, 400))}');
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
  final pPlain = jsonEncode({'clienttime': clienttime, 'token': token});
  final pRaw = KugoCrypto.rsaEncryptRaw(pPlain).toUpperCase();
  final pPkcs = KugoCrypto.rsaEncryptPkcs1(pPlain).toUpperCase();
  final aes = KugoCrypto.playlistAesEncrypt(
    jsonEncode({
      'userid': int.parse(userId),
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 50,
    }),
  );

  final baseBody = <String, dynamic>{
    'userid': int.parse(userId),
    'token': token,
    'total_ver': 979,
    'type': 2,
    'page': 1,
    'pagesize': 50,
  };

  await hit(dio, 'plain', path: '/v7/get_all_list', router: 'cloudlist.service.kugou.com', body: baseBody);
  await hit(
    dio,
    'with_p_raw',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {...baseBody, 'p': pRaw},
  );
  await hit(
    dio,
    'with_p_pkcs',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {...baseBody, 'p': pPkcs},
  );
  await hit(
    dio,
    'p_json_keyorder',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {
      ...baseBody,
      'p': KugoCrypto.rsaEncryptRaw(
        jsonEncode({'token': token, 'clienttime': clienttime}),
      ).toUpperCase(),
    },
  );
  // AES body as string with key in query
  await hit(
    dio,
    'aes_body',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {'data': aes.str, 'key': aes.key},
    queryExtra: {'key': aes.key},
  );
  // body is raw aes string
  await hit(
    dio,
    'aes_raw_string',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {'userid': int.parse(userId), 'token': token, 'total_ver': 979, 'type': 2, 'page': 1, 'pagesize': 50},
    headerExtra: {'x-router': 'cloudlist.service.kugou.com'},
  );

  // more body fields often seen
  await hit(
    dio,
    'rich_body',
    path: '/v7/get_all_list',
    router: 'cloudlist.service.kugou.com',
    body: {
      ...baseBody,
      'appid': 3116,
      'clientver': 11440,
      'clienttime': clienttime,
      'mid': mid,
      'guid': guid,
      'dfid': dfid,
      'p': pRaw,
    },
  );

  // type 0 / 1 / 2 without p
  for (final t in [0, 1, 2, 3]) {
    await hit(
      dio,
      'type_$t',
      path: '/v7/get_all_list',
      router: 'cloudlist.service.kugou.com',
      body: {...baseBody, 'type': t, 'total_ver': 979},
    );
  }

  exit(0);
}
