import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/bili/bili_client.dart';
import '../../core/api/bili/bili_cookies.dart';

/// 与其他音源隔离的本地凭据；不把 Cookie 写进日志或导出文件。
abstract final class BiliAuthStore {
  static const key = 'bili.auth.v1';
  static Map<String, String> sanitize(Map<Object?, Object?> raw) =>
      BiliCookies.sanitize(raw);

  static Map<String, String> decode(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['cookies'] is! Map) return {};
      return sanitize(data['cookies'] as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> restoreInto(BiliClient client) async {
    final prefs = await SharedPreferences.getInstance();
    final cookies = decode(prefs.getString(key) ?? '');
    if (cookies.isEmpty) {
      await prefs.remove(key);
    } else {
      client.seedCookies(cookies);
    }
  }

  static Future<void> save(BiliClient client) async {
    final prefs = await SharedPreferences.getInstance();
    final cookies = sanitize(client.cookies);
    if (cookies.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode({'cookies': cookies}));
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
