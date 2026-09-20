import 'audio_quality.dart';

class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
    this.hash = '',
    this.albumId = '',
    this.mixSongId = '',
    this.artistId = '',
    this.quality = 'SQ',
    this.isVip = false,
    this.availableQualities = const {},
    this.relateGoods = const [],
    this.qualityCatalogComplete = false,
    this.recDesc = '',
    this.similarDesc = '',
    this.language = '',
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final int durationMs;
  final String hash;
  final String albumId;
  final String mixSongId;

  /// 主歌手的 numeric id，用于跳转歌手详情页。
  /// **空字符串 = 未知**（部分接口只给 `filename`，拿不到 id）——
  /// 此时不应跳转，否则会把歌手名当 id 用，详情页必然加载失败。
  final String artistId;

  final String quality;
  final bool isVip;

  /// 已知可播音质；**空集合 = 未知**（不禁用选项，播放时向下 resolve）。
  final Set<AppQuality> availableQualities;
  final List<RelateGood> relateGoods;

  /// true = 接口给出了完整音质目录（relate_goods）；false = 仅从 hash 字段推断。
  final bool qualityCatalogComplete;

  /// 推荐语 / 推荐理由（私人 FM 等接口给 `recDesc`；空 = 未提供，勿编造）。
  final String recDesc;

  /// “相似推荐”描述（私人 FM 等接口可能给 `similarDesc`）。
  final String similarDesc;

  /// 语种标签（如 `国语` / `欧美` / `日语`；空 = 未知）。
  final String language;

  String get durationLabel {
    final total = Duration(milliseconds: durationMs);
    final m = total.inMinutes.toString().padLeft(2, '0');
    final s = (total.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get hasHash => hash.trim().isNotEmpty;

  /// 能否安全跳转歌手详情页（必须有 numeric id）。
  bool get hasArtistId => artistId.trim().isNotEmpty;

  Track copyWith({
    String? id,
    String? name,
    String? artist,
    String? album,
    String? coverUrl,
    int? durationMs,
    String? hash,
    String? albumId,
    String? mixSongId,
    String? artistId,
    String? quality,
    bool? isVip,
    Set<AppQuality>? availableQualities,
    List<RelateGood>? relateGoods,
    bool? qualityCatalogComplete,
    String? recDesc,
    String? similarDesc,
    String? language,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      durationMs: durationMs ?? this.durationMs,
      hash: hash ?? this.hash,
      albumId: albumId ?? this.albumId,
      mixSongId: mixSongId ?? this.mixSongId,
      artistId: artistId ?? this.artistId,
      quality: quality ?? this.quality,
      isVip: isVip ?? this.isVip,
      availableQualities: availableQualities ?? this.availableQualities,
      relateGoods: relateGoods ?? this.relateGoods,
      qualityCatalogComplete: qualityCatalogComplete ?? this.qualityCatalogComplete,
      recDesc: recDesc ?? this.recDesc,
      similarDesc: similarDesc ?? this.similarDesc,
      language: language ?? this.language,
    );
  }
}

class PlaylistBrief {
  const PlaylistBrief({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.description = '',
    this.creator = '',
    this.trackCount = 0,
    this.playCountLabel = '',
  });

  final String id;
  final String name;
  final String coverUrl;
  final String description;

  /// Owner nickname; empty for endpoints that don't report one.
  final String creator;
  final int trackCount;
  final String playCountLabel;
}

class LyricLine {
  const LyricLine({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
}

class ResolvedAudio {
  const ResolvedAudio({
    required this.url,
    this.backupUrls = const [],
    this.quality = '128k',
  });

  final String url;
  final List<String> backupUrls;

  /// 请求或响应中的音质 token（128/320/flac/hires…）。
  final String quality;

  List<String> get allUrls => [url, ...backupUrls];

  AppQuality? get qualityEnum => AudioQualityUtil.parseQualityToken(quality);
}
