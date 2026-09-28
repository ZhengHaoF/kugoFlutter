import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugou/kugo_crypto.dart';
import 'package:kugo/core/api/kugou/kugo_sign.dart';

void main() {
  group('KugoSign.signCloudKey', () {
    test('matches KuGouMusicApi signCloudKey formula', () {
      // md5("musicclound" + hash + pid + salt)
      final hash = 'aabbccddeeff00112233445566778899';
      const pid = 20026;
      final expected = KugoSign.md5Hex(
        'musicclound$hash$pid'
        'ebd1ac3134c880bda6a2194537843caa0162e2e7',
      );
      expect(KugoSign.signCloudKey(hash, pid), expected);
    });

    test('is deterministic for same inputs', () {
      final a = KugoSign.signCloudKey('abc', 20026);
      final b = KugoSign.signCloudKey('abc', 20026);
      expect(a, b);
      expect(a.length, 32);
    });
  });

  group('mcloud envelope (playlistAes + rsa p)', () {
    test('playlistAesEncrypt/Decrypt roundtrip preserves JSON', () {
      final dataMap = {
        'page': 1,
        'pagesize': 30,
        'getkmr': 1,
      };
      final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
      expect(aes.key.length, 6);
      final decoded = KugoCrypto.playlistAesDecrypt(aes.str, aes.key);
      expect(decoded, isNotNull);
      final map = jsonDecode(decoded!) as Map;
      expect(map['page'], 1);
      expect(map['pagesize'], 30);
      expect(map['getkmr'], 1);
    });

    test('body is raw AES ciphertext (base64 of str)', () {
      final aes = KugoCrypto.playlistAesEncrypt('{"page":1}');
      final body = base64.decode(aes.str);
      expect(body, isNotEmpty);
      // Ciphertext must not be the plaintext JSON.
      expect(utf8.decode(body, allowMalformed: true), isNot(contains('page')));
    });

    test('signParamsKey(clienttime) is md5(appid+salt+clientver+data)', () {
      const clienttime = '1700000000';
      final expected = KugoSign.md5Hex(
        '${KugoSign.appId}'
        'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
        '${KugoSign.clientVer}'
        '$clienttime',
      );
      expect(KugoSign.signParamsKey(clienttime), expected);
    });
  });
}
