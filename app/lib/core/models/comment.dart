/// 评论模型（跨音源共用；写入侧复用同一批类型）。
///
/// 放在 `core/models` 而不是 repository 文件里，是为了让
/// `core/source/capabilities.dart` 的能力接口能在不反向依赖 data 层的前提下引用。
library;

/// 评论档位：**由各源实现给出**（选项 id + 展示名，首项即默认），见
/// [CommentReadSource.commentSortOptions]。
///
/// 早先这里是 `enum CommentSort { all, hottest, barrage }` —— 硬编码酷狗三档，
/// 表达不了「档位由服务端给出」：网易的档位是响应 `sortTypeList` 里的
/// 推荐 / 热度 / 时间，且**没有弹幕**。故枚举退役，改为各源自报档位、
/// UI 只渲染并原样回传 id（与 `NewAlbumFeedSource.albumRegions` 同构）。
///
/// 酷狗三档的真实语义（**不是同一接口的参数**，是两套接口 + 一个独立评论池）：
/// - `all` = `/mcomment/v1/cmtlist`
/// - `hottest` = `/m.comment.service/r/v1/rank/topliked`（按点赞数）
/// - `barrage` = `/index.php?r=comments/getCommentWithLike` + `code=articulossong`

/// 非歌曲的评论对象：歌单 / 专辑。
///
/// 这两者与歌曲是**三套独立评论池**（`code` 不同），走的是另一组端点
/// （`/m.comment.service/v1/cmtlist`，不是歌曲的 `/mcomment/v1/cmtlist`），
/// 所以不能复用歌曲那套「按 mixsongid 查」的链路。
enum CommentResourceKind {
  /// 歌单（酷狗 `specialid`）。
  playlist,

  /// 专辑（酷狗 `albumid`）。
  album,
}

/// 用户名旁的铭牌 / 身份徽标（如「超级VIP」「学生」「演员」）。
class CommentBadge {
  const CommentBadge({required this.kind, required this.label});

  /// 机器可读类型（`svip` / `concept` / `vip` / `music` / `student` …），UI 据此配色。
  final String kind;

  /// 展示文案（「超级VIP」「音乐包」「学生」…）。
  final String label;
}

/// 分类 / 热词筛选项（评论区 chips）。
class CommentFilterOption {
  const CommentFilterOption({
    required this.id,
    required this.label,
    this.count = 0,
  });

  /// 分类 = `classify_list[].id`；热词 = 词本身（原样回传给 `hot_word`）。
  final String id;
  final String label;

  /// 该筛选下的评论条数（0 = 接口未给）。
  final int count;
}

/// 一条评论（楼层回复共用同一模型）。
class Comment {
  const Comment({
    required this.id,
    required this.user,
    required this.content,
    this.userId = '',
    this.likeCount = 0,
    this.avatarUrl = '',
    this.timeLabel = '',
    this.replyCount = 0,
    this.location = '',
    this.badges = const [],
    this.talentIcon = '',
  });

  final String id;
  final String user;

  /// 评论作者 userid（空 = 接口未给）。
  final String userId;
  final String content;
  final int likeCount;
  final String avatarUrl;
  final String timeLabel;

  /// 楼层回复数（`reply_num`；0 = 无回复或接口未给）。
  final int replyCount;

  /// IP 属地（如「山东」；空 = 接口未给）。
  final String location;

  /// 用户名旁的铭牌 / 身份徽标。
  final List<CommentBadge> badges;

  /// 头像角标（达人 / 演唱者）URL；空 = 无。
  final String talentIcon;

  bool get hasReplies => replyCount > 0;
}

/// 一页评论 + 该曲的评论池与筛选项。
class CommentPage {
  const CommentPage({
    this.items = const [],
    this.total = 0,
    this.childrenId = '',
    this.maxPage = 0,
    this.classifyList = const [],
    this.hotwordList = const [],
    this.nextCursor = '',
  });

  final List<Comment> items;

  /// 服务端给出的评论总数（`count`）。
  final int total;

  /// 评论池 id（`childrenid`）——**楼层、最热、弹幕都靠它**，
  /// 它既不是 mixsongid 也不是 hash，只能从评论列表响应里取。
  final String childrenId;

  /// 服务端分页上限（`maxPage`）；0 = 未给。
  final int maxPage;

  /// 分类筛选项（`classify_list`，仅 `cmtlist` 首屏带）。
  final List<CommentFilterOption> classifyList;

  /// 热词筛选项（`hot_word_list`，仅 `cmtlist` 首屏带）。
  final List<CommentFilterOption> hotwordList;

  /// 下一页游标（**对 UI 不透明**）；空串 = 没有下一页。
  ///
  /// 分页有两种形态，差异收在各源实现里：
  /// - 酷狗 = **页码式**（`page` + [maxPage]），本字段恒空；
  /// - 网易 = **游标式**，且三档 cursor 构造各不相同（推荐档是数字 offset、
  ///   热度档是 `normalHot#<offset>`、时间档是**上一页末条的 `time`**）。
  ///   时间档的游标依赖上一页的 items，所以只能由实现在映射时算好塞这里，
  ///   UI 翻页时原样回传给 [CommentReadSource.songComments] 的 `cursor`。
  final String nextCursor;

  static const empty = CommentPage();

  bool get isEmpty => items.isEmpty;
}
