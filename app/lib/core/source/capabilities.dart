import '../models/audio_quality.dart';
import '../models/barrage.dart';
import '../models/catalog_models.dart';
import '../models/cloud_models.dart';
import '../models/comment.dart';
import '../models/daily_recommend.dart';
import '../models/fm_mode.dart';
import '../models/mv_models.dart';
import '../models/search_result.dart';
import '../models/style_recommend.dart';
import '../models/track.dart';
import 'music_source.dart';

/// 可选能力接口：谁有谁 `implements`。UI 用 `registry.capability<T>()` 显隐，
/// 禁止在基类堆 `bool get hasXxx` + 空实现。

/// 私人 FM（酷狗红心 Radio / 网易私人 FM 的共同子集）。
abstract interface class PersonalFmSource {
  /// 拉取下一批 FM 曲目。
  ///
  /// [unplayed] 当前队列尚未播放数量；[fresh] = 开新会话。
  /// **协议参数由实现映射**（酷狗 `remain_songcnt` 且上限 4；网易忽略）——
  /// 调用方只报语义，不得传协议值。
  Future<List<Track>> nextFmTracks({int unplayed = 0, bool fresh = false});

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

/// 酷狗「风格推荐」歌曲流（`everyday_style_recommend`）。
///
/// 无此能力的源把「风格」退化为 [PlaylistCatalogSource] 风格歌单——
/// UI 用 `capability<StyleStreamSource>()` 判形态，不写 `platform == kugou`。
abstract interface class StyleStreamSource {
  /// 风格标签 + 歌曲。[tagIds] 为各源原生标签 id 逗号串，空串 = 默认推荐。
  Future<StyleRecommendResult> fetchStyleRecommend({
    String tagIds = '',
    int limit = 30,
  });
}

/// 歌单详情（含榜单交叉 fallback；换榜列表走 [RankSource]）。
///
/// 返回 null = 接口无数据（酷狗公开歌单缺失）；实现也可抛异常（网易）。
/// 深链路由 `/playlist/:id?src=<wire>` 按源分发到此。
///
/// **账号态路径也归实现**：酷狗用户自建/收藏（userId + token + fileid/listid）
/// 的识别与取曲只出现在 `KugouSource` 内，页面不得直连 `UserRepository`。
abstract interface class PlaylistDetailSource {
  /// 取歌单/榜单详情。
  ///
  /// [briefHint] 列表点击带来的 brief（识别用户单、封面兜底）；可空。
  /// [preferRank] 榜单视图优先走榜单接口；实现内再做 榜单 ↔ 歌单 交叉 fallback。
  ///
  /// 返回的 [PlaylistBrief.isRank] 标明**实际取到**的数据形态
  /// （交叉 fallback 时可能与 [preferRank] 相反）。
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylistDetail(
    String id, {
    PlaylistBrief? briefHint,
    bool preferRank = false,
  });
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
/// **入参一律是 [Track]，不是平台 id**：各源自己决定拿 track 的哪个字段去查
/// （酷狗要 `album_audio_id` 且可能需回搜解析、网易是 `R_SO_4_<songId>`），
/// 这就是「源差异收口在实现里」——UI 不该替某个源做 id 计算。
/// UI 只认 [Track] / 档位 id 字符串 / [CommentPage]。
abstract interface class CommentReadSource {
  /// 最近一次失败的**用户可读**原因；成功时为空串。
  ///
  /// 读接口以「返回空 + 原因」而不是抛异常收口（与既有 repository 一致），
  /// 所以原因要能从能力面上取到，UI 不必回头去碰 repository。
  String get lastError;

  /// 评论档位（**首项即默认**）：`(id, label)`，UI 只按顺序渲染并原样回传 id。
  ///
  /// 为什么不硬编码枚举：酷狗是「两个接口 + 一个弹幕池」的路由语义，网易是
  /// 同一接口换 `sortType`、档位由响应 `sortTypeList` 给出（推荐/热度/时间），
  /// 枚举表达不了「档位由实现给出」。与 `NewAlbumFeedSource.albumRegions` 同构。
  List<({String id, String label})> get commentSortOptions;

  /// 歌曲评论分页。
  ///
  /// [sort] 是 [commentSortOptions] 里的 id（空串 = 用默认档）；
  /// [cursor] 是上一次返回的 [CommentPage.nextCursor]（**不透明**，页码式源忽略它）。
  ///
  /// 返回的 [CommentPage.childrenId] 是**该源的评论池 token**（酷狗 = `childrenid`，
  /// 既不是歌曲 id 也不是 hash）：调 [floorReplies] /
  /// [CommentExtrasSource.featuredComments] / [CommentWriteSource] 时原样回传即可，
  /// UI 不解读它的含义。
  Future<CommentPage> songComments(
    Track track, {
    int page = 1,
    int pageSize = 20,
    String sort = '',
    String cursor = '',
  });

  /// 主评论下的楼层回复。[childrenId] 取自 [CommentPage.childrenId]。
  Future<List<Comment>> floorReplies({
    required Track track,
    required String childrenId,
    required String rootCommentId,
    int page = 1,
    int pageSize = 20,
  });

  /// 评论总数；null = 该源未提供（UI 显示「—」，**不要编数字**）。
  Future<int?> commentCount(Track track);
}

/// 评论列表的**增强能力**（分类 / 热词 / 精彩评论）——目前**只有酷狗有**。
///
/// 为什么单独成接口：这三项网易一个都没有（无分类、无热词、无「精彩评论」口），
/// 若留在 [CommentReadSource] 上，网易就得写三个空实现 —— 与文件开头那句
/// 「谁有谁 `implements`，禁止基类堆 `bool hasXxx` + 空实现」直接冲突。
/// 拆出来后 **网易不 implements，UI 自动不出 chips 行与精彩评论块**。
///
/// 失败文案复用 [CommentReadSource.lastError]（酷狗侧本来就是同一份状态）。
abstract interface class CommentExtrasSource {
  /// 分类评论。[typeId] 取自 [CommentPage.classifyList]。
  Future<CommentPage> classifyComments(
    Track track, {
    required String typeId,
    int page = 1,
    int pageSize = 20,
  });

  /// 热词评论。[hotWord] 取自 [CommentPage.hotwordList]。
  Future<CommentPage> hotwordComments(
    Track track, {
    required String hotWord,
    int page = 1,
    int pageSize = 20,
  });

  /// 精彩评论（[childrenId] 同 [CommentReadSource.floorReplies]）。
  /// **空列表是正常结果**（游客态拿不到），UI 据此隐藏该区块。
  Future<List<Comment>> featuredComments({
    required Track track,
    required String childrenId,
    int page = 1,
    int pageSize = 10,
  });
}

/// 歌单 / 专辑评论的**读**侧（写侧另立 [ResourceCommentWriteSource]）。
///
/// 入参是**资源 id**（歌单 specialid / 专辑 albumid），与 [CommentReadSource]
/// 的 [Track] 入参不是一回事 —— 所以单独成接口，不往歌曲那条链路里塞分支。
///
/// 实现差异（酷狗）收在实现里：端点走 B 组 `/m.comment.service/v1/cmtlist`，
/// 靠 `code` 区分歌单池 / 专辑池；网易则是 `A_PL_0_` / `R_AL_3_` 前缀的 threadId。
/// UI 只认 [CommentResourceKind] + 资源 id。
///
/// 读 / 写拆开与 [CommentReadSource] / [CommentWriteSource] 同因：写侧**要登录**
/// 且可能触发风控，而读侧游客态就能拉。网易目前只有读侧（写侧留到 N2）。
abstract interface class ResourceCommentSource {
  /// 最近一次失败的**用户可读**原因；成功时为空串。
  String get resourceCommentError;

  /// 歌单 / 专辑评论分页。
  ///
  /// [cursor] 同 [CommentReadSource.songComments]：游标式源（网易）靠它翻页，
  /// 页码式源（酷狗）忽略。
  ///
  /// 返回的 [CommentPage.childrenId] 是评论池 token，楼层与写侧原样回传。
  Future<CommentPage> resourceComments(
    CommentResourceKind kind, {
    required String resourceId,
    int page = 1,
    int pageSize = 20,
    String cursor = '',
  });

  /// 主评论下的楼层回复。[childrenId] 取自 [resourceComments] 的返回值。
  Future<List<Comment>> resourceFloorReplies(
    CommentResourceKind kind, {
    required String childrenId,
    required String rootCommentId,
    int page = 1,
    int pageSize = 20,
  });

  /// 评论总数；null = 该源未提供（UI 显示「—」）。
  Future<int?> resourceCommentCount(
    CommentResourceKind kind,
    String resourceId,
  );

}

/// 歌单 / 专辑评论的**写**侧：发评论 / 回复楼层。
///
/// 与读侧（[ResourceCommentSource]）拆开的原因同 [CommentWriteSource]：
/// **要登录** + **可能触发风控**。目前只有酷狗实现，**网易不 implements**
/// ⇒ 歌单 / 专辑页的「说点什么…」与「回复」入口对网易自动隐藏，
/// 而不是渲染出来、点了才提示不支持。
abstract interface class ResourceCommentWriteSource {
  /// 该源当前是否已登录（同 [CommentWriteSource.isLoggedIn]：登录态判断归实现）。
  bool get isLoggedIn;

  /// 发歌单 / 专辑评论。失败抛 [SourceFailure]（与 [CommentWriteSource] 一致）。
  Future<void> sendResourceComment(
    CommentResourceKind kind, {
    required String childrenId,
    required String content,
    String resourceName = '',
  });

  /// 回复歌单 / 专辑下某条主评论（楼层）。
  ///
  /// [replyToUser] / [replyToContent] 非空时，实现按上游约定把正文拼成
  /// `//@昵称:被回复内容` 的引用格式再提交。
  Future<void> sendResourceFloorReply(
    CommentResourceKind kind, {
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
    String resourceName = '',
  });
}

/// 评论**写**侧：发评论 / 回复楼层。
///
/// 与读侧拆开是因为写侧的两个硬约束：**要登录**、**可能触发风控（SSA）**。
/// 失败一律抛 [SourceFailure]（与 [UserPlaylistWriteSource] 一致），UI 捕获后展示可读文案。
abstract interface class CommentWriteSource {
  /// 该源**当前是否已登录** —— 登录态判断也归实现，UI 不许自己判。
  ///
  /// 两个源的凭据完全不是一回事：酷狗是 `AuthTokenHolder` 里的 token，
  /// 网易是 `MUSIC_U` cookie。早先 UI 统一看酷狗 token，导致**网易已扫码登录、
  /// 酷狗没登录时照样提示「登录后才能发表评论」并跳酷狗登录页** —— 就是这个
  /// 字段缺失造成的。
  bool get isLoggedIn;

  /// 发表歌曲评论。[childrenId] 取自 [CommentPage.childrenId]；歌名由实现从
  /// [track] 取（上游 `childrenname` 用），UI 不必单独传。
  Future<void> sendSongComment({
    required Track track,
    required String childrenId,
    required String content,
  });

  /// 回复某条主评论（楼层）。
  ///
  /// [replyToUser] / [replyToContent] 非空时，实现按上游约定把正文拼成
  /// `//@昵称:被回复内容` 的引用格式再提交。
  Future<void> sendFloorReply({
    required Track track,
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
  });
}

/// 评论**点赞** / 取消赞 —— 目前**只有网易有**（酷狗没有这个能力）。
///
/// 单独成接口（而不是塞进 [CommentWriteSource]）的原因同 [CommentExtrasSource]：
/// 酷狗没有点赞口，塞进去就得写空实现。UI 用 `registry.capability<...>()`
/// 取不到就**不渲染赞按钮**，而不是渲染出来点了才提示不支持。
abstract interface class CommentLikeSource {
  /// [childrenId] 取自 [CommentPage.childrenId]（网易即 `threadId`），
  /// [commentId] 是评论 id；[like] 为 false = 取消赞。
  ///
  /// 失败抛 [SourceFailure]；**UI 做乐观更新**，失败要能回滚。
  Future<void> setCommentLiked({
    required String childrenId,
    required String commentId,
    required bool like,
  });
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
/// 两源都经本能力取数，UI 用 `registry.capability<UserLibrarySource>()`，
/// 不再区分 `userCollectionsProvider` / `neteaseLikesProvider` 双栈。
abstract interface class UserLibrarySource {
  /// 拉取云端「我喜欢」全部曲目（翻页/分批由实现内部处理）。
  Future<List<Track>> likedTracks();
}

/// 用户云端「我喜欢」写操作（红心 / 取消红心）。
///
/// 与 [UserPlaylistWriteSource] 分开：红心是平台语义（网易 F4 likeSong /
/// 酷狗写默认喜欢单），不是任意歌单加曲。UI 红心只调本接口。
abstract interface class UserLikedWriteSource {
  /// 该源当前是否已登录（登录态判断归实现）。
  bool get isLoggedIn;

  /// 设置红心状态。失败抛 [SourceFailure]。
  Future<void> setTrackLiked(Track track, {required bool liked});
}

/// 用户云端歌单**读取**（自建 / 收藏 / 收藏专辑 / 关注歌手）。
///
/// 两源都经本能力取数；没有的字段返回空列表（网易暂无专辑收藏/关注歌手）。
abstract interface class UserPlaylistReadSource {
  /// 拉取用户歌单（一次给全量；`more` 为真表示还有下一页）。
  Future<UserPlaylistsPage> userPlaylists({int offset = 0, int limit = 1000});
}

/// 用户资料库读取结果（歌单 + 收藏专辑 + 关注歌手）。
class UserPlaylistsPage {
  const UserPlaylistsPage({
    this.created = const [],
    this.collected = const [],
    this.favoritedAlbums = const [],
    this.followedArtists = const [],
    this.more = false,
  });

  /// 自建（含「我喜欢的音乐」这类默认单）。
  final List<PlaylistBrief> created;

  /// 收藏（他人歌单）。
  final List<PlaylistBrief> collected;

  /// 收藏专辑（酷狗 `source==2`；网易暂无则空）。
  final List<AlbumBrief> favoritedAlbums;

  /// 关注歌手（酷狗 follow；网易暂无则空）。
  final List<ArtistBrief> followedArtists;

  /// 是否还有下一页。
  final bool more;

  /// 云端「我喜欢」歌单（见 [findLikedPlaylist]）。
  PlaylistBrief? get likedPlaylist => findLikedPlaylist([...created, ...collected]);
}

/// 从用户歌单里定位云端「我喜欢」。
///
/// 顺序对齐 EchoMusic 的 `findLikedPlaylist`
/// （`EchoMusic/src/renderer/stores/playlist/helpers.ts`），并补了一条酷狗
/// 实测必需约束：
/// 酷狗 `/v7/get_all_list` 会同时把「默认收藏」(`is_def=1`，空单) 与
/// 「我喜欢」(`is_def=2`) 标成默认单，且前者排在前面。若直接取第一个
/// `isDefault` 就会命中空的「默认收藏」，表现为「我的红心歌曲不见了」。
/// 故先按名字定位，`isDefault` 兜底时排除「默认收藏」这个占位单。
///
/// 多级顺序：精确名 → 精确名 → 默认单（排除「默认收藏」）→ 名字含「喜欢」
/// → 收藏/默认兜底 → 精确「默认收藏」。
PlaylistBrief? findLikedPlaylist(Iterable<PlaylistBrief> playlists) {
  final all = playlists.toList(growable: false);

  PlaylistBrief? byName(String exact) {
    for (final p in all) {
      if (p.name.trim() == exact) return p;
    }
    return null;
  }

  PlaylistBrief? byNameContains(String part) {
    for (final p in all) {
      if (p.name.trim().contains(part)) return p;
    }
    return null;
  }

  PlaylistBrief? firstWhere(bool Function(PlaylistBrief) test) {
    for (final p in all) {
      if (test(p)) return p;
    }
    return null;
  }

  return byName('我喜欢的音乐') ??
      byName('我喜欢') ??
      firstWhere((p) => p.isDefault && p.name.trim() != '默认收藏') ??
      byNameContains('喜欢') ??
      firstWhere((p) => p.type == 1 || p.isDefault) ??
      byName('默认收藏');
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

/// MV 搜索 + 从歌曲找关联 MV。
///
/// 与 [MusicSource.searchSongs] 同构：分页返回统一 Brief，`total` 可空。
/// 入参 [Track] 而不是平台 id（同 [CommentReadSource] 的理由）。
abstract interface class MvSearchSource {
  /// 关键词搜 MV。
  Future<SearchPageResult<MvBrief>> searchMvs(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  });

  /// 歌曲关联的 MV 列表（多版本：官方/现场/饭制…）。
  ///
  /// 返回空列表 = 该曲无 MV（正常结果，UI 出空态）。
  Future<List<MvBrief>> songMvs(Track track);

  /// 歌手 MV 列表。[tag] 见实现注释（`''` 全部 / `18` 官方…）。
  Future<SearchPageResult<MvBrief>> fetchArtistMvs(
    String authorId, {
    int page = 1,
    int pageSize = 30,
    String tag = '',
  });
}

/// MV 详情 + 取流。UI 只认 [MvDetail] / [MvPlayUrlResult]。
abstract interface class MvDetailSource {
  /// 详情 + 多清晰度片源（按清到糊排序）。
  ///
  /// 返回 null = 接口无数据；失败抛 [SourceFailure]。
  Future<MvDetail?> fetchMvDetail(MvBrief brief);

  /// 用某档片源的 [MvPlaySource.hash] 取短时播放地址。
  ///
  /// [hash] 传 [MvDetail.defaultSource] 或用户选中的那档；不要传歌曲 `mvhash`。
  Future<MvPlayUrlResult> resolveMvPlayUrl(String hash);
}

/// MV 收藏（登录态）。id 必须是数字 video_id（[normalizeMvCollectId]）。
abstract interface class MvCollectSource {
  Future<void> setMvCollected(String videoId, {required bool collected});
  Future<Set<String>> fetchCollectedMvIds();
}

/// MV 弹幕（读 + 写）。
///
/// 与歌曲评论里的「弹幕档位」**不是一回事**：那是评论列表的一个排序池，
/// 这里是叠在视频上的飞行弹幕层，按 **MV 主 hash** 分池
/// （对齐 EchoMusic MvDetail 的 `/video/barrage`）。
///
/// 只有实现了本能力的源才出弹幕开关与渲染层；未实现的源（如网易）
/// UI 自动隐藏入口，而不是渲染出来点了才提示不支持。
abstract interface class MvBarrageSource {
  /// 最近一次拉取失败的**用户可读**原因；成功时为空串（读侧不抛异常）。
  String get barrageError;

  /// 拉取某 MV 的弹幕（按 [hash] 分池）。
  ///
  /// 返回空列表 = 暂无弹幕 / 失败（失败原因见 [barrageError]），
  /// 对 UI 都是「空态」，不区分。
  Future<List<BarrageItem>> fetchMvBarrage(
    String hash, {
    int page = 1,
    int pageSize = 100,
  });

  /// 发送一条弹幕（登录态）。
  ///
  /// 只给 [hash] 时由实现先解析弹幕池（上游只认 video_id）；已知 [videoId]
  /// 可直接传入省一次请求。[name] 即 `childrenname`（MV 标题）。
  /// 失败抛 [SourceFailure]。
  Future<void> sendMvBarrage({
    required String hash,
    required String content,
    String name = '',
    String videoId = '',
  });
}

/// 音乐云盘（用户上传到云端的私有文件）。
///
/// **双源都实现了**：酷狗（`CloudRepository`）与网易（J 组，2026-10-09 接，
/// 协议面对齐 api-enhanced `module/user_cloud*.js` / `cloud*.js`）。UI 用
/// `registry.capability<CloudDiskSource>()` 显隐，不写 `platform == kugou`。
///
/// 一期只读：列表 / 播放 / 删除。上传见二期 [CloudUploadSource]。
/// 协议对照见 `docs/api-notes.md`「音乐云盘」节。
///
/// 两源身份键不同：酷狗是 `cloudFileId`(kv_id) + `hash` 双键，网易只有
/// songId（`cloudFileId` 即 songId，`hash` 为空）——删除/取流都认
/// [CloudDeleteTarget.cloudFileId]，故契约不用分叉。
abstract interface class CloudDiskSource {
  /// 当前源是否已登录（云盘是登录态资产）。
  bool get isCloudDiskLoggedIn;

  /// 拉取云盘一页。[page] 从 1 开始。
  ///
  /// 未登录抛 [LoginRequired]；网络失败抛 [NetworkFailure]。
  Future<CloudDiskPage> fetchCloudDiskPage({int page = 1, int pageSize = 30});

  /// 解析云盘文件播放地址。
  ///
  /// [track] 须带 [Track.cloudAudioSource] 或 [Track.hash]；
  /// 云盘页曲目直接传列表项即可。失败抛 [SourceFailure]。
  Future<PlayUrlResult> resolveCloudPlayUrl(Track track);

  /// 删除云盘文件。目标须有 `cloudFileId` 或 `hash`（见 [CloudDeleteTarget]）。
  ///
  /// 失败抛 [SourceFailure]；成功后调用方自行刷新列表。
  Future<void> deleteCloudTracks(List<CloudDeleteTarget> targets);
}

/// 二期：上传到云盘。
abstract interface class CloudUploadSource {
  /// 上传单个文件（二进制）。
  ///
  /// [title] 不含扩展名；[extendname] 小写不带点。
  /// 可选 [audioId] / [albumAudioId] 用于关联曲库（缺省时实现内部尝试匹配）。
  /// 返回 [CloudUploadResult]；失败抛 [SourceFailure]。
  Future<CloudUploadResult> uploadCloudFile({
    required List<int> bytes,
    required String title,
    required String extendname,
    String? authorName,
    String? audioId,
    String? albumAudioId,
    void Function(int sent, int total)? onProgress,
  });
}
