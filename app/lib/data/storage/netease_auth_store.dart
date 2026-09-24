import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/netease/netease_client.dart';

/// 网易云登录态落盘（对齐 Neri `NeteaseCookieRepository`）。
///
/// 存 JSON `{cookies:{...}, savedAt:<ms>}`，key `netease.auth.v1`。
/// 只落「含登录 cookie 键」的快照，并按 Neri 的规则过滤非法键值，
/// 避免把被污染的值再灌回请求头。
class NeteaseAuthStore {
  static const _key = 'netease.auth.v1';

  /// 判定「已登录」的键（Neri `LOGIN_COOKIE_KEYS`）。
  static const loginCookieKeys = ['MUSIC_U'];

  /// cookie 名合法字符集：`^[!#$%&'*+.^_`|~0-9A-Za-z-]+$`。
  static final RegExp _validKey = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");

  static bool _isAcceptable(String key, String value) {
    if (key.isEmpty || value.isEmpty) return false;
    if (!_validKey.hasMatch(key)) return false;
    if (value.contains(';')) return false;
    for (final r in value.runes) {
      if (r < 0x20 || r == 0x7f) return false; // ISO 控制符
    }
    return true;
  }

  static bool _hasLoginCookie(Map<String, String> cookies) =>
      loginCookieKeys.any((k) => (cookies[k] ?? '').isNotEmpty);

  /// 编码为落盘 JSON；**无登录 cookie 时返回 null**（表示不该落盘）。
  static String? encode(Map<String, String> cookies, {DateTime? savedAt}) {
    final picked = <String, String>{};
    for (final e in cookies.entries) {
      if (!_isAcceptable(e.key, e.value)) continue;
      picked[e.key] = e.value;
    }
    if (!_hasLoginCookie(picked)) return null;
    return jsonEncode({
      'cookies': picked,
      'savedAt': (savedAt ?? DateTime.now()).millisecondsSinceEpoch,
    });
  }

  /// 解码落盘 JSON；非法 / 无登录 cookie 时返回空 Map。
  static Map<String, String> decode(String raw) {
    final Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return const {};
    }
    if (data is! Map) return const {};
    final node = data['cookies'];
    if (node is! Map) return const {};
    final out = <String, String>{};
    for (final e in node.entries) {
      final key = '${e.key}';
      final value = '${e.value}';
      if (!_isAcceptable(key, value)) continue;
      out[key] = value;
    }
    if (!_hasLoginCookie(out)) return const {};
    return out;
  }

  /// 启动时把磁盘凭据灌回 [client]；无有效凭据返回 false。
  static Future<bool> restoreInto(NeteaseClient client) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return false;
    final cookies = decode(raw);
    if (cookies.isEmpty) {
      await prefs.remove(_key);
      return false;
    }
    client.seedCookies(cookies);
    return client.hasLogin;
  }

  /// 落盘当前会话；无登录 cookie 时清掉旧记录。
  static Future<void> save(NeteaseClient client) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = encode(client.cookies);
    if (raw == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, raw);
  }

  /// 清除本地登录记录。
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
