import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/netease/netease_crypto.dart';

void main() {
  test('randomKey is 16-char base62', () {
    final key = NeteaseCrypto.randomKey();
    expect(key.length, 16);
    expect(RegExp(r'^[a-zA-Z0-9]+$').hasMatch(key), isTrue);
  });

  test('md5Hex matches known vector', () {
    expect(
      NeteaseCrypto.md5Hex(''),
      'd41d8cd98f00b204e9800998ecf8427e',
    );
  });

  test('weApiEncrypt returns params + 256-hex encSecKey', () {
    NeteaseCrypto.debugRandom = Random(42);
    final out = NeteaseCrypto.weApiEncrypt({
      's': '周杰伦',
      'type': 1,
      'limit': 5,
      'offset': 0,
      'total': true,
    });
    NeteaseCrypto.debugRandom = null;

    expect(out.keys, containsAll(['params', 'encSecKey']));
    expect(out['params']!.isNotEmpty, isTrue);
    // 1024-bit RSA → 128 bytes → 256 hex chars.
    expect(out['encSecKey']!.length, 256);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(out['encSecKey']!), isTrue);
  });

  test('weApiEncrypt is deterministic with seeded random', () {
    NeteaseCrypto.debugRandom = Random(7);
    final a = NeteaseCrypto.weApiEncrypt({'s': 'a', 'type': 1});
    NeteaseCrypto.debugRandom = Random(7);
    final b = NeteaseCrypto.weApiEncrypt({'s': 'a', 'type': 1});
    NeteaseCrypto.debugRandom = null;
    expect(a['params'], b['params']);
    expect(a['encSecKey'], b['encSecKey']);
  });

  test('eApiEncrypt builds uppercase hex params', () {
    final out = NeteaseCrypto.eApiEncrypt(
      '/eapi/song/lyric/v1',
      {'id': 186016, 'lv': 0},
    );
    final params = out['params']!;
    expect(params.isNotEmpty, isTrue);
    expect(params, params.toUpperCase());
    expect(RegExp(r'^[0-9A-F]+$').hasMatch(params), isTrue);
  });

  test('anonymous produces url-safe base64', () {
    final s = NeteaseCrypto.anonymous('device-id-123');
    // Java UrlEncoder 可能带 '=' padding；禁止 + /
    expect(s.contains('+'), isFalse);
    expect(s.contains('/'), isFalse);
    expect(RegExp(r'^[A-Za-z0-9_=-]+$').hasMatch(s), isTrue);
  });

  test('linuxApiEncrypt returns eparams hex', () {
    final out = NeteaseCrypto.linuxApiEncrypt({'id': 1});
    final eparams = out['eparams']!;
    expect(eparams.isNotEmpty, isTrue);
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(eparams), isTrue);
    // PKCS7 block size 16 → hex length multiple of 32.
    expect(eparams.length % 32, 0);
  });

  test('rsaEncrypt pads to 128 bytes', () {
    final hex = NeteaseCrypto.rsaEncrypt('abcdefghijklmnop');
    expect(hex.length, 256);
    // first bytes may be zero-padded
    expect(int.parse(hex.substring(0, 2), radix: 16), lessThan(256));
    expect(utf8.encode('abcdefghijklmnop').length, 16);
  });
}
