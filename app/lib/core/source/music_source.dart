import '../models/audio_quality.dart';
import '../models/search_result.dart';
import '../models/track.dart';
import 'music_platform.dart';

/// 统一失败。分源把业务码映射到这里，UI 不写 `switch (errcode)`。
sealed class SourceFailure implements Exception {
  const SourceFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// 断网 / 超时 / 中间盒 HTML 过滤（酷狗「URL过滤」等）。
class NetworkFailure extends SourceFailure {
  const NetworkFailure(super.message, {this.filtered = false});

  final bool filtered;
}

/// 需要登录（网易 `code==301`；酷狗 SSA 风控等需重登场景）。
class LoginRequired extends SourceFailure {
  const LoginRequired([super.message = '需要登录']);
}

/// 无版权 / VIP 墙 / fee，或明确不可播。
class NoPermission extends SourceFailure {
  const NoPermission([super.message = '没有播放权限']);
}

class NotFound extends SourceFailure {
  const NotFound([super.message = '未找到']);
}

class RateLimited extends SourceFailure {
  const RateLimited([super.message = '请求过于频繁']);
}

/// 解析失败、未知业务码 —— 上游协议可能已变。
class UpstreamChanged extends SourceFailure {
  const UpstreamChanged([super.message = '上游响应异常']);
}

/// 播放地址解析成功结果。headers 必须由 Source 下发（防盗链各源不同）。
class PlayUrlResult {
  const PlayUrlResult({
    required this.url,
    this.backupUrls = const [],
    this.headers = const {},
    this.grantedQuality,
    this.isPreviewClip = false,
  });

  final String url;
  final List<String> backupUrls;
  final Map<String, String> headers;
  final AppQuality? grantedQuality;
  final bool isPreviewClip;

  List<String> get allUrls => [url, ...backupUrls];
}

/// 歌词包。行模型复用 [LyricLine]（逐字/译文/音译已在行内）。
class LyricPayload {
  const LyricPayload({
    this.lines = const [],
    this.sourceTag = '',
  });

  final List<LyricLine> lines;
  final String sourceTag;

  static const empty = LyricPayload();

  bool get isEmpty => lines.isEmpty;
}

/// 所有音源都必须实现的最小契约。特殊能力见 `capabilities.dart`。
abstract class MusicSource {
  MusicPlatform get platform;

  /// 四个搜索入口同构（见 多音源接入方案 §3.2）：分页返回统一 Brief。
  ///
  /// `total` 缺失时返回 `null`（网易歌手搜索、酷狗 `search/singer` 都不报），
  /// 由调用方按「整页」启发式判断是否还有下一页 —— **不要瞎猜一个数**。
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  });

  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  });

  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  });

  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  });

  /// 短时播放地址。失败抛 [SourceFailure]。
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  });

  /// 歌词；无歌词返回 [LyricPayload.empty]。
  Future<LyricPayload> fetchLyric(Track track);
}
