/// 纯 Dart Cookie 校验，协议与 CLI 不依赖 Flutter 存储插件。
abstract final class BiliCookies {
  static final _validKey = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  static Map<String, String> sanitize(Map<Object?, Object?> raw) {
    final result = <String, String>{};
    for (final e in raw.entries) {
      if (e.key is! String || e.value is! String) continue;
      final name = e.key as String;
      final value = e.value as String;
      if (!_validKey.hasMatch(name) ||
          value.isEmpty ||
          value.contains(';') ||
          value.runes.any((r) => r <= 0x20 || r >= 0x7f)) {
        continue;
      }
      result[name] = value;
    }
    return (result['SESSDATA'] ?? '').isEmpty ? {} : result;
  }
}
