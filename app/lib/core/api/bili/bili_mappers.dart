import '../../models/search_result.dart';
import '../../models/track.dart';
import '../../source/music_platform.dart';
import 'bili_client.dart';

/// B 站原始响应 → 统一模型（B2 适配层）。
///
/// 口径（方案 §2 / §4.1 / §5.3）：
/// - **搜索态 `Track.id` = 裸 bvid**（`search/type=video` 不返回 cid，
///   分入口定形态见 §5.3 #5）；内容态 `bvid:cid` 由 B4 列表口产出，
///   `resolvePlayUrl` 两种形态都认。
/// - `title` 已在客户端剥过 `<em class="keyword">` + HTML 实体（必答项 #3）。
/// - **> 15 min 的长视频不进单曲结果**（§5.3 #8，阈值 B2 定案）：
///   合集 / 长混音 / 完整现场走 B4 的 `PlaylistDetailSource`，
///   别让用户在「单曲」Tab 点到一段 40 分钟的现场。
abstract final class BiliMappers {
  /// 单曲搜索结果时长上限（秒）。
  static const maxSongDurationSec = 15 * 60;

  /// 搜索页 → 统一 Track 列表（`total` 用服务端 numResults）。
  static SearchPageResult<Track> mapSearchPage(BiliVideoPage page) {
    final tracks = <Track>[];
    for (final item in page.items) {
      if (item.bvid.isEmpty) continue;
      if (item.durationSec > maxSongDurationSec) continue;
      tracks.add(mapTrack(item));
    }
    return SearchPageResult(items: tracks, total: page.numResults);
  }

  /// 单个视频 → Track（一个视频 = 一首候选歌，默认 P1）。
  static Track mapTrack(BiliVideoItem item) => Track(
        platform: MusicPlatform.bili,
        id: item.bvid,
        name: item.title,
        artist: item.author,
        // B 站无专辑口径；留空而非编造。
        album: '',
        coverUrl: item.coverUrl,
        durationMs: item.durationSec * 1000,
        // UP 主 mid → artistId（B4 歌手详情页跳转用；0 = 未知）。
        artistId: item.mid == 0 ? '' : item.mid.toString(),
        // 搜索态不知道实际档位（取流时才知道），留空让 UI 显示未知。
        quality: '',
      );
}
