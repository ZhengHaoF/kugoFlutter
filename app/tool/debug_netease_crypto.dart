import 'dart:convert';
import 'dart:typed_data';

import 'package:kugo/core/api/netease/netease_crypto.dart';

void main() {
  // 1) RSA 公钥解析结果
  final key = debugParseRsa();
  print('n bits=${key.$1.bitLength} e=${key.$2}');
  print('n hex=${key.$1.toRadixString(16).substring(0, 32)}…');

  // 2) weapi 对同一 payload 两次（固定随机）应稳定
  final payload = {'s': 'a', 'type': '1', 'limit': '5', 'offset': '0', 'total': 'true'};
  final enc = NeteaseCrypto.weApiEncrypt(payload);
  print('encSecKey len=${enc['encSecKey']!.length}');
  print('params len=${enc['params']!.length}');
  print('json=${jsonEncode(payload)}');
}
