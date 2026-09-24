import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 网易云 weapi / eapi / linux 加密（对齐 NeriPlayer `NeteaseCrypto`）。
///
/// 常量为协议事实型，**勿改**。RSA 使用与官方一致的**无填充** modPow。
abstract final class NeteaseCrypto {
  static const String base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static const String presetKey = '0CoJUm6Qyw8W8jud';
  static const String iv = '0102030405060708';
  static const String linuxKey = 'rFgB&h#%2?^eDg:Q';
  static const String eapiKey = 'e82ckenh8dichen8';
  static const String eapiFormat = '%s-36cd479b6b5-%s-36cd479b6b5-%s';
  static const String eapiSalt = 'nobody%suse%smd5forencrypt';

  /// X.509 SPKI RSA 公钥（与官方客户端一致）。
  static const String publicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFb
t7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZ
MldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB
-----END PUBLIC KEY-----
''';

  static final Random _secureRandom = Random.secure();

  /// 可注入随机源（单测用）。
  static Random? debugRandom;

  static Random get _rng => debugRandom ?? _secureRandom;

  static String randomKey() {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(base62[_rng.nextInt(base62.length)]);
    }
    return sb.toString();
  }

  static String md5Hex(String data) =>
      md5.convert(utf8.encode(data)).toString();

  static String _aesEncrypt(
    String text,
    String key,
    String ivStr, {
    required bool cbc,
    required String format,
  }) {
    final keyBytes = Uint8List.fromList(utf8.encode(key));
    final plain = Uint8List.fromList(utf8.encode(text));
    final Uint8List out;
    if (cbc) {
      final iv = Uint8List.fromList(utf8.encode(ivStr));
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
      cipher.init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), iv),
          null,
        ),
      );
      out = cipher.process(plain);
    } else {
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), AESEngine());
      cipher.init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          KeyParameter(keyBytes),
          null,
        ),
      );
      out = cipher.process(plain);
    }
    return switch (format.toLowerCase()) {
      'base64' => base64.encode(out),
      'hex' => _toHex(out),
      'hexupper' => _toHex(out).toUpperCase(),
      _ => throw ArgumentError('Unknown AES output format: $format'),
    };
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// RSA 无填充（text 为 16 位倒序密钥）。
  static String rsaEncrypt(String text) {
    final key = _parseRsaPublicKey(publicKeyPem);
    final message = _bytesToBigInt(utf8.encode(text));
    final result = message.modPow(key.exponent, key.modulus);
    final keySize = (key.modulus.bitLength + 7) >> 3;
    var bytes = _bigIntToBytes(result);
    if (bytes.length > keySize) {
      bytes = bytes.sublist(bytes.length - keySize);
    } else if (bytes.length < keySize) {
      final padded = Uint8List(keySize);
      padded.setRange(keySize - bytes.length, keySize, bytes);
      bytes = padded;
    }
    return _toHex(bytes);
  }

  /// weapi：双 AES-CBC + RSA → `params` / `encSecKey`。
  static Map<String, String> weApiEncrypt(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    final secretKey = randomKey();
    final enc1 = _aesEncrypt(json, presetKey, iv, cbc: true, format: 'base64');
    final params =
        _aesEncrypt(enc1, secretKey, iv, cbc: true, format: 'base64');
    final encSecKey = rsaEncrypt(secretKey.split('').reversed.join());
    return {'params': params, 'encSecKey': encSecKey};
  }

  /// eapi：MD5 盐拼接 + AES-ECB → 大写 hex `params`。
  static Map<String, String> eApiEncrypt(
    String urlPath,
    Map<String, dynamic> payload,
  ) {
    final data = jsonEncode(payload);
    final apiPath = urlPath.replaceFirst('/eapi', '/api');
    final digest = md5Hex(eapiSalt.format([apiPath, data]));
    final message = eapiFormat.format([apiPath, data, digest]);
    final cipher =
        _aesEncrypt(message, eapiKey, '', cbc: false, format: 'hexupper');
    return {'params': cipher};
  }

  /// linuxapi：AES-ECB hex `eparams`。
  static Map<String, String> linuxApiEncrypt(Map<String, dynamic> payload) {
    final cipher = _aesEncrypt(
      jsonEncode(payload),
      linuxKey,
      '',
      cbc: false,
      format: 'hex',
    );
    return {'eparams': cipher};
  }

  /// 设备匿名串（weapi 部分接口用）。
  static String anonymous(String deviceId) {
    const xorKey = '3go8&\$8*3*3h0k(2)2';
    final bytes = utf8.encode(deviceId);
    final xored = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      xored[i] = (bytes[i] ^ xorKey.codeUnitAt(i % xorKey.length)) & 0xff;
    }
    final digest = md5Hex(String.fromCharCodes(xored));
    final digestBytes = Uint8List.fromList(
      [for (var i = 0; i < digest.length; i += 2) int.parse(digest.substring(i, i + 2), radix: 16)],
    );
    final encoded = base64Url.encode(digestBytes);
    return base64Url.encode(utf8.encode('$deviceId $encoded'));
  }
}

class _RsaPublic {
  const _RsaPublic(this.modulus, this.exponent);
  final BigInt modulus;
  final BigInt exponent;
}

/// 测试用：暴露公钥解析结果。
(BigInt, BigInt) debugParseRsa() {
  final k = _parseRsaPublicKey(NeteaseCrypto.publicKeyPem);
  return (k.modulus, k.exponent);
}

/// 从 X.509 SubjectPublicKeyInfo 解析 RSA 公钥。
_RsaPublic _parseRsaPublicKey(String pem) {
  final cleaned = pem
      .replaceAll('-----BEGIN PUBLIC KEY-----', '')
      .replaceAll('-----END PUBLIC KEY-----', '')
      .replaceAll(RegExp(r'\s'), '');
  final der = base64.decode(cleaned);
  // SPKI: SEQUENCE { AlgorithmIdentifier, BIT STRING { SEQUENCE { n, e } } }
  // 找 INTEGER n（长度 128）与 INTEGER e。
  var offset = 0;
  BigInt? modulus;
  BigInt? exponent;
  while (offset < der.length) {
    if (der[offset] != 0x02) {
      offset++;
      continue;
    }
    offset++;
    if (offset >= der.length) break;
    var len = der[offset];
    offset++;
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | der[offset];
        offset++;
      }
    }
    if (offset + len > der.length) break;
    final value = Uint8List.sublistView(der, offset, offset + len);
    offset += len;
    if (value.length >= 128 && modulus == null) {
      modulus = _bytesToBigInt(value);
    } else if (value.length <= 4 && exponent == null) {
      exponent = _bytesToBigInt(value);
    }
  }
  if (modulus == null || exponent == null) {
    throw const FormatException('RSA public key parse failed');
  }
  return _RsaPublic(modulus, exponent);
}

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b & 0xff);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value) {
  if (value == BigInt.zero) return Uint8List(1);
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

extension on String {
  String format(List<String> args) {
    var i = 0;
    return replaceAllMapped('%s', (_) => args[i++]);
  }
}
