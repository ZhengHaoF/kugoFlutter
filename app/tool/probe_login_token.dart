// Try string-everything params + login_by_token refresh.
// Run: dart run tool/probe_login_token.dart
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

const liteKey = 'c24f74ca2820225badc01946dba4fdf7';
const liteIv = 'adc01946dba4fdf7';
const liteT2Key = 'fd14b35e3f81af3817a20ae7adae7020';
const liteT2Iv = '17a20ae7adae7020';
const liteT1Key = '5e4ef500e9597fe004bd09a46d8add98';
const liteT1Iv = '04bd09a46d8add98';

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

  // --- login_by_token ---
  final dateNow = DateTime.now().millisecondsSinceEpoch;
  final p3 = KugoCrypto.aesEncrypt(
    jsonEncode({'clienttime': dateNow ~/ 1000, 'token': token}),
    key: liteKey,
    iv: liteIv,
  ) as String;
  final encryptParams = KugoCrypto.aesEncrypt('{}') as Map;
  final encKey = encryptParams['key']! as String;
  final encStr = encryptParams['str']! as String;
  final pk = KugoCrypto.rsaEncryptRaw(
    jsonEncode({'clienttime_ms': dateNow, 'key': encKey}),
  );
  final t2 = KugoCrypto.aesEncrypt(
    '$guid|0f607264fc6318a92b9e13c65db7cd3c||kugoFlutter|$dateNow',
    key: liteT2Key,
    iv: liteT2Iv,
  ) as String;
  final t1 = KugoCrypto.aesEncrypt('|$dateNow', key: liteT1Key, iv: liteT1Iv)
      as String;

  final dataMap = {
    'dfid': dfid,
    'p3': p3,
    'plat': 1,
    't1': t1,
    't2': t2,
    't3': 'MCwwLDAsMCwwLDAsMCwwLDA=',
    'pk': pk.toUpperCase(),
    'params': encStr,
    'userid': userId,
    'clienttime_ms': dateNow,
    'dev': 'kugoFlutter',
  };
  final bodyJson = jsonEncode(dataMap);
  final query = <String, dynamic>{
    ...KugoSign.defaultParams(dfid: dfid, mid: mid),
  };
  query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);

  try {
    final res = await dio.post<dynamic>(
      'http://login.user.kugou.com/v5/login_by_token',
      queryParameters: query,
      data: bodyJson,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'mid': mid,
          'Cookie':
              'token=$token; userid=$userId; dfid=$dfid; KUGOU_API_MID=$mid; KUGOU_API_GUID=$guid; KUGOU_API_DEV=kugoFlutter',
        },
      ),
    );
    final raw = res.data?.toString() ?? '';
    stdout.writeln('[login_by_token] $raw');
    Map<String, dynamic>? body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    if (body != null && body['status'] == 1) {
      final data = Map<String, dynamic>.from(body['data'] as Map? ?? {});
      final secu = (data['secu_params'] ?? '').toString();
      if (secu.isNotEmpty) {
        final decoded = KugoCrypto.aesDecryptHex(secu, encKey);
        stdout.writeln('  secu_decoded: $decoded');
      }
      stdout.writeln('  new token: ${data['token']}');
      stdout.writeln('  t1: ${data['t1']}');
    }
  } catch (e) {
    stdout.writeln('[login_by_token] ERR $e');
  }

  // --- get_all_list all-string params ---
  {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bodyObj = {
      'userid': userId,
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 30,
    };
    final bodyJson2 = jsonEncode(bodyObj);
    final q = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': '3116',
      'clientver': '11440',
      'clienttime': '$clienttime',
      'plat': '1',
      'userid': userId,
      'token': token,
    };
    q['signature'] = KugoSign.signatureAndroidParams(q, data: bodyJson2);
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com/v7/get_all_list',
      queryParameters: q,
      data: bodyJson2,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'mid': mid,
          'clienttime': '$clienttime',
          'x-router': 'cloudlist.service.kugou.com',
        },
      ),
    );
    stdout.writeln('[all_string_params] ${res.data}');
  }

  exit(0);
}
