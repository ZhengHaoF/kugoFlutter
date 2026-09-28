import 'track.dart';

/// 云盘文件身份与播放源。对齐 EchoMusic `CloudAudioSource`。
///
/// 身份键优先级：`cloudFileId`（kv_id）→ `hash`。删除与取流都靠它。
class CloudAudioSource {
  const CloudAudioSource({
    required this.hash,
    this.cloudFileId = '',
    this.hashStd = '',
    this.audioId = '',
    this.albumAudioId = '',
    this.bitrate,
    this.size,
    this.ext = '',
    this.name = '',
    this.matchBy,
  });

  /// 文件 hash（播放地址必填）。
  final String hash;

  /// 云盘文件 ID（上游 `kv_id` / `fileid`）。删除优先用它。
  final String cloudFileId;

  /// 标准 hash，回退匹配用。
  final String hashStd;

  /// 曲库音频 ID（≠ mixsongid）。
  final String audioId;

  /// 专辑音频 ID（即 mixsongid）。
  final String albumAudioId;

  /// 码率档：1/2=128, 3=320, 4=flac, 5=high。
  final int? bitrate;

  /// 文件字节数。
  final int? size;

  /// 扩展名（不带点）。
  final String ext;

  /// 展示名（已去扩展名）。
  final String name;

  /// 命中来源（回退匹配时标记用哪一级 key 命中）。
  final CloudMatchBy? matchBy;

  bool get hasFileId => _isPositiveId(cloudFileId);

  CloudAudioSource copyWith({
    String? hash,
    String? cloudFileId,
    String? hashStd,
    String? audioId,
    String? albumAudioId,
    int? bitrate,
    int? size,
    String? ext,
    String? name,
    CloudMatchBy? matchBy,
  }) {
    return CloudAudioSource(
      hash: hash ?? this.hash,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      hashStd: hashStd ?? this.hashStd,
      audioId: audioId ?? this.audioId,
      albumAudioId: albumAudioId ?? this.albumAudioId,
      bitrate: bitrate ?? this.bitrate,
      size: size ?? this.size,
      ext: ext ?? this.ext,
      name: name ?? this.name,
      matchBy: matchBy ?? this.matchBy,
    );
  }
}

enum CloudMatchBy { albumAudioId, audioId, hashStd, hash }

/// 云盘容量（字节）。上游字段名 `availble_size` 拼写如此。
class CloudDiskCapacity {
  const CloudDiskCapacity({
    this.totalBytes = 0,
    this.usedBytes = 0,
    this.availableBytes = 0,
  });

  final int totalBytes;
  final int usedBytes;
  final int availableBytes;

  static const empty = CloudDiskCapacity();

  /// 已用量；上游未报 `used_size` 时用 total-available 推。
  int get used => usedBytes > 0 ? usedBytes : (totalBytes - availableBytes).clamp(0, 1 << 62);

  /// 用量比例 0–1；容量未知时返回 0。
  double get usedRatio {
    if (totalBytes <= 0) return 0;
    return (used / totalBytes).clamp(0.0, 1.0);
  }
}

/// 云盘一页。
class CloudDiskPage {
  const CloudDiskPage({
    this.tracks = const [],
    this.total = 0,
    this.capacity = CloudDiskCapacity.empty,
    this.page = 1,
    this.hasMore = false,
  });

  final List<Track> tracks;
  final int total;
  final CloudDiskCapacity capacity;
  final int page;

  /// 是否还有下一页（按 total 或本页是否满页判断）。
  final bool hasMore;
}

/// 单条删除目标。优先 [cloudFileId]，缺失回退 [hash]。
class CloudDeleteTarget {
  const CloudDeleteTarget({
    this.cloudFileId = '',
    this.hash = '',
    this.albumAudioId = '',
  });

  final String cloudFileId;
  final String hash;
  final String albumAudioId;

  bool get canDelete => _isPositiveId(cloudFileId) || hash.trim().isNotEmpty;
}

bool _isPositiveId(String value) {
  final text = value.trim();
  return RegExp(r'^\d+$').hasMatch(text) && !RegExp(r'^0+$').hasMatch(text);
}

/// [Track] → [CloudDeleteTarget]。
CloudDeleteTarget cloudDeleteTargetFromTrack(Track track) {
  return CloudDeleteTarget(
    cloudFileId: track.cloudFileId,
    hash: track.hash,
    albumAudioId: track.mixSongId,
  );
}

/// 上传前曲库匹配结果（用于写入 `audio_id` / `album_audio_id`）。
class CloudUploadMatch {
  const CloudUploadMatch({
    this.audioId = '',
    this.albumAudioId = '',
    this.hashStd = '',
    this.authorName = '',
    this.audioName = '',
  });

  final String audioId;
  final String albumAudioId;
  final String hashStd;
  final String authorName;
  final String audioName;

  bool get hasIds => audioId.isNotEmpty || albumAudioId.isNotEmpty;
}

/// 单文件上传结果。
class CloudUploadResult {
  const CloudUploadResult({
    required this.secondUpload,
    this.matched = false,
    this.hash = '',
  });

  /// 服务端已有该文件（`upload_id` 为空），跳过分片直传。
  final bool secondUpload;

  /// 是否关联到了曲库 ID。
  final bool matched;

  /// 服务端文件 hash（`x-bss-filename`）。
  final String hash;
}
