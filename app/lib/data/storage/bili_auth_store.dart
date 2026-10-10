import 'dart:convert';

import '../../core/api/bili/bili_client.dart';
import '../../core/api/bili/bili_cookies.dart';
import 'credential_store.dart';

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
    final revision = CredentialStore.revision(key);
    final cookies = decode(await CredentialStore.read(key) ?? '');
    if (revision != CredentialStore.revision(key)) return;
    if (cookies.isEmpty) {
      client.clearCookies();
      await CredentialStore.clear(key);
    } else {
      client.seedCookies(cookies);
    }
  }

  static Future<void> save(BiliClient client) async {
    final cookies = sanitize(client.cookies);
    if (cookies.isEmpty) {
      await CredentialStore.clear(key);
    } else {
      await CredentialStore.write(key, jsonEncode({'cookies': cookies}));
    }
  }

  static Future<void> clear() async {
    await CredentialStore.clear(key);
  }
}
