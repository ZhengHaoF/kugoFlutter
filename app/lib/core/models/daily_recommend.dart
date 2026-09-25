import 'track.dart';

/// 每日推荐（跨源统一结果）。
///
/// 各源差异（酷狗 `/top/ip` 公开兜底 + 个性化接口、网易 G3 每日推荐）在 source
/// 实现里收口成以下四个字段，UI 不按源分支。
class DailyRecommendResult {
  const DailyRecommendResult({
    required this.tracks,
    this.personalized = false,
    this.error = '',
    this.needLogin = false,
  });

  final List<Track> tracks;

  /// 是否为「个性化」推荐（酷狗登录态、网易日推均为真）。
  final bool personalized;

  /// 失败文案；空 = 无错误。
  final String error;

  /// 空结果是否因未登录（提示「去登录」）。
  final bool needLogin;

  bool get isEmpty => tracks.isEmpty;
}

/// 日推页顶部日期标签（本地日期，与源无关）。
String dailyRecommendDateLabel([DateTime? date]) {
  final d = date ?? DateTime.now();
  return '${d.month}月${d.day}日';
}
