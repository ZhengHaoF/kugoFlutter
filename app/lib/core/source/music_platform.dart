/// 音源平台标识。身份键为 `(platform, id)`，禁止用裸 hash 当全局身份。
enum MusicPlatform {
  kugou,
  netease;

  String get wireName => name;

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
