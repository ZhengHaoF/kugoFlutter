import 'package:flutter/material.dart';

import '../../core/api/mappers.dart' show formatCount;
import '../../core/models/comment.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import 'cover_box.dart';

/// 评论条（歌曲 / 歌单 / 专辑三处评论区共用）。
///
/// 楼层展开与「回复」都是**可选能力**：传了回调才显示对应入口，
/// 不传就只渲染纯展示的一条评论 —— 精彩评论块就是这么用的。
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.expanded = false,
    this.loadingFloor = false,
    this.replies = const [],
    this.onToggleReplies,
    this.onReply,
  });

  final Comment comment;
  final bool expanded;
  final bool loadingFloor;
  final List<Comment> replies;

  /// 非空才显示「N 条回复」入口（无回复的评论不给入口，避免点了空展开）。
  final VoidCallback? onToggleReplies;

  /// 非空才显示「回复」入口。
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KugoSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CoverBox(
                seed: comment.avatarUrl.isEmpty
                    ? 'avatar-${comment.user}'
                    : comment.avatarUrl,
                size: 36,
                radius: 999,
                child: const Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
              ),
              // 达人 / 演唱者角标（`vinfo9.pic`），叠在头像右下角。
              if (comment.talentIcon.isNotEmpty)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: CoverBox(
                    seed: comment.talentIcon,
                    size: 14,
                    radius: 999,
                    child: const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              comment.user,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: kugo.caption.copyWith(
                                color: kugo.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (comment.badges.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            for (final b in comment.badges.take(2))
                              CommentBadgeChip(badge: b),
                          ],
                        ],
                      ),
                    ),
                    if (comment.timeLabel.isNotEmpty)
                      Text(comment.timeLabel, style: kugo.caption),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: kugo.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up_off_alt_rounded,
                      size: 14,
                      color: kugo.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatCount(comment.likeCount),
                      style: kugo.caption.copyWith(color: kugo.textTertiary),
                    ),
                    if (comment.location.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        comment.location,
                        style: kugo.caption.copyWith(color: kugo.textTertiary),
                      ),
                    ],
                    if (onToggleReplies != null) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: loadingFloor ? null : onToggleReplies,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            loadingFloor
                                ? '加载中…'
                                : '${formatCount(comment.replyCount)}条回复',
                            style: kugo.caption.copyWith(color: kugo.primary),
                          ),
                        ),
                      ),
                    ],
                    if (onReply != null) ...[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: onReply,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '回复',
                            style: kugo.caption.copyWith(color: kugo.primary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: KugoSpacing.sm),
                  if (replies.isEmpty)
                    Text(
                      loadingFloor ? '加载中…' : '暂无回复',
                      style: kugo.caption.copyWith(color: kugo.textTertiary),
                    )
                  else
                    for (final r in replies) FloorReplyTile(reply: r),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 楼层回复：缩进 + 更小的头像/字号。
class FloorReplyTile extends StatelessWidget {
  const FloorReplyTile({super.key, required this.reply});

  final Comment reply;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: KugoSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverBox(
            seed: reply.avatarUrl.isEmpty
                ? 'avatar-${reply.user}'
                : reply.avatarUrl,
            size: 26,
            radius: 999,
            child: const Icon(
              Icons.person_rounded,
              size: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reply.user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(
                          color: kugo.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (reply.timeLabel.isNotEmpty)
                      Text(reply.timeLabel, style: kugo.caption),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  reply.content,
                  style: kugo.body.copyWith(fontSize: 13, height: 1.4),
                ),
                if (reply.likeCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.thumb_up_off_alt_rounded,
                        size: 12,
                        color: kugo.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatCount(reply.likeCount),
                        style: kugo.caption.copyWith(color: kugo.textTertiary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 铭牌 chip：VIP 类用主色，身份类（学生/演员/认证/明星）用中性色。
class CommentBadgeChip extends StatelessWidget {
  const CommentBadgeChip({super.key, required this.badge});

  final CommentBadge badge;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    const identityKinds = {'student', 'actor', 'biz', 'tme-star', 'auth'};
    final isVip = !identityKinds.contains(badge.kind);
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isVip
            ? kugo.primary.withValues(alpha: 0.14)
            : kugo.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isVip ? kugo.primary : kugo.divider),
      ),
      child: Text(
        badge.label,
        style: kugo.caption.copyWith(
          fontSize: 10,
          height: 1.3,
          color: isVip ? kugo.primary : kugo.textSecondary,
        ),
      ),
    );
  }
}
