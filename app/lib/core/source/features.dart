import 'capabilities.dart';
import 'music_platform.dart';
import 'registry.dart';

/// 入口类功能：可以按「源 × 功能」两个维度单独开关。
///
/// 只覆盖**入口**（用户主动去搜、去点、去听新内容的地方）。详情页 / 播放 /
/// 歌词 /「我喜欢」这些被动能力**不做开关**——关掉它们只会把已经到手的内容
/// 变残，而不会省下任何请求。
///
/// 与整源开关（`AppSettings.enabledSources`）的关系是**两级 AND**：
/// 整源关掉 → 它的所有功能一起失效；整源启用 → 再由子开关逐项决定。
/// 子开关的取值**不随后者清零**，重新启用父开关即恢复原配置。
enum SourceFeature {
  search('search', '搜索'),
  personalFm('fm', '私人 FM'),
  dailyRecommend('daily', '每日推荐'),
  rank('rank', '排行榜');

  const SourceFeature(this.id, this.label);

  /// 落盘 token 里的功能段（改动会破坏已存配置，别改）。
  final String id;

  /// 设置页显示名。
  final String label;

  /// 落盘 token：`<wireName>:<id>`，例 `kugou:fm`。
  String tokenFor(MusicPlatform platform) => '${platform.wireName}:$id';

  /// 该源是否具备此功能的能力。
  ///
  /// 不具备 → 设置里**不列**这一项（列了也只能点出空态，是假入口）。
  /// 搜索是基类能力（[MusicSource.searchSongs]），注册过的源必然支持。
  bool supportedBy(MusicSourceRegistry? registry, MusicPlatform platform) {
    if (registry == null) return false;
    return switch (this) {
      SourceFeature.search => true,
      SourceFeature.personalFm =>
        registry.capability<PersonalFmSource>(platform) != null,
      SourceFeature.dailyRecommend =>
        registry.capability<DailyRecommendSource>(platform) != null,
      SourceFeature.rank => registry.capability<RankSource>(platform) != null,
    };
  }
}
