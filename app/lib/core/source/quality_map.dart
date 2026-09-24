import '../models/audio_quality.dart';

/// 全局抽象音质 ↔ 各平台请求档位。
abstract final class SourceQualityMap {
  /// 酷狗 `/v5/url` quality 参数。
  static String kugouParam(AppQuality q) => switch (q) {
        AppQuality.standard => '128',
        AppQuality.hq => '320',
        AppQuality.sq => 'flac',
        AppQuality.hiRes => 'hires',
      };

  /// 网易 `song/enhance/player/url/v1` 的 level（预留，阶段 B 起用）。
  static String neteaseLevel(AppQuality q) => switch (q) {
        AppQuality.standard => 'standard',
        AppQuality.hq => 'exhigh',
        AppQuality.sq => 'lossless',
        AppQuality.hiRes => 'hires',
      };

  /// 酷狗向下兼容候选（含自身），映射为 `/v5/url` 参数串。
  static List<String> kugouCandidates(AppQuality preferred) =>
      [for (final q in preferred.candidatesDownward) kugouParam(q)];
}
