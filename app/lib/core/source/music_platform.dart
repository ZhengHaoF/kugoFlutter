/// 音源平台标识。身份键为 `(platform, id)`，禁止用裸 hash 当全局身份。
enum MusicPlatform {
  kugou,
  netease;

  String get wireName => name;

  /// 展示名：来源角标与音源筛选 chips 用（UI 禁止自己 `switch (platform)`）。
  String get label => switch (this) {
        MusicPlatform.kugou => '酷狗',
        MusicPlatform.netease => '网易云',
      };

  static MusicPlatform fromWire(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'kugou':
      case 'kg':
        return MusicPlatform.kugou;
      case 'netease':
      case 'ncm':
      case '163':
        return MusicPlatform.netease;
      default:
        return MusicPlatform.kugou;
    }
  }
}

/// 稳定的跨源实体键，用于队列/历史/歌词缓存/MediaItem。
String musicIdentity(MusicPlatform platform, String id) =>
    '${platform.wireName}:$id';
