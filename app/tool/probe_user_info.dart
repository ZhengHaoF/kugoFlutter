// Probe user_info + get_all_list after checking token validity.
// Run: dart run tool/probe_user_info.dart
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

  // --- user_info (relation.user.kugou.com) ---
  {
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
    try {
      final res = await dio.post<dynamic>(
        'http://relation.user.kugou.com/v1/get_my_userinfo',
        data: jsonEncode(dataMap),
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'Host': 'relation.user.kugou.com',
            'Cookie': cookie,
          },
        ),
      );
      stdout.writeln('[user_info] ${res.data}');
    } catch (e) {
      stdout.writeln('[user_info] ERR $e');
    }
  }

  // --- get_all_list with signature that matches JS sort of key=value strings ---
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
    final bodyJson = jsonEncode(bodyObj);
    final params = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': 3116,
      'clientver': 11440,
      'clienttime': clienttime,
      'plat': 1,
      'userid': int.parse(userId),
      'token': token,
    };
    // Web-style sort of "key=value" strings (not keys) — just in case
    final entries = params.entries.map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    final paramsString = entries.join();
    final sigWebSort = KugoSign.md5Hex(
      'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA$paramsString$bodyJson' 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA',
    );
    final q = Map<String, dynamic>.from(params)..['signature'] = sigWebSort;
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com/v7/get_all_list',
      queryParameters: q,
      data: bodyJson,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'mid': mid,
          'clienttime': '$clienttime',
          'x-router': 'cloudlist.service.kugou.com',
          'Cookie': cookie,
          'kg-rc': '1',
          'kg-thash': '5d816a0',
          'kg-rec': '1',
          'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        },
      ),
    );
    stdout.writeln('[get_all_list_web_sort] ${res.data}');
  }

  // --- get_all_list without extra kg headers ---
  {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bodyObj = {
      'userid': int.parse(userId),
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 30,
    };
    final bodyJson = jsonEncode(bodyObj);
    final q = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': 3116,
      'clientver': 11440,
      'clienttime': clienttime,
      'plat': 1,
      'userid': int.parse(userId),
      'token': token,
    };
    q['signature'] = KugoSign.signatureAndroidParams(q, data: bodyJson);
    final res = await dio.post<dynamic>(
      'https://gateway.kugou.com/v7/get_all_list',
      queryParameters: q,
      data: bodyJson,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'mid': mid,
          'clienttime': '$clienttime',
          'x-router': 'cloudlist.service.kugou.com',
          'Cookie': cookie,
        },
      ),
    );
    stdout.writeln('[get_all_list_no_kg] ${res.data}');
  }

  exit(0);
}
