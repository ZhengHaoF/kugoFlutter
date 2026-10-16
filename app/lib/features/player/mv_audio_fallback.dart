/// MV 音频兜底：歌曲音源解析不出可播地址时，借用其关联曲库 MV 的音轨。
///
/// 对齐 EchoMusic `mvAudio.ts`（PR #482）。仅当用户显式开启设置时才被调用，
/// 且一次播放请求只尝试一次（由调用方用 `seq` 保证）。
///
/// 只收「官方发布的完整曲库 MV」（见 [MvBrief.isCatalogMv]）：短视频 / UGC /
/// 其他版本的时长与歌曲对不上，拿来兜底只会得到错误的播放时长。
library;

import '../../core/models/mv_models.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/registry.dart';
import '../mv/mv_entry.dart';

/// 兜底不可用的原因。文案直接面向日志与 UI 提示。
enum MvAudioUnavailableReason {
  noMixSongId('缺少歌曲关联 ID，无法查询曲库 MV'),
  noCapability('当前音源不支持 MV'),
  allShortVideos('关联视频均被平台标记为短视频，未找到可用 MV'),
  noCatalogMv('未找到符合条件的曲库 MV'),
  noUrl('曲库 MV 播放地址获取失败'),
  queryFailed('曲库 MV 查询失败，请稍后重试');

  const MvAudioUnavailableReason(this.message);

  final String message;
}

/// 兜底结果：可直接喂给播放引擎的地址集合。
class MvAudioFallbackResult {
  const MvAudioFallbackResult({
    required this.urls,
    required this.headers,
    required this.mv,
  });

  /// 主地址在前，备用地址在后（引擎按序试播）。
  final List<String> urls;
  final Map<String, String> headers;

  /// 实际借用的曲库 MV（供 UI 标注）。
  final MvBrief mv;
}

/// 从同曲多版本里挑一条可作兜底的曲库 MV。
///
/// 过滤与排序对齐 EchoMusic `pickCatalogMv`：先取官方推荐位，没有则取列表中
/// 第一条合格项（保持上游顺序，不引入不稳定排序）。
MvBrief? pickCatalogMv(List<MvBrief> versions) {
  MvBrief? best;
  for (final mv in versions) {
    if (!mv.isCatalogMv) continue;
    if (mv.durationMs <= 0) continue;
    if (mv.hash.isEmpty) continue;
    if (best == null || (mv.isRecommend && !best.isRecommend)) best = mv;
  }
  return best;
}

/// 解析可用于兜底播放的 MV 音源。
///
/// [isCurrent] 由调用方注入（通常是播放控制器的 `seq` 闸门）：每一步之间都会
/// 检查，切歌后立即放弃，且不再回写任何状态。
/// 返回 `null` = 没有可用兜底，原因通过 [onUnavailable] 外抛给日志/提示。
Future<MvAudioFallbackResult?> resolveMvAudioFallback(
  Track track, {
  required bool Function() isCurrent,
  void Function(MvAudioUnavailableReason reason)? onUnavailable,
}) async {
  void unavailable(MvAudioUnavailableReason reason) =>
      onUnavailable?.call(reason);

  // 必须是正整数 album_audio_id，否则 kmr 接口无从查询。
  final mixSongId = track.mixSongId.trim();
  if (!_isPositiveInt(mixSongId)) {
    unavailable(MvAudioUnavailableReason.noMixSongId);
    return null;
  }
  if (!isCurrent()) return null;

  final registry = musicSourceRegistry;
  final search = registry?.capability<MvSearchSource>(track.platform);
  final detail = registry?.capability<MvDetailSource>(track.platform);
  if (search == null || detail == null) {
    unavailable(MvAudioUnavailableReason.noCapability);
    return null;
  }

  List<MvBrief> versions;
  try {
    // 与 MV 入口 / MV 播放页共用内存缓存，点过 MV 的歌不再重复打接口。
    versions = await loadSongMvs(track);
  } catch (_) {
    if (isCurrent()) unavailable(MvAudioUnavailableReason.queryFailed);
    return null;
  }
  if (!isCurrent()) return null;

  final mv = pickCatalogMv(versions);
  if (mv == null) {
    final allShort =
        versions.isNotEmpty &&
        versions.every((v) => v.isShort != null && v.isShort != 0);
    unavailable(
      allShort
          ? MvAudioUnavailableReason.allShortVideos
          : MvAudioUnavailableReason.noCatalogMv,
    );
    return null;
  }

  try {
    final resolved = await detail.resolveMvPlayUrl(mv.hash);
    if (!isCurrent()) return null;
    final urls = resolved.allUrls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      unavailable(MvAudioUnavailableReason.noUrl);
      return null;
    }
    return MvAudioFallbackResult(
      urls: urls,
      // 与音频同源防盗链头；trackermv 校验 UA/Referer，缺头会 403。
      headers: resolved.headers,
      mv: mv,
    );
  } catch (_) {
    if (isCurrent()) unavailable(MvAudioUnavailableReason.queryFailed);
    return null;
  }
}

bool _isPositiveInt(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);
