import 'package:shared_preferences/shared_preferences.dart';

/// 上次播放位置（单曲）。
///
/// 放在 SharedPreferences 而不是 Drift：队列表加列要走 build_runner 重生成，
/// 而这个值只是「下次冷启动恢复到哪」。存的时候带上曲目身份，恢复时比对，
/// 避免把上一首的位置套到另一首上。
class PlaybackPositionStore {
  PlaybackPositionStore._();

  static const _kKey = 'playback.position.key';
  static const _kMs = 'playback.position.ms';

  static Future<void> save(String trackKey, int positionMs) async {
    if (trackKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, trackKey);
      await prefs.setInt(_kMs, positionMs < 0 ? 0 : positionMs);
    } catch (_) {}
  }

  /// [trackKey] 对应的位置；不匹配 / 无记录 / 零位 → null。
  static Future<int?> load(String trackKey) async {
    if (trackKey.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(_kKey);
      final ms = prefs.getInt(_kMs);
      if (key == null || key != trackKey || ms == null || ms <= 0) return null;
      return ms;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
      await prefs.remove(_kMs);
    } catch (_) {}
  }
}
