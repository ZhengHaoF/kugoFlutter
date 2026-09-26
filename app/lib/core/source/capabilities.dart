import '../models/audio_quality.dart';
import '../models/catalog_models.dart';
import '../models/comment.dart';
import '../models/daily_recommend.dart';
import '../models/fm_mode.dart';
import '../models/search_result.dart';
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
  /// 拉取今日推荐。各源差异（酷狗 `/top/ip` 公开兜底、网易 G3 日推）收口到
  /// [DailyRecommendResult] 的 tracks/personalized/needLogin/error 四字段。
  Future<DailyRecommendResult> dailyRecommend();
}

/// 榜单。
abstract interface class RankSource {
  /// 榜单列表。统一返回 [PlaylistBrief]（含 `isRank`/`platform`/`rankTypeName`），
  /// 供榜单列表页编排与详情页换榜弹窗复用。
  Future<List<PlaylistBrief>> rankBoards();

  Future<List<Track>> rankTracks(String boardId, {int page = 1});
}

/// 歌单分类发现（探索发现「歌单」Tab）。
///
/// 标签层级差异收口在实现里：酷狗二级 group 原样返回，网易一级扁平拍成单组，
/// UI 只认 [PlaylistTagGroup] 并渲染同一行 chips。
abstract interface class PlaylistCatalogSource {
  /// 分类标签。返回空 = 该源分类接口无数据（UI 出空态 + 默认分类）。
  Future<List<PlaylistTagGroup>> playlistTagGroups();

  /// 按分类取歌单。
  ///
  /// [cat] 是**各源原生分类值**（酷狗 `categoryid` / 网易中文标签名），由 UI
  /// 原样回传 [PlaylistTag.id]；空串 = 用该源自己的默认分类。
  Future<List<PlaylistBrief>> categoryPlaylists({
    required String cat,
    int pageSize = 30,
  });
}

/// 推荐新歌（探索发现「新歌速递」Tab）。
///
/// 网易侧是「推荐新歌」口径（无地区分类），酷狗侧是新歌速递单口 —— 差异在实现里，
/// UI 只拿曲目列表。
abstract interface class NewSongFeedSource {
  Future<List<Track>> newSongs({int pageSize = 30});
}

/// 新碟上架（探索发现「新碟上架」Tab）。
///
/// 地区分片各源不同（酷狗 `all/chn/eur/jpn/kor`、网易 `ALL/ZH/EA/KR/JP`），
/// 故选项由实现给出，UI 只按顺序渲染 chips、把 [region] 原样回传。
abstract interface class NewAlbumFeedSource {
  /// 地区分片（各源原生值，**首项即默认**）。
  List<({String id, String label})> get albumRegions;

  Future<List<AlbumBrief>> newAlbums({
    required String region,
    int pageSize = 30,
  });
}

/// 歌手列表（探索发现「歌手」Tab）。
///
/// 筛选维度各源不同（酷狗：性别 + 流派 + 响应分组字母；网易：性别 + 地区 + 首字母），
/// 故选项一律由实现给出，UI 只按顺序渲染 chips 行、把选中的 id 原样回传。
/// 某维度返回空列表 = 该源无此项，UI 隐藏该行。
abstract interface class ArtistListSource {
  /// 性别分片（首项即默认）。
  List<({String id, String label})> get artistGenderOptions;

  /// 地区 / 流派分片（首项即默认）。
  List<({String id, String label})> get artistStyleOptions;

  /// 首字母分片（首项即默认 = 不筛）。
  ///
  /// 酷狗无字母入参，其字母来自**上次响应**的分组标题（调过 [artistList] 后才有值，
  /// 由实现内部按响应回填）；网易则直接是 `initial` 入参（服务端筛选）。
  List<({String id, String label})> get artistInitialOptions;

  Future<List<ArtistBrief>> artistList({
    required String gender,
    required String style,
    required String initial,
    int pageSize = 30,
  });
}

/// 推荐聚合（「为你推荐」页的「推荐歌单」「编辑精选」两块）。
///
/// 酷狗侧：`special_recommend`（`categoryid=0`）+ `musicadservice/top_ip`；
/// 网易侧：G1 个性推荐歌单 + G7a 精品歌单。榜单 / 新歌 / 每日推荐另有契约。
abstract interface class RecommendFeedSource {
  /// 推荐歌单（算法/个性化）。
  ///
  /// [cat] 是**各源原生推荐分类值**（酷狗 `categoryid`）；空串 = 该源默认推荐。
  /// 网易个性推荐歌单没有分类维度，实现忽略 [cat]。
  Future<List<PlaylistBrief>> recommendPlaylists({
    String cat = '',
    int pageSize = 12,
  });

  /// 编辑精选（人工精选歌单）。
  Future<List<PlaylistBrief>> editorialPlaylists({int pageSize = 12});
}

/// 歌单详情（非榜单；榜单走 [RankSource]）。
///
/// 返回 null = 接口无数据（酷狗公开歌单缺失）；实现也可抛异常（网易）。
/// 深链路由 `/playlist/:id?src=<wire>` 按源分发到此。
abstract interface class PlaylistDetailSource {
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylistDetail(
    String id,
  );
}

/// 专辑详情。深链 `/album/:id?src=<wire>` 按源分发到此。
abstract interface class AlbumDetailSource {
  Future<AlbumDetail?> fetchAlbumDetail(String albumId);
}

/// 歌手详情 + 歌曲分页。深链 `/artist/:id?src=<wire>` 按源分发到此。
abstract interface class ArtistDetailSource {
  Future<ArtistDetail?> fetchArtistDetail(String artistId);

  /// 网易侧 [ArtistSongSort.newest] 映射 `order=new`（按发行时间倒序）。
  Future<ArtistSongsPage> fetchArtistSongsPage(
    String artistId, {
    int page = 1,
    int pageSize = 30,
    ArtistSongSort sort = ArtistSongSort.hot,
  });
}

/// 可播音质目录（酷狗 relate_goods）。无此能力则跳过懒加载。
abstract interface class QualityCatalogSource {
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchQualityCatalog(
    Track track,
  );
}

/// 评论**读**侧（写侧另立接口：需要登录且可能触发风控）。
///
/// 各源差异（酷狗的「排序 = 两个不同接口」、网易的 `R_SO_4_` 口径）收口在实现里，
/// UI 只认 [CommentSort] 与 [CommentPage]。
abstract interface class CommentReadSource {
  /// 最近一次失败的**用户可读**原因；成功时为空串。
  ///
  /// 读接口以「返回空 + 原因」而不是抛异常收口（与既有 repository 一致），
  /// 所以原因要能从能力面上取到，UI 不必回头去碰 repository。
  String get lastError;

  /// 歌曲评论分页。[mixSongId] 是平台的歌曲 id（酷狗 = mixsongid）。
  ///
  /// 返回的 [CommentPage.childrenId] 是评论池 id，调 [floorReplies] 时要原样回传。
  Future<CommentPage> songComments(
    String mixSongId, {
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  });

  /// 主评论下的楼层回复。
  Future<List<Comment>> floorReplies({
    required String childrenId,
    required String rootCommentId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 20,
  });

  /// 评论总数（入参是音频 hash，与列表 `count` 同口径）；null = 无数据。
  Future<int?> commentCount(String hash);
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

/// 用户云端歌单**读取**（自建 / 收藏，不含曲目）。
///
/// 酷狗侧仍走既有 `user_repository` 链路（带 fileid 等酷狗口径）；
/// 网易侧由本能力提供，UI 用 `registry.capability<UserPlaylistReadSource>()` 取。
abstract interface class UserPlaylistReadSource {
  /// 拉取用户歌单（一次给全量；`more` 为真表示还有下一页）。
  Future<UserPlaylistsPage> userPlaylists({int offset = 0, int limit = 1000});
}

/// 用户歌单读取结果。
class UserPlaylistsPage {
  const UserPlaylistsPage({
    this.created = const [],
    this.collected = const [],
    this.more = false,
  });

  /// 自建（含「我喜欢的音乐」这类默认单）。
  final List<PlaylistBrief> created;

  /// 收藏（他人歌单）。
  final List<PlaylistBrief> collected;

  /// 是否还有下一页。
  final bool more;
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
