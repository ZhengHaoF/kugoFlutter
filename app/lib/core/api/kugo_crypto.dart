import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// AES/RSA helpers matching KuGouMusicApi `util/crypto.js`.
abstract final class KugoCrypto {
  /// Lite platform RSA public key (SPKI PEM).
  static const liteRsaPem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB
-----END PUBLIC KEY-----''';

  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String randomAlnum(int len, {bool lower = false}) {
    const pool = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final rnd = Random.secure();
    final s =
        List.generate(len, (_) => pool[rnd.nextInt(pool.length)]).join();
    return lower ? s.toLowerCase() : s;
  }

  /// AES-CBC + PKCS7, hex output.
  /// Without [key]/[iv]: random 16-char key, AES key=md5(tempKey)[0:32],
  /// iv=last 16 of that — returns `{str, key}`.
  static Object aesEncrypt(String data, {String? key, String? iv}) {
    String aesKey;
    String aesIv;
    String? tempKey;
    if (key != null && iv != null) {
      aesKey = key;
      aesIv = iv;
    } else {
      tempKey = randomAlnum(16, lower: true);
      aesKey = md5Hex(tempKey).substring(0, 32);
      aesIv = aesKey.substring(aesKey.length - 16);
    }
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(
        encrypt_pkg.Key.fromUtf8(aesKey),
        mode: encrypt_pkg.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    final encrypted = encrypter.encrypt(
      data,
      iv: encrypt_pkg.IV.fromUtf8(aesIv),
    );
    final hex = _bytesToHex(encrypted.bytes);
    if (tempKey == null) return hex;
    return {'str': hex, 'key': tempKey};
  }

  static String? aesDecryptHex(String hex, String keyOrTempKey, {String? iv}) {
    try {
      final aesKey = iv != null ? keyOrTempKey : md5Hex(keyOrTempKey).substring(0, 32);
      final aesIv = iv ?? aesKey.substring(aesKey.length - 16);
      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(
          encrypt_pkg.Key.fromUtf8(aesKey),
          mode: encrypt_pkg.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      final bytes = _hexToBytes(hex);
      final dec = encrypter.decrypt(
        encrypt_pkg.Encrypted(bytes),
        iv: encrypt_pkg.IV.fromUtf8(aesIv),
      );
      return dec;
    } catch (_) {
      return null;
    }
  }

  /// AES-CBC + PKCS7, **base64** output, random 6-char lowercase key.
  /// Matches KuGouMusicApi `playlistAesEncrypt`:
  /// key=md5(tempKey)[0:16], iv=md5(tempKey)[16:32].
  static ({String str, String key}) playlistAesEncrypt(String data) {
    final tempKey = randomAlnum(6, lower: true);
    final digest = md5Hex(tempKey);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(
        encrypt_pkg.Key.fromUtf8(digest.substring(0, 16)),
        mode: encrypt_pkg.AESMode.cbc,
        padding: 'PKCS7',
      ),
    );
    final encrypted = encrypter.encrypt(
      data,
      iv: encrypt_pkg.IV.fromUtf8(digest.substring(16, 32)),
    );
    return (str: base64.encode(encrypted.bytes), key: tempKey);
  }

  /// Reverse of [playlistAesEncrypt]. Returns null when key/body is invalid.
  static String? playlistAesDecrypt(String base64Body, String tempKey) {
    try {
      final digest = md5Hex(tempKey);
      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(
          encrypt_pkg.Key.fromUtf8(digest.substring(0, 16)),
          mode: encrypt_pkg.AESMode.cbc,
          padding: 'PKCS7',
        ),
      );
      return encrypter.decrypt(
        encrypt_pkg.Encrypted(base64.decode(base64Body)),
        iv: encrypt_pkg.IV.fromUtf8(digest.substring(16, 32)),
      );
    } catch (_) {
      return null;
    }
  }

  /// RSAES-PKCS1-V1_5, hex output — matches forge `rsaEncrypt2` in crypto.js.
  static String rsaEncryptPkcs1(String data, {String pem = liteRsaPem}) {
    final key = _parseRsaPem(pem);
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    final out = engine.process(Uint8List.fromList(utf8.encode(data)));
    return _bytesToHex(out);
  }

  /// Raw RSA (no PKCS padding) — matches forge `rsaRawEncrypt` in crypto.js.
  static String rsaEncryptRaw(String data, {String pem = liteRsaPem}) {
    final key = _parseRsaPem(pem);
    final n = key.modulus!;
    final keyLength = (n.bitLength + 7) ~/ 8;
    var buffer = Uint8List.fromList(utf8.encode(data));
    if (buffer.length > keyLength) {
      throw StateError('Data length exceeds RSA key size');
    }
    if (buffer.length < keyLength) {
      // forge zero-pads at the end
      final zeroPad = Uint8List(keyLength);
      zeroPad.setAll(0, buffer);
      buffer = zeroPad;
    }
    final m = BigInt.parse(_bytesToHex(buffer), radix: 16);
    final c = m.modPow(key.publicExponent!, n);
    return c.toRadixString(16).padLeft(keyLength * 2, '0');
  }

  static RSAPublicKey _parseRsaPem(String pem) {
    final stripped = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');
    final der = base64.decode(stripped);
    final parser = ASN1Parser(der);
    final seq = parser.nextObject() as ASN1Sequence;
    final bitString = seq.elements![1] as ASN1BitString;
    final inner = ASN1Parser(bitString.stringValues as Uint8List? ?? bitString.valueBytes!);
    // Some parsers nest differently; try valueBytes of bit string
    final keySeq = inner.nextObject() as ASN1Sequence;
    final n = (keySeq.elements![0] as ASN1Integer).integer;
    final e = (keySeq.elements![1] as ASN1Integer).integer;
    if (n == null || e == null) {
      throw StateError('Failed to parse RSA public key');
    }
    return RSAPublicKey(n, e);
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
