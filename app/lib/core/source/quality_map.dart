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

  /// B 站 DASH 音轨的**带宽下限**（bps）。B 站按视频供给给档，
  /// **禁硬编码 audio id**（方案 §3.5 / §8.1：同一 id 带宽随视频变），
  /// 只能按带宽分档：实测 `30216`≈64k / `30232`≈80~115k /
  /// `30280`≈177~216k，故 70k 以上算 hq、150k 以上算 sq。
  ///
  /// hiRes（dolby / flac）不走带宽口径——按分组优先，见
  /// `BiliSource.selectAudio` 的 `_groupRank`。
  static int biliBandwidthFloor(AppQuality q) => switch (q) {
        AppQuality.standard => 0,
        AppQuality.hq => 70000,
        AppQuality.sq => 150000,
        AppQuality.hiRes => 150000,
      };
}
