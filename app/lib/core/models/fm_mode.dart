/// 私人 FM「电台」模式（红心 / 小众 / 速览）。
///
/// 三个档位都走酷狗真实私人 FM 接口 `/v2/personal_recommend`
/// （KuGouMusicApi `module/personal_fm.js`），只是请求参数不同：
/// [modeParam] → 接口 `mode`（normal/small/peak）。
///
/// 注意：接口的 `song_pool_id`（口味/风格/探索）属于**另一条轴**，
/// 见 [FmSongPool.poolId]，不要塞到这里来。
enum FmMode { heart, niche, peek }

extension FmModeX on FmMode {
  /// 分段按钮 / chip 上的短标签。
  String get label => switch (this) {
        FmMode.heart => '红心',
        FmMode.niche => '小众',
        FmMode.peek => '速览',
      };

  /// 电台标题，如「红心电台」。
  String get stationTitle => switch (this) {
        FmMode.heart => '红心电台',
        FmMode.niche => '小众电台',
        FmMode.peek => '速览电台',
      };

  /// 副标题（一句话描述这个电台的口味）。
  String get subtitle => switch (this) {
        FmMode.heart => '猜你喜欢',
        FmMode.niche => '小众精选',
        FmMode.peek => '短曲速览',
      };

  /// 真实接口的 `mode` 参数。
  String get modeParam => switch (this) {
        FmMode.heart => 'normal',
        FmMode.niche => 'small',
        FmMode.peek => 'peak',
      };

  /// 是否偏好短曲（用于本地时长过滤：peek 速览只留短歌）。
  bool get preferShort => this == FmMode.peek;
}

/// 私人 FM 的「口味池」维度，与 [FmMode] **正交**。
///
/// - 真实接口：本轴就是接口的 `song_pool_id`（0=口味 / 1=风格 / 2=探索），
///   官方语义为「Alpha 根据口味 / Beta 根据风格 / Gamma 探索」。
/// - 兜底（关键词池）模式：没有服务端含义，只是一组搜索关键词，以及
///   「为什么是这首歌」那一行的诚实文案。
enum FmSongPool { taste, style, explore }

extension FmSongPoolX on FmSongPool {
  String get label => switch (this) {
        FmSongPool.taste => '口味',
        FmSongPool.style => '风格',
        FmSongPool.explore => '探索',
      };

  /// 真实接口的 `song_pool_id`。
  int get poolId => switch (this) {
        FmSongPool.taste => 0,
        FmSongPool.style => 1,
        FmSongPool.explore => 2,
      };

  /// 并入本池候选集的关键词束。
  List<String> get keywords => switch (this) {
        FmSongPool.taste => const ['热门', '华语流行', '经典'],
        FmSongPool.style => const ['民谣', '电子', '轻音乐'],
        FmSongPool.explore => const ['独立', '冷门', '爵士'],
      };

  /// 「为什么是这首歌」的诚实一行说明（与旧 personal_fm_page.dart 一致）。
  String get reasonLabel => switch (this) {
        FmSongPool.taste => '来自「热门 / 华语流行」',
        FmSongPool.style => '来自「民谣 / 电子」',
        FmSongPool.explore => '来自「独立 / 爵士」',
      };

  /// 按电台档位微调关键词：小众档换成更“小众”的词，速览/红心用原词。
  List<String> keywordsFor(FmMode mode) => switch (mode) {
        FmMode.heart => keywords,
        FmMode.niche => const ['小众', '独立', '冷门', '地下', '宝藏'],
        FmMode.peek => keywords,
      };
}
