/// MV / 视频领域模型。
///
/// 字段对齐酷狗 `search/mv`（富）+ `video/detail` + `kmr/audio/mv` 的交集，
/// 各源差异收口在 mapper 里（见 `data/repositories/mv_repository.dart`）。
library;

import '../source/music_platform.dart';

/// MV 收藏 ID 归一化。
///
/// 播放 hash、歌曲 album_audio_id **不能**当收藏 ID；只接受正整数 video_id
/// （对齐 EchoMusic `normalizeVideoId`）。非法返回空串。
///
/// 上限取 JS `Number.MAX_SAFE_INTEGER`（2^53-1）：上游 id 体系按 JS 数字
/// 处理，超界值在服务端会丢精度，必须拒绝。
String normalizeMvCollectId(Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty) return '';
  if (!RegExp(r'^\d+$').hasMatch(text)) return '';
  final id = int.tryParse(text);
  if (id == null || id <= 0) return '';
  if (id > 0x1FFFFFFFFFFFFF) return ''; // 2^53-1
  return '$id';
}

/// MV 列表/搜索摘要。
class MvBrief {
  const MvBrief({
    required this.id,
    required this.hash,
    required this.name,
    required this.coverUrl,
    this.artist = '',
    this.artistId = '',
    this.durationMs = 0,
    this.publishDate = '',
    this.qualityMark = '',
    this.mixSongId = '',
    this.audioHash = '',
    this.platform = MusicPlatform.kugou,
  });

  /// MV 稳定 id（酷狗 `MvID` / `video_id`）。可空字符串 = 接口未给。
  final String id;

  /// **主 MV hash**（播放/特权入参）。不是歌曲 `mvhash`，也不是分档 hash。
  final String hash;
  final String name;
  final String coverUrl;
  final String artist;
  final String artistId;
  final int durationMs;
  final String publishDate;

  /// 接口标注的最高清晰度（如 `1080P`）；空 = 未知。
  final String qualityMark;

  /// 歌曲侧 `album_audio_id`（酷狗 `MixSongID`），用于「跳回歌曲 / 关联 MV」。
  final String mixSongId;

  /// 关联音频 hash（可空）。
  final String audioHash;

  final MusicPlatform platform;

  String get durationLabel {
    final total = Duration(milliseconds: durationMs);
    final m = total.inMinutes.toString().padLeft(2, '0');
    final s = (total.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 一条可播的视频片源（某编码 × 某清晰度）。
class MvPlaySource {
  const MvPlaySource({
    required this.hash,
    required this.label,
    this.codec = '',
    this.width = 0,
    this.height = 0,
    this.filesize = 0,
    this.bitrate = 0,
  });

  /// 该档的视频 hash —— `video/url` 用它取地址。
  final String hash;

  /// 展示名，如 `1080P` / `720P`。
  final String label;

  /// `h264` / `h265` / `mkv`；空 = 未知。
  final String codec;
  final int width;
  final int height;
  final int filesize;
  final int bitrate;

  /// 是否比 [other] 更清晰（先按 height，再按 bitrate）。
  bool isClearerThan(MvPlaySource other) {
    if (height != other.height) return height > other.height;
    return bitrate > other.bitrate;
  }
}

/// MV 详情 + 可播片源列表。
class MvDetail {
  const MvDetail({
    required this.brief,
    this.sources = const [],
    this.description = '',
    this.playCountLabel = '',
    this.downloadCountLabel = '',
    this.collectionCountLabel = '',
    this.authors = const [],
  });

  final MvBrief brief;

  /// 多清晰度片源，**已按从清到糊排序**；空 = 未解析出片源。
  final List<MvPlaySource> sources;

  final String description;
  final String playCountLabel;
  final String downloadCountLabel;
  final String collectionCountLabel;

  /// 作者/歌手名列表（展示用）。
  final List<String> authors;

  /// 默认片源：最清的一档；无片源返回 null。
  MvPlaySource? get defaultSource => sources.isEmpty ? null : sources.first;
}

/// 取流结果（对齐 [PlayUrlResult] 的 headers 语义）。
class MvPlayUrlResult {
  const MvPlayUrlResult({
    required this.url,
    this.backupUrls = const [],
    this.headers = const {},
    this.filesize = 0,
  });

  final String url;
  final List<String> backupUrls;
  final Map<String, String> headers;
  final int filesize;

  List<String> get allUrls => [url, ...backupUrls];
}
