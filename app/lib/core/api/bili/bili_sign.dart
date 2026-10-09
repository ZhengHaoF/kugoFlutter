import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bili_endpoints.dart';

/// WBI 反爬签名（对齐 NeriPlayer `BiliClient.signWbiUrl` /
/// `ensureValidMixin` / `webTicketHmacSha256Hex`，逻辑逐行核对一致）。
///
/// **纯函数、无 IO** —— 单测不联外网（哔哩哔哩接入方案 §10）。
///
/// 签名流程（方案 §3.1）：
/// 1. `nav` 取 `wbi_img.img_url` / `sub_url`，文件名主体拼 `raw`；
/// 2. `raw` 按 [mixinIndex] 打乱取前 32 位 = `mixinKey`（缓存 10 分钟）；
/// 3. 请求参数加 `wts`（秒级时间戳）→ **值**过滤 `!'()*` → 按 key 排序；
/// 4. `w_rid = md5(query + mixinKey)`，`query` 为 `k=v&…`（k/v 均严格
///    encodeURIComponent）。
abstract final class BiliSign {
  /// MIXIN_INDEX：mixinKey 打乱表，64 位，官方固定值（方案 §3.1，
  /// 与 bilibili-API-collect 公示表一致）。
  static const mixinIndex = <int>[
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, //
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, //
    22, 25, 54, 21, 56, 62, 6, 63, 57, 20, 34, 52, 59, 11, 36, 44, //
  ];

  /// 由 `nav` 的 `img_url` / `sub_url` 算 mixinKey。
  ///
  /// 取 URL 路径最后一段的文件名主体（`/` 后、`.` 前），即 imgKey/subKey。
  static String mixinKeyFromUrls(String imgUrl, String subUrl) {
    if (imgUrl.trim().isEmpty || subUrl.trim().isEmpty) {
      throw ArgumentError('invalid wbi img/sub url: $imgUrl / $subUrl');
    }
    return mixinKeyFromKeys(_fileNameStem(imgUrl), _fileNameStem(subUrl));
  }

  /// 由 imgKey + subKey 算 mixinKey（32 位；不足 32 位时原样返回，
  /// 对齐 NeriPlayer `ensureValidMixin`）。
  static String mixinKeyFromKeys(String imgKey, String subKey) {
    final raw = imgKey + subKey;
    final sb = StringBuffer();
    for (final idx in mixinIndex) {
      if (idx < raw.length) sb.write(raw[idx]);
    }
    final mixed = sb.toString();
    return mixed.length >= 32 ? mixed.substring(0, 32) : mixed;
  }

  /// 值过滤：删掉 `!'()*`。**只过滤值、不过滤 key**（对齐 NeriPlayer
  /// `filterValue`；官方口径同）。
  static String filterValue(String value) =>
      value.replaceAll(RegExp(r"""[!'()*]"""), '');

  /// 严格 encodeURIComponent：unreserved 集 `A-Za-z0-9-_.!~*'()`，
  /// 其余按 UTF-8 百分号编码（大写 hex）。
  ///
  /// **不能**直接用 `Uri.encodeQueryComponent`——它把空格编码成 `+`，
  /// 而官方预映像用 JS `encodeURIComponent`（空格是 `%20`）。带空格或
  /// 中文的搜索词会因此签出错误 `w_rid`（服务端 -403）。
  static String encodeUriComponent(String value) {
    final sb = StringBuffer();
    for (final byte in utf8.encode(value)) {
      if (_isUnreserved(byte)) {
        sb.writeCharCode(byte);
      } else {
        sb.write('%');
        sb.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return sb.toString();
  }

  /// 算 `w_rid`。[params] 为业务参数（会被拷贝，不入参会修改）。
  /// [wts] 缺省取当前秒级时间戳（测试可注入固定值锁向量）。
  static String wrid(
    Map<String, String> params,
    String mixinKey, {
    int? wts,
  }) {
    final filtered = <String, String>{};
    params.forEach((k, v) => filtered[k] = filterValue(v));
    filtered['wts'] =
        (wts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final keys = filtered.keys.toList()..sort();
    final query = keys
        .map((k) =>
            '${encodeUriComponent(k)}=${encodeUriComponent(filtered[k]!)}')
        .join('&');
    return md5.convert(utf8.encode(query + mixinKey)).toString();
  }

  /// WebTicket 兜底签名（方案 §3.2）：`hexsign = HMAC-SHA256(msg, key)`，
  /// 小写 hex。key 为 [BiliEndpoints.webTicketKey]。
  static String hmacSha256Hex(String message, [String? key]) {
    final hmac = Hmac(sha256, utf8.encode(key ?? BiliEndpoints.webTicketKey));
    return hmac.convert(utf8.encode(message)).toString();
  }

  static String _fileNameStem(String url) {
    final path = Uri.parse(url).path;
    final last = path.split('/').last;
    final dot = last.indexOf('.');
    return dot <= 0 ? last : last.substring(0, dot);
  }

  static bool _isUnreserved(int b) =>
      (b >= 0x30 && b <= 0x39) || // 0-9
      (b >= 0x41 && b <= 0x5A) || // A-Z
      (b >= 0x61 && b <= 0x7A) || // a-z
      b == 0x2D || // -
      b == 0x2E || // .
      b == 0x5F || // _
      b == 0x7E || // ~
      b == 0x21 || // !
      b == 0x2A || // *
      b == 0x27 || // '
      b == 0x28 || // (
      b == 0x29; // )
}
