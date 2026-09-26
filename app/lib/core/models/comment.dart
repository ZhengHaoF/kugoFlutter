/// 评论模型（跨音源共用；写入侧将来复用同一批类型）。
///
/// 放在 `core/models` 而不是 repository 文件里，是为了让
/// `core/source/capabilities.dart` 的能力接口能在不反向依赖 data 层的前提下引用。
library;

/// 评论排序口径。
///
/// 酷狗**没有**「sort 参数」这种开关：实测 `sort` / `sort_type` / `sort_method` /
/// `order` / `orderby` / `hot` / `new` / `type` … 全部被服务端忽略（响应逐条相同）。
/// 真正的排序是 `cmtlist` 响应里 `tag[]` 页签给出的**两个不同接口**。
enum CommentSort {
  /// 默认排序（`/mcomment/v1/cmtlist`）。
  all,

  /// 最热（`/m.comment.service/r/v1/rank/topliked`，按点赞数）。
  hottest,
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

  bool get hasReplies => replyCount > 0;
}

/// 一页评论 + 该曲的评论池信息。
class CommentPage {
  const CommentPage({
    this.items = const [],
    this.total = 0,
    this.childrenId = '',
    this.maxPage = 0,
  });

  final List<Comment> items;

  /// 服务端给出的评论总数（`count`）。
  final int total;

  /// 评论池 id（`childrenid`）——**楼层与「最热」都靠它**，
  /// 它既不是 mixsongid 也不是 hash，只能从评论列表响应里取。
  final String childrenId;

  /// 服务端分页上限（`maxPage`）；0 = 未给。
  final int maxPage;

  static const empty = CommentPage();

  bool get isEmpty => items.isEmpty;
}
