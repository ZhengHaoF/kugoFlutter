/// 评论模型（跨音源共用；写入侧复用同一批类型）。
///
/// 放在 `core/models` 而不是 repository 文件里，是为了让
/// `core/source/capabilities.dart` 的能力接口能在不反向依赖 data 层的前提下引用。
library;

/// 评论数据源档位。
///
/// 这三档**不是同一个接口的参数**：
/// - [all] / [hottest] 是 `cmtlist` 响应里 `tag[]` 给出的两个不同接口；
/// - [barrage] 是**另一个评论池**（`code=articulossong`），与评论互不相通。
enum CommentSort {
  /// 全部（`/mcomment/v1/cmtlist`）。
  all,

  /// 最热（`/m.comment.service/r/v1/rank/topliked`，按点赞数）。
  hottest,

  /// 弹幕（`/index.php?r=comments/getCommentWithLike` + `code=articulossong`）。
  barrage,
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

  static const empty = CommentPage();

  bool get isEmpty => items.isEmpty;
}
