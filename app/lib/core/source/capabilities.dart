import '../models/audio_quality.dart';
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

/// 可播音质目录（酷狗 relate_goods）。无此能力则跳过懒加载。
abstract interface class QualityCatalogSource {
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchQualityCatalog(
    Track track,
  );
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

/// 用户云端「我喜欢」（红心）曲库。
///
/// 酷狗侧仍走既有 `userCollectionsProvider`（旧链路，带 fileid 写操作）；
/// 网易侧由本能力提供，UI 用 `registry.capability<UserLibrarySource>()` 取。
abstract interface class UserLibrarySource {
  /// 拉取云端「我喜欢」全部曲目（翻页/分批由实现内部处理）。
  Future<List<Track>> likedTracks();
}

/// 热搜词。
abstract interface class SearchHotSource {
  Future<List<String>> hotKeywords({int count = 20});
}

/// 设备扫码登录（网易扫码；酷狗走独立的 `features/auth` 链路，不经此处）。
///
/// 平台差异（unikey / chainId / MUSIC_U…）全部留在实现里，UI 只认下面三个
/// 统一模型与 [LoginQrStatus]。
abstract interface class DeviceLoginSource {
  /// 创建扫码会话：拿到二维码内容（由 UI 渲染成二维码）。
  Future<LoginQrSession> createLoginQr();

  /// 轮询一次扫码状态。参数即 [createLoginQr] 的返回值，原样回传。
  Future<LoginQrPoll> pollLoginQr(LoginQrSession session);

  /// 当前登录账号（未登录返回 null）。
  Future<LoginAccount?> currentAccount();

  /// 退出登录（清本地会话）。
  Future<void> logout();
}

/// 扫码会话。[payload] 是平台私有数据（如网易的 chainId），UI 不解读。
class LoginQrSession {
  const LoginQrSession({
    required this.id,
    required this.qrContent,
    this.payload,
  });

  /// 会话标识（网易即 unikey）。
  final String id;

  /// 二维码要编码的内容。
  final String qrContent;

  /// 平台私有数据，轮询时原样带回。
  final Object? payload;
}

/// 扫码状态（800 过期 / 801 待扫 / 802 待确认 / 803 成功 的统一映射）。
enum LoginQrStatus { expired, waiting, scanned, confirmed, unknown }

class LoginQrPoll {
  const LoginQrPoll({required this.status, this.message = ''});

  final LoginQrStatus status;
  final String message;

  bool get isConfirmed => status == LoginQrStatus.confirmed;
}

/// 登录账号摘要。
class LoginAccount {
  const LoginAccount({
    required this.userId,
    required this.nickname,
    this.avatarUrl = '',
    this.isVip = false,
  });

  final String userId;
  final String nickname;
  final String avatarUrl;
  final bool isVip;
}
