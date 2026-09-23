// Probe cloudlist createCloudRequest protocol for /v7/get_all_list.
// Run: dart run tool/probe_cloudlist.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

import '../lib/core/api/kugo_crypto.dart';
import '../lib/core/api/kugo_sign.dart';

const token =
    '4a02e46fe7546861f9db29c410801e32fa2680b2a90cb991468660db572d54f7';
const userId = '2511133520';
const guid = '2b9c607bf85a801ca492f2d95bb4e67b';
const dfid = '0QeBfz1rwip04Bv9cF415aed';

String md5Hex(String s) => md5.convert(utf8.encode(s)).toString();

Uint8List aesCbcRaw(String plain, String key16, String iv16) {
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(
      encrypt_pkg.Key.fromUtf8(key16),
      mode: encrypt_pkg.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );
  final encrypted = encrypter.encrypt(
    plain,
    iv: encrypt_pkg.IV.fromUtf8(iv16),
  );
  return Uint8List.fromList(encrypted.bytes);
}

Future<void> main() async {
  final mid = KugoSign.calculateMid(guid);
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c > 0,
    ),
  );

  const litePem = KugoCrypto.liteRsaPem;
  const defaultPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB
-----END PUBLIC KEY-----''';

  Future<void> hit(
    String label, {
    required int appid,
    required int clientver,
    required String appkey,
    required String pem,
    bool uidAsString = true,
  }) async {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final aesSession = KugoCrypto.randomAlnum(6, lower: true);
    final digest = md5Hex(aesSession);
    final aesKey = digest.substring(0, 16);
    final aesIv = digest.substring(16, 32);
    final key = md5Hex('$appid$appkey$clientver$clienttime').toLowerCase();
    final portraitPlain = jsonEncode({
      'aes': aesSession,
      'uid': uidAsString ? userId : int.parse(userId),
      'token': token,
    });
    final p = KugoCrypto.rsaEncryptPkcs1(portraitPlain, pem: pem).toUpperCase();
    final dataMap = <String, dynamic>{
      'userid': uidAsString ? userId : int.parse(userId),
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 30,
    };
    final bodyJson = jsonEncode(dataMap);
    final cipherBytes = aesCbcRaw(bodyJson, aesKey, aesIv);
    final query = <String, dynamic>{
      'appid': appid,
      'clientver': clientver,
      'mid': mid,
      'clienttime': clienttime,
      'key': key,
      'dfid': dfid,
      'p': p,
    };
    final headers = <String, dynamic>{
      'Content-Type': 'application/json;charset=utf-8',
      'x-router': 'cloudlist.service.kugou.com',
      'dfid': dfid,
      'clienttime': '$clienttime',
      'mid': mid,
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      'User-Agent': KugoSign.userAgent,
      'Cookie': [
        'token=$token',
        'userid=$userId',
        'dfid=$dfid',
        'KUGOU_API_MID=$mid',
        'KUGOU_API_GUID=$guid',
        'KUGOU_API_DEV=kugoFlutter',
      ].join(';'),
    };
    try {
      final res = await dio.post<List<int>>(
        'https://gateway.kugou.com/v7/get_all_list',
        queryParameters: query,
        data: cipherBytes,
        options: Options(headers: headers),
      );
      final bytes = Uint8List.fromList(res.data ?? const []);
      String aesText = '';
      var aesOk = false;
      try {
        final encrypter = encrypt_pkg.Encrypter(
          encrypt_pkg.AES(
            encrypt_pkg.Key.fromUtf8(aesKey),
            mode: encrypt_pkg.AESMode.cbc,
            padding: 'PKCS7',
          ),
        );
        aesText = encrypter.decrypt(
          encrypt_pkg.Encrypted(bytes),
          iv: encrypt_pkg.IV.fromUtf8(aesIv),
        );
        aesOk = true;
      } catch (e) {
        aesText = 'AES_FAIL $e';
      }
      final rawText = utf8.decode(bytes, allowMalformed: true);
      stdout.writeln('[$label] HTTP ${res.statusCode} aesOk=$aesOk');
      stdout.writeln('  aes: ${aesText.substring(0, aesText.length.clamp(0, 300))}');
      stdout.writeln('  raw: ${rawText.substring(0, rawText.length.clamp(0, 300))}');
    } catch (e) {
      stdout.writeln('[$label] ERR $e');
    }
  }

  await hit(
    'lite_uid_str',
    appid: 3116,
    clientver: 11440,
    appkey: 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA',
    pem: litePem,
    uidAsString: true,
  );
  await hit(
    'lite_uid_num',
    appid: 3116,
    clientver: 11440,
    appkey: 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA',
    pem: litePem,
    uidAsString: false,
  );
  await hit(
    'default_uid_str',
    appid: 1005,
    clientver: 20489,
    appkey: 'OIlwieks28dk2k092lksi2UIkp',
    pem: defaultPem,
    uidAsString: true,
  );
  await hit(
    'default_uid_num',
    appid: 1005,
    clientver: 20489,
    appkey: 'OIlwieks28dk2k092lksi2UIkp',
    pem: defaultPem,
    uidAsString: false,
  );

  exit(0);
}
