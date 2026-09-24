import '../models/fm_mode.dart';
import '../models/track.dart';

/// 可选能力接口：谁有谁 `implements`。UI 用 `registry.capability<T>()` 显隐，
/// 禁止在基类堆 `bool get hasXxx` + 空实现。

/// 私人 FM（酷狗红心 Radio / 网易私人 FM 的共同子集）。
abstract interface class PersonalFmSource {
  /// 拉取下一批 FM 曲目。
  Future<List<Track>> nextFmTracks({int remain = 5});

  /// 上报：喜欢 / 跳过 / 垃圾桶（语义由实现映射到平台参数）。
  Future<void> reportFmFeedback(Track track, {required FmFeedback feedback});
}

enum FmFeedback { like, skip, trash }

/// 酷狗红心 Radio 独有：模式/曲库切换。
abstract interface class HeartRadioSource {
  Future<void> setHeartMode({FmMode? mode, FmSongPool? pool});
}

/// 每日推荐。
abstract interface class DailyRecommendSource {
  Future<List<Track>> dailyRecommendedSongs();
}

/// 榜单。
abstract interface class RankSource {
  Future<List<({String id, String name, String coverUrl})>> rankBoards();
  Future<List<Track>> rankTracks(String boardId, {int page = 1});
}

/// 用户云端歌单写操作（加/删曲；建单另议）。
abstract interface class UserPlaylistWriteSource {
  Future<void> addPlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  });

  Future<void> removePlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  });
}

/// 热搜词。
abstract interface class SearchHotSource {
  Future<List<String>> hotKeywords();
}
