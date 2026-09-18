import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/kugo_crypto.dart';
import '../../core/api/kugo_sign.dart';

/// Device identity returned by KuGou `POST /risk/v2/r_register_dev`.
class DeviceRegistration {
  const DeviceRegistration({
    required this.dfid,
    this.mid = '',
    this.guid = '',
    this.uuid = '',
    this.serverDev = '',
    this.mac = '',
  });

  final String dfid;
  final String mid;
  final String guid;
  final String uuid;
  final String serverDev;
  final String mac;
}

/// Port of KuGouMusicApi `module/register_dev.js`.
///
/// Risk-controlled endpoints (comments, some playlist APIs) reject an unknown
/// `dfid` with `err_code=20028` + a `ssa-code` response header. Registering a
/// real device once is what EchoMusic does at startup; the official anonymous
/// value `-` is used as a fallback (see [DeviceIdentity]).
class DeviceRepository {
  DeviceRepository({Dio? dio}) : _dio = dio ?? _createDio();

  static const _baseUrl = 'https://userservice.kugou.com';
  static const _path = '/risk/v2/r_register_dev';

  /// Official anonymous device id; accepted by the risk-controlled endpoints.
  static const anonymousDfid = '-';

  final Dio _dio;
  String lastError = '';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.bytes,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  /// Registers this install and returns the server-issued device identity.
  /// Returns null on any failure; [lastError] then explains why.
  Future<DeviceRegistration?> register({
    required String mid,
    required String guid,
  }) async {
    lastError = '';
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const dfid = anonymousDfid;

    // register_dev.js dataMap — values mirror a Redmi/Xiaomi handset.
    final dataMap = <String, dynamic>{
      'availableRamSize': 4983533568,
      'availableRomSize': 48114719,
      'availableSDSize': 48114717,
      'basebandVer': '',
      'batteryLevel': 100,
      'batteryStatus': 3,
      'brand': 'Redmi',
      'buildSerial': 'unknown',
      'device': 'marble',
      'imei': guid,
      'imsi': '',
      'manufacturer': 'Xiaomi',
      'uuid': guid,
      'accelerometer': false,
      'accelerometerValue': '',
      'gravity': false,
      'gravityValue': '',
      'gyroscope': false,
      'gyroscopeValue': '',
      'light': false,
      'lightValue': '',
      'magnetic': false,
      'magneticValue': '',
      'orientation': false,
      'orientationValue': '',
      'pressure': false,
      'pressureValue': '',
      'step_counter': false,
      'step_counterValue': '',
      'temperature': false,
      'temperatureValue': '',
    };

    final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
    final p = KugoCrypto.rsaEncryptPkcs1(
      jsonEncode({'aes': aes.key, 'uid': 0, 'token': ''}),
    );

    final params = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      'part': 1,
      'platid': 1,
      'p': p,
    };
    // request.js signs the android way, and register_dev sends a raw string
    // body — that body is part of the signature.
    params['signature'] = KugoSign.signatureAndroidParams(params, data: aes.str);

    try {
      final res = await _dio.post<List<int>>(
        '$_baseUrl$_path',
        queryParameters: params,
        data: aes.str,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'dfid': dfid,
            'clienttime': '$clienttime',
            'mid': mid,
            'kg-rc': '1',
            'kg-thash': '5d816a0',
            'kg-rec': '1',
            'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
          },
        ),
      );

      final bytes = res.data ?? const <int>[];
      if (bytes.isEmpty) {
        lastError = '设备注册响应为空';
        return null;
      }

      // Response is AES(base64) encrypted with the key we generated; fall back
      // to plain JSON when the server answered in the clear.
      final raw = utf8.decode(bytes, allowMalformed: true);
      Map<String, dynamic>? body;
      final decrypted = KugoCrypto.playlistAesDecrypt(
        base64.encode(bytes),
        aes.key,
      );
      for (final candidate in [decrypted, raw]) {
        if (candidate == null || candidate.isEmpty) continue;
        try {
          final decoded = jsonDecode(candidate);
          if (decoded is Map) {
            body = Map<String, dynamic>.from(decoded);
            break;
          }
        } catch (_) {}
      }

      if (body == null) {
        lastError = '设备注册响应无法解析';
        return null;
      }
      if (body['status'] != 1 && body['status'] != '1') {
        lastError =
            '${body['msg'] ?? body['error'] ?? '设备注册失败'}（status=${body['status']}）';
        return null;
      }

      final data = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : const <String, dynamic>{};
      final newDfid = (data['dfid'] ?? '').toString().trim();
      if (newDfid.isEmpty) {
        lastError = '设备注册未返回 dfid';
        return null;
      }

      return DeviceRegistration(
        dfid: newDfid,
        mid: (data['mid'] ?? '').toString(),
        guid: (data['guid'] ?? '').toString(),
        uuid: (data['uuid'] ?? '').toString(),
        serverDev: (data['serverDev'] ?? '').toString(),
        mac: (data['mac'] ?? '').toString(),
      );
    } on DioException catch (e) {
      lastError = e.message ?? '设备注册网络错误';
      return null;
    } catch (e) {
      lastError = '设备注册异常：$e';
      return null;
    }
  }
}
