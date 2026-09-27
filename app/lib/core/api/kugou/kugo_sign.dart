import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Kugou client signature (concept/lite platform), ported from KuGouMusicApi.
abstract final class KugoSign {
  /// Concept app (lite).
  static const appId = '3116';
  static const clientVer = '11440';
  static const _saltKeyLite = '185672dd44712f60bb1736df5a377e82';
  static const _saltSigLite = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
  static const _saltSigWeb = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const srcAppId = 2919;
  static const userAgent =
      'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String randomAlnum(int len) {
    const pool = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final rnd = Random.secure();
    return List.generate(len, (_) => pool[rnd.nextInt(pool.length)]).join();
  }

  /// mid = decimal(BigInt(md5(guid))).
  static String calculateMid(String guid) {
    final digest = md5Hex(guid);
    return BigInt.parse('0x$digest').toString();
  }

  /// signKey for tracker /v5/url.
  static String signKey(
    String hash,
    String mid, {
    String userid = '0',
    String appId = appId,
  }) {
    return md5Hex('$hash$_saltKeyLite$appId$mid$userid');
  }

  /// Android/lite signature: md5(salt + sorted key=value + data + salt).
  static String signatureAndroidParams(
    Map<String, dynamic> params, {
    String data = '',
  }) {
    final keys = params.keys.toList()..sort();
    final paramsString = keys.map((k) {
      final v = params[k];
      final value = (v is Map || v is List) ? jsonEncode(v) : '$v';
      return '$k=$value';
    }).join();
    return md5Hex('$_saltSigLite$paramsString$data$_saltSigLite');
  }

  /// Web signature: md5(salt + sorted key=value + data + salt).
  static String signatureWebParams(
    Map<String, dynamic> params, {
    String data = '',
  }) {
    final keys = params.keys.toList()..sort();
    final paramsString = keys.map((k) {
      final v = params[k];
      final value = (v is Map || v is List) ? jsonEncode(v) : '$v';
      return '$k=$value';
    }).join();
    return md5Hex('$_saltSigWeb$paramsString$data$_saltSigWeb');
  }

  /// signParamsKey for login (lite).
  static String signParamsKey(String data) {
    return md5Hex('$appId$_saltSigLite$clientVer$data');
  }

  /// Default query params injected on every gateway request.
  static Map<String, dynamic> defaultParams({
    required String dfid,
    required String mid,
    String uuid = '-',
    int? appid,
    int? clientver,
  }) {
    return {
      'dfid': dfid,
      'mid': mid,
      'uuid': uuid,
      'appid': appid ?? int.parse(appId),
      'clientver': clientver ?? int.parse(clientVer),
      'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }
}
