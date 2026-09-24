import '../source/music_platform.dart';
import 'audio_quality.dart';

class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.durationMs,
    this.platform = MusicPlatform.kugou,
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

  /// 音源平台。身份键 = [identityKey]（`platform:id`）。
  final MusicPlatform platform;

  /// 平台侧歌曲稳定 id：酷狗 = mixSongId 优先（见 mappers），网易 = songId。
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

  /// 跨源稳定键，队列/历史/歌词缓存/MediaItem 一律用这个。
  String get identityKey => musicIdentity(platform, id);

  /// 能否安全跳转歌手详情页（必须有 numeric id）。
  bool get hasArtistId => artistId.trim().isNotEmpty;

  Track copyWith({
    String? id,
    String? name,
    String? artist,
    String? album,
    String? coverUrl,
    int? durationMs,
    MusicPlatform? platform,
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
      platform: platform ?? this.platform,
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
    this.isRank = false,
    this.platform = MusicPlatform.kugou,
    this.listKind = 1,
    this.userId = '',
    this.isDefault = false,
    this.type = 0,
    this.listId = '',
    this.rankTypeName = '',
    this.updateFrequency = '',
  });

  final String id;
  final String name;
  final String coverUrl;
  final String description;

  /// Owner nickname; empty for endpoints that don't report one.
  final String creator;
  final int trackCount;
  final String playCountLabel;
  final bool isRank;

  final MusicPlatform platform;

  /// 酷狗列表种类：1 歌单 / 2 专辑（原字段名 `source`，与音源撞名故改）。
  /// 与 [type]（0 自建 / 1 收藏）语义不同，勿混用。
  final int listKind;

  /// Owner userid when reported by user playlist endpoints.
  final String userId;

  /// True for default favorites playlist.
  final bool isDefault;

  /// Kugou list `type`: 0 self-created (incl. 我喜欢), 1 collected.
  final int type;

  /// Cloud `listid` from `/user/playlist` — required for track APIs.
  /// Never fall back to public `specialid`.
  final String listId;

  /// 榜单分类名（如「推荐」）；空 = 接口未提供。
  final String rankTypeName;

  /// 更新频率（如「日更」）；空 = 接口未提供。
  final String updateFrequency;

  PlaylistBrief copyWith({
    String? id,
    String? name,
    String? coverUrl,
    String? description,
    String? creator,
    int? trackCount,
    String? playCountLabel,
    bool? isRank,
    MusicPlatform? platform,
    int? listKind,
    String? userId,
    bool? isDefault,
    int? type,
    String? listId,
    String? rankTypeName,
    String? updateFrequency,
  }) {
    return PlaylistBrief(
      id: id ?? this.id,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      description: description ?? this.description,
      creator: creator ?? this.creator,
      trackCount: trackCount ?? this.trackCount,
      playCountLabel: playCountLabel ?? this.playCountLabel,
      isRank: isRank ?? this.isRank,
      platform: platform ?? this.platform,
      listKind: listKind ?? this.listKind,
      userId: userId ?? this.userId,
      isDefault: isDefault ?? this.isDefault,
      type: type ?? this.type,
      listId: listId ?? this.listId,
      rankTypeName: rankTypeName ?? this.rankTypeName,
      updateFrequency: updateFrequency ?? this.updateFrequency,
    );
  }
}


/// 逐字（KRC）时间片：一个汉字/音节/单词。
class LyricChar {
  const LyricChar({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int startMs;
  final int endMs;

  bool contains(int positionMs) =>
      positionMs >= startMs && positionMs < endMs;
}

class LyricLine {
  const LyricLine({
    required this.timeMs,
    required this.text,
    this.endMs,
    this.chars = const [],
    this.translated,
    this.romanized,
  });

  final int timeMs;
  final String text;

  /// 行结束时间；KRC 有精确值，LRC 可空。
  final int? endMs;

  /// 逐字时间轴；空 = 仅整行（LRC）。
  final List<LyricChar> chars;

  /// 译文副行（KRC `[language:]` type=1），无则 null。
  final String? translated;

  /// 音译/罗马音副行（type=0），无则 null。
  final String? romanized;

  bool get hasCharTiming => chars.isNotEmpty;

  /// 该行内已唱过的字符数（含当前正在唱的）。
  int sungCharCount(int positionMs) {
    if (chars.isEmpty) return positionMs >= timeMs ? text.length : 0;
    var n = 0;
    for (final c in chars) {
      if (c.startMs <= positionMs) {
        n += c.text.length;
      } else {
        break;
      }
    }
    return n;
  }
}

/// 歌词加载状态：与是否正在播放解耦。
///
/// 切歌 / 冷启动恢复后应立刻进入 loading；UI 据此区分
/// 「歌词加载中…」与「暂无歌词」。
enum LyricsStatus { idle, loading, ready, empty }

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
