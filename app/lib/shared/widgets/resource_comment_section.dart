import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/mappers.dart' show formatCount;
import '../../core/models/comment.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/comment_repository.dart' show CommentRepository;
import '../../features/auth/auth_token_holder.dart';
import 'comment_composer_sheet.dart';
import 'comment_tile.dart';

/// 歌单 / 专辑评论区：自管 loading、分页、楼层与发评论。
///
/// 与歌曲评论区（`song_detail_page`）的差异，也是这里**不做**的事：
/// - 无排序档（歌单 / 专辑评论只有一个列表接口，没有「最热」/「弹幕」）；
/// - 无分类 / 热词 chips（实测这两类响应不带 `classify_list` / `hot_word_list`）；
/// - 无精彩评论块（游客态拿不到，价值不大）。
///
/// 取数走 [ResourceCommentSource] 能力接口，UI 不碰 repository。
class ResourceCommentSection extends StatefulWidget {
  const ResourceCommentSection({
    super.key,
    required this.platform,
    required this.kind,
    required this.resourceId,
    this.resourceName = '',
  });

  final MusicPlatform platform;

  /// 歌单 / 专辑。
  final CommentResourceKind kind;

  /// 歌单 specialid / 专辑 albumid。
  final String resourceId;

  /// 资源名（写口 `childrenname` 用）。
  final String resourceName;

  @override
  State<ResourceCommentSection> createState() => _ResourceCommentSectionState();
}

class _ResourceCommentSectionState extends State<ResourceCommentSection> {
  static const int _pageSize = 20;

  CommentPage _comments = CommentPage.empty;
  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';

  /// 分页游标：与歌曲页同口径 —— **不用「累积条数 ÷ pageSize」推页码**。
  int _loadedPage = 0;
  bool _lastPageFull = false;

  final Map<String, List<Comment>> _floors = {};
  final Set<String> _expanded = {};
  final Set<String> _floorLoading = {};

  ResourceCommentSource? get _source =>
      musicSourceRegistry?.capability<ResourceCommentSource>(widget.platform);

  /// 写侧另取：**没有写侧能力的源（网易）不该渲染写入口** ——
  /// 而不是渲染出来、点了才提示「当前音源不支持评论」。
  ResourceCommentWriteSource? get _writeSource => musicSourceRegistry
      ?.capability<ResourceCommentWriteSource>(widget.platform);

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  /// 两种分页形态：**游标式**（网易，`nextCursor` 非空即还有）优先，
  /// 否则按页码式（酷狗：满页且未到 `maxPage`）。
  bool get _pageHasMore {
    if (_comments.nextCursor.isNotEmpty) return true;
    if (!_lastPageFull) return false;
    final max = _comments.maxPage;
    return max == 0 || _loadedPage < max;
  }

  Future<void> _loadFirst() async {
    final source = _source;
    if (source == null) {
      setState(() {
        _loading = false;
        _error = '当前音源不支持评论';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
      _comments = CommentPage.empty;
      _floors.clear();
      _expanded.clear();
      _floorLoading.clear();
    });

    final page = await source.resourceComments(
      widget.kind,
      resourceId: widget.resourceId,
      page: 1,
      pageSize: _pageSize,
    );
    final err = source.resourceCommentError;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page.items.isEmpty) {
        // 评论为空是常态（很多歌单真的 0 条），给文案而不是错误态。
        _error = err.isEmpty ? '暂无评论' : err;
        _loadedPage = 0;
        _lastPageFull = false;
        return;
      }
      _comments = page;
      _loadedPage = 1;
      _lastPageFull = page.items.length >= _pageSize;
      _error = '';
    });
  }

  Future<void> _loadMore() async {
    final source = _source;
    if (source == null || _loadingMore || !_pageHasMore) return;
    final next = _loadedPage + 1;
    setState(() => _loadingMore = true);
    final page = await source.resourceComments(
      widget.kind,
      resourceId: widget.resourceId,
      page: next,
      pageSize: _pageSize,
      cursor: _comments.nextCursor,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _lastPageFull = page.items.length >= _pageSize;
      if (page.items.isEmpty) return;
      _loadedPage = next;
      _comments = CommentPage(
        items: [..._comments.items, ...page.items],
        total: page.total > 0 ? page.total : _comments.total,
        childrenId: page.childrenId.isNotEmpty
            ? page.childrenId
            : _comments.childrenId,
        maxPage: page.maxPage > 0 ? page.maxPage : _comments.maxPage,
      );
    });
  }

  Future<void> _toggleFloor(Comment root) async {
    final id = root.id;
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    setState(() => _expanded.add(id));
    if (_floors.containsKey(id) || _floorLoading.contains(id)) return;

    final source = _source;
    if (source == null) return;
    setState(() => _floorLoading.add(id));
    final list = await source.resourceFloorReplies(
      widget.kind,
      childrenId: _comments.childrenId,
      rootCommentId: id,
    );
    if (!mounted) return;
    setState(() {
      _floorLoading.remove(id);
      _floors[id] = list;
    });
  }

  /// 回复成功后强制重拉该楼层 —— 楼层已缓存，仅展开看不到新内容。
  Future<void> _reloadFloor(Comment root) async {
    final source = _source;
    if (source == null) return;
    setState(() => _floorLoading.add(root.id));
    final list = await source.resourceFloorReplies(
      widget.kind,
      childrenId: _comments.childrenId,
      rootCommentId: root.id,
    );
    if (!mounted) return;
    setState(() {
      _floorLoading.remove(root.id);
      _floors[root.id] = list;
      _expanded.add(root.id);
    });
  }

  bool get _isLoggedIn => AuthTokenHolder.instance.hasToken;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _compose({Comment? replyTo}) async {
    if (!_isLoggedIn) {
      _toast('登录后才能发表评论');
      context.push('/login');
      return;
    }
    // 写侧能力（酷狗有、网易没有）。入口本身在 UI 上已隐藏，这里只是兜底。
    final source = _writeSource;
    if (source == null) return;
    final pool = _comments.childrenId;
    if (pool.isEmpty) {
      _toast('评论池未知，请刷新评论后再试');
      return;
    }

    final text = await showCommentComposerSheet(
      context,
      replyTo: replyTo?.user,
      maxLength: CommentRepository.maxContentLength,
    );
    if (!mounted || text == null || text.isEmpty) return;

    try {
      if (replyTo == null) {
        await source.sendResourceComment(
          widget.kind,
          childrenId: pool,
          content: text,
          resourceName: widget.resourceName,
        );
        if (!mounted) return;
        _toast('评论已发布');
        await _loadFirst();
      } else {
        await source.sendResourceFloorReply(
          widget.kind,
          childrenId: pool,
          rootCommentId: replyTo.id,
          content: text,
          replyToUser: replyTo.user,
          replyToContent: replyTo.content,
          resourceName: widget.resourceName,
        );
        if (!mounted) return;
        _toast('回复已发布');
        await _reloadFloor(replyTo);
      }
    } on SourceFailure catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('发送失败：${e.toString().split('\n').first}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('评论', style: kugo.section),
            const SizedBox(width: 8),
            if (_comments.total > 0)
              Text(
                '${formatCount(_comments.total)}条',
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: KugoSpacing.sm),
        // 无写侧能力（网易）时**不渲染**写入口 —— 渲染出来点了才提示不支持更糟。
        if (_writeSource != null) _composerEntry(kugo),
        const SizedBox(height: KugoSpacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(KugoSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_comments.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KugoSpacing.lg),
            child: Text(_error, style: kugo.caption),
          )
        else ...[
          for (final c in _comments.items)
            CommentTile(
              comment: c,
              expanded: _expanded.contains(c.id),
              loadingFloor: _floorLoading.contains(c.id),
              replies: _floors[c.id] ?? const [],
              onToggleReplies: c.hasReplies ? () => _toggleFloor(c) : null,
              onReply: _writeSource == null ? null : () => _compose(replyTo: c),
            ),
          if (_pageHasMore)
            TextButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: KugoSpacing.sm),
              child: Center(
                child: Text('没有更多评论了', style: kugo.caption),
              ),
            ),
        ],
      ],
    );
  }

  /// 「说点什么…」入口：未登录时点击直接引导登录。
  Widget _composerEntry(KugoTheme kugo) {
    return InkWell(
      borderRadius: BorderRadius.circular(KugoRadius.card),
      onTap: () => _compose(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KugoSpacing.md,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: kugo.surfaceElevated,
          borderRadius: BorderRadius.circular(KugoRadius.card),
          border: Border.all(color: kugo.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 16, color: kugo.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isLoggedIn ? '说点什么…' : '登录后参与评论',
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
