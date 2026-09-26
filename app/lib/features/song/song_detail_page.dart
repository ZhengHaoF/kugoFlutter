import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/mappers.dart' show formatCount;
import '../../core/models/comment.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/comment_repository.dart' show CommentRepository;
import '../../data/repositories/search_repository.dart';
import '../../features/auth/auth_token_holder.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/comment_composer_sheet.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/kugo_h_scroll.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// Route: /song?id=&name=&artist=&album=&cover=&hash=&mixSongId=&duration=
class SongDetailPage extends ConsumerStatefulWidget {
  const SongDetailPage({
    super.key,
    required this.id,
    this.name = '',
    this.artist = '',
    this.album = '',
    this.coverUrl = '',
    this.hash = '',
    this.mixSongId = '',
    this.durationMs = 0,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final String hash;
  final String mixSongId;
  final int durationMs;

  @override
  ConsumerState<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends ConsumerState<SongDetailPage> {
  static const int _pageSize = 20;

  CommentPage _comments = CommentPage.empty;
  CommentSort _sort = CommentSort.all;
  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';
  String? _resolvedMixId;

  /// 分页游标：`_loadedPage` 是已加载到的页码，`_lastPageFull` 是最近一页是否满页。
  /// **不能**用「累积条数 ÷ pageSize」推页码 —— 空页/短页会把它带偏。
  int _loadedPage = 0;
  bool _lastPageFull = false;

  /// 楼层：根评论 id → 回复列表；`_expanded` 记展开了哪些，`_floorLoading` 去重。
  final Map<String, List<Comment>> _floors = {};
  final Set<String> _expanded = {};
  final Set<String> _floorLoading = {};

  /// 分类 / 热词筛选（只在「全部」档生效；再点一次同一个 chip 取消）。
  String _classifyId = '';
  String _hotword = '';

  /// 精彩评论。游客态实测拿不到（接口返回空），空就不显示这一块。
  List<Comment> _featured = const [];

  Track get _track => Track(
    id: widget.id,
    name: widget.name.isEmpty ? '歌曲' : widget.name,
    artist: widget.artist,
    album: widget.album,
    coverUrl: widget.coverUrl,
    durationMs: widget.durationMs,
    hash: widget.hash,
    mixSongId: _resolvedMixId ?? widget.mixSongId,
  );

  /// 评论走能力接口取，UI 不直连 repository。
  CommentReadSource? get _source =>
      musicSourceRegistry?.capability<CommentReadSource>(MusicPlatform.kugou);

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  /// cmtlist needs album_audio_id as mixsongid (NOT audio_id).
  /// EchoMusic: mixSongId || resourceId, with search-backed detailSong.
  Future<List<String>> _mixSongIdCandidates() async {
    final out = <String>[];
    void add(String? v) {
      if (v == null) return;
      var s = v.trim();
      if (s.isEmpty || s == '0' || s.toLowerCase() == 'null') return;
      // Hash-like values are never valid mixsongid.
      if (s.length >= 32 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return;
      if (!out.contains(s)) out.add(s);
    }

    final name = widget.name.trim();
    final artist = widget.artist.trim();
    final hash = widget.hash.trim().toLowerCase();

    // Prefer live search album_audio_id — old queue stores audio_id.
    Future<void> searchOnce(String keyword) async {
      if (keyword.isEmpty) return;
      try {
        final hits = await searchRepository.searchSongs(keyword, pageSize: 10);
        Track? byHash;
        Track? byNameArtist;
        Track? byName;
        for (final t in hits) {
          if (hash.isNotEmpty &&
              t.hash.isNotEmpty &&
              t.hash.toLowerCase() == hash) {
            byHash = t;
            break;
          }
        }
        for (final t in hits) {
          final nOk = name.isEmpty || t.name == name;
          final aOk =
              artist.isEmpty ||
              t.artist.contains(artist) ||
              artist.contains(t.artist);
          if (nOk && aOk) {
            byNameArtist = t;
            break;
          }
        }
        for (final t in hits) {
          if (name.isNotEmpty && t.name == name) {
            byName = t;
            break;
          }
        }
        final match =
            byHash ??
            byNameArtist ??
            byName ??
            (hits.isNotEmpty ? hits.first : null);
        if (match != null) {
          add(match.mixSongId);
          _resolvedMixId ??= match.mixSongId;
        }
        // Also collect other album_audio_ids for the same title (covers/Live).
        for (final t in hits) {
          if (name.isNotEmpty && t.name.startsWith(name)) add(t.mixSongId);
        }
      } catch (_) {}
    }

    await searchOnce(
      [
        if (name.isNotEmpty) name,
        if (artist.isNotEmpty) artist,
      ].join(' ').trim(),
    );
    if (out.isEmpty) await searchOnce(name);
    if (out.isEmpty && hash.isNotEmpty) await searchOnce(hash);

    add(_resolvedMixId);
    add(widget.mixSongId);
    add(widget.id);
    return out;
  }

  /// 首屏 / 切排序：**切排序会清空旧列表**（两种排序的内容完全不同，
  /// 混着显示会误导）。[keepList] 为真时保留当前列表，只在顶部转圈。
  Future<void> _loadFirst({bool keepList = false}) async {
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
      _loadingMore = false;
      _error = '';
      if (!keepList) {
        _comments = CommentPage.empty;
        _floors.clear();
        _expanded.clear();
        _floorLoading.clear();
      }
    });

    final candidates = _resolvedMixId != null
        ? <String>[_resolvedMixId!]
        : await _mixSongIdCandidates();
    var page = CommentPage.empty;
    var err = '';
    for (final id in candidates) {
      page = await _fetchPage(source, id, 1);
      if (page.items.isNotEmpty) {
        _resolvedMixId = id;
        break;
      }
      err = source.lastError;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page.items.isEmpty) {
        _comments = CommentPage.empty;
        _loadedPage = 0;
        _lastPageFull = false;
        _error = err.isEmpty ? '暂无评论' : err;
        return;
      }
      _comments = page;
      _loadedPage = 1;
      _lastPageFull = page.items.length >= _pageSize;
      _error = '';
    });

    // 精彩评论只在「全部」且未筛选时补一块；游客态拿不到就是空，不显示。
    if (_sort == CommentSort.all && _classifyId.isEmpty && _hotword.isEmpty) {
      unawaited(_loadFeatured());
    }
  }

  /// 还有下一页？= 上一页是满页，且未到达服务端的 `maxPage`。
  bool get _pageHasMore {
    if (!_lastPageFull) return false;
    final max = _comments.maxPage;
    return max == 0 || _loadedPage < max;
  }

  Future<void> _loadMore() async {
    final source = _source;
    final id = _resolvedMixId;
    if (source == null || id == null || _loadingMore || !_pageHasMore) return;

    final next = _loadedPage + 1;
    setState(() => _loadingMore = true);
    final page = await _fetchPage(source, id, next);
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
        // 筛选项只有首屏响应带，翻页时必须原样续上，否则 chips 会消失。
        classifyList: _comments.classifyList,
        hotwordList: _comments.hotwordList,
      );
    });
  }

  /// 按当前「档位 + 筛选」取一页。分类 / 热词只在「全部」档生效。
  Future<CommentPage> _fetchPage(
    CommentReadSource source,
    String mixSongId,
    int page,
  ) {
    if (_sort == CommentSort.all) {
      if (_hotword.isNotEmpty) {
        return source.hotwordComments(
          mixSongId,
          hotWord: _hotword,
          page: page,
          pageSize: _pageSize,
        );
      }
      if (_classifyId.isNotEmpty) {
        return source.classifyComments(
          mixSongId,
          typeId: _classifyId,
          page: page,
          pageSize: _pageSize,
        );
      }
    }
    return source.songComments(
      mixSongId,
      page: page,
      pageSize: _pageSize,
      sort: _sort,
    );
  }

  /// 选中 / 取消分类 chip（再点同一个即取消）。
  Future<void> _selectClassify(String id) async {
    setState(() {
      _classifyId = _classifyId == id ? '' : id;
      _hotword = '';
    });
    await _loadFirst();
  }

  /// 选中 / 取消热词 chip。
  Future<void> _selectHotword(String word) async {
    setState(() {
      _hotword = _hotword == word ? '' : word;
      _classifyId = '';
    });
    await _loadFirst();
  }

  /// 精彩评论：只在「全部」且未筛选时拉一次；空就是空（游客态拿不到），不显示区块。
  Future<void> _loadFeatured() async {
    final source = _source;
    final pool = _comments.childrenId;
    if (source == null || pool.isEmpty) return;
    final list = await source.featuredComments(
      childrenId: pool,
      mixSongId: _resolvedMixId ?? widget.mixSongId,
    );
    if (!mounted) return;
    setState(() => _featured = list);
  }

  Future<void> _switchSort(CommentSort sort) async {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      // 分类 / 热词只属于「全部」档，换档时清掉，免得标签与数据源不一致。
      _classifyId = '';
      _hotword = '';
    });
    await _loadFirst();
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
    final list = await source.floorReplies(
      childrenId: _comments.childrenId,
      rootCommentId: id,
      mixSongId: _resolvedMixId ?? widget.mixSongId,
    );
    if (!mounted) return;
    setState(() {
      _floorLoading.remove(id);
      _floors[id] = list;
    });
  }

  // ── 写侧（发评论 / 回复） ────────────────────────────────

  CommentWriteSource? get _writer =>
      musicSourceRegistry?.capability<CommentWriteSource>(MusicPlatform.kugou);

  bool get _isLoggedIn => AuthTokenHolder.instance.hasToken;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 打开输入弹层并提交。[replyTo] 为空 = 发主评论，否则回复该主评论。
  Future<void> _compose({Comment? replyTo}) async {
    if (!_isLoggedIn) {
      _toast('登录后才能发表评论');
      context.push('/login');
      return;
    }
    final writer = _writer;
    if (writer == null) {
      _toast('当前音源不支持评论');
      return;
    }
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

    final songName = widget.name.trim();
    final mixSongId = _resolvedMixId ?? widget.mixSongId;
    try {
      if (replyTo == null) {
        await writer.sendSongComment(
          childrenId: pool,
          content: text,
          songName: songName,
          mixSongId: mixSongId,
        );
        if (!mounted) return;
        _toast('评论已发布');
        await _loadFirst();
      } else {
        await writer.sendFloorReply(
          childrenId: pool,
          rootCommentId: replyTo.id,
          content: text,
          replyToUser: replyTo.user,
          replyToContent: replyTo.content,
          songName: songName,
          mixSongId: mixSongId,
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

  /// 回复成功后强制重拉该楼层 —— 楼层已缓存，仅展开不会看到新内容。
  Future<void> _reloadFloor(Comment root) async {
    final source = _source;
    if (source == null) return;
    setState(() => _floorLoading.add(root.id));
    final list = await source.floorReplies(
      childrenId: _comments.childrenId,
      rootCommentId: root.id,
      mixSongId: _resolvedMixId ?? widget.mixSongId,
    );
    if (!mounted) return;
    setState(() {
      _floorLoading.remove(root.id);
      _floors[root.id] = list;
      _expanded.add(root.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final track = _track;
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('歌曲详情')),
      body: SmoothListView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          KugoSpacing.md,
          KugoSpacing.lg,
          40,
        ),
        children: [
          Row(
            children: [
              if (track.id.isNotEmpty || track.hash.isNotEmpty)
                CoverHero(
                  tag: track.id.isNotEmpty
                      ? 'player-cover-${track.id}'
                      : KugoHeroTags.songCover(track.hash),
                  seed: track.coverUrl,
                  size: 88,
                  radius: KugoRadius.card,
                )
              else
                CoverBox(
                  seed: track.coverUrl,
                  size: 88,
                  radius: KugoRadius.card,
                ),
              const SizedBox(width: KugoSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, style: kugo.title),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.artist.isEmpty ? '未知歌手' : track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SourceBadge(platform: track.platform),
                      ],
                    ),
                    if (track.album.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(color: kugo.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KugoSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref.read(playerControllerProvider.notifier).playQueue([
                      track,
                    ], startIndex: 0);
                    context.push('/player');
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('播放'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: artistTapFor(context, track),
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('歌手'),
                ),
              ),
            ],
          ),
          if (player.current?.id == track.id)
            Padding(
              padding: const EdgeInsets.only(top: KugoSpacing.sm),
              child: Text(
                player.isPlaying ? '正在播放' : '已加入播放',
                style: kugo.caption.copyWith(color: kugo.primary),
              ),
            ),
          const SizedBox(height: KugoSpacing.xl),
          Row(
            children: [
              Text('评论', style: kugo.section),
              const SizedBox(width: 8),
              if (_comments.total > 0)
                Text(
                  '${formatCount(_comments.total)}条',
                  style: kugo.caption.copyWith(color: kugo.textTertiary),
                ),
              const Spacer(),
              _sortButton(kugo, CommentSort.hottest, '最热'),
              _sortButton(kugo, CommentSort.all, '全部'),
              _sortButton(kugo, CommentSort.barrage, '弹幕'),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          _composerEntry(kugo),
          if (_sort == CommentSort.all) _filterChipsRow(kugo),
          if (_featured.isNotEmpty) ...[
            const SizedBox(height: KugoSpacing.md),
            Row(
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: kugo.primary,
                ),
                const SizedBox(width: 6),
                Text('精彩评论', style: kugo.section),
              ],
            ),
            const SizedBox(height: KugoSpacing.sm),
            for (final c in _featured) _CommentTile(comment: c),
            Divider(color: kugo.divider),
          ],
          const SizedBox(height: KugoSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(KugoSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_comments.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(KugoSpacing.lg),
              child: Text(
                _error.isEmpty ? '暂无评论' : _error,
                style: kugo.caption,
              ),
            )
          else ...[
            for (final c in _comments.items)
              _CommentTile(
                comment: c,
                expanded: _expanded.contains(c.id),
                loadingFloor: _floorLoading.contains(c.id),
                replies: _floors[c.id] ?? const [],
                onToggleReplies: c.hasReplies ? () => _toggleFloor(c) : null,
                onReply: () => _compose(replyTo: c),
              ),
            if (_pageHasMore)
              TextButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: Text(_loadingMore ? '加载中…' : '加载更多'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: KugoSpacing.sm),
                child: Center(child: Text('没有更多评论了', style: kugo.caption)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sortButton(KugoTheme kugo, CommentSort value, String label) {
    final selected = _sort == value;
    return TextButton(
      onPressed: () => _switchSort(value),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: kugo.caption.copyWith(
          color: selected ? kugo.primary : kugo.textTertiary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
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

  /// 分类 / 热词 chips。只在「全部」档出现；没有筛选项时整行收起。
  Widget _filterChipsRow(KugoTheme kugo) {
    final options = <Widget>[
      for (final c in _comments.classifyList)
        _chip(
          kugo,
          label: c.count > 0 ? '${c.label} ${formatCount(c.count)}' : c.label,
          selected: _classifyId == c.id,
          onTap: () => _selectClassify(c.id),
        ),
      for (final w in _comments.hotwordList)
        _chip(
          kugo,
          label: '#${w.label}',
          selected: _hotword == w.id,
          onTap: () => _selectHotword(w.id),
        ),
    ];
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: KugoSpacing.sm),
      child: KugoHScroll(
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Row(children: options),
        ),
      ),
    );
  }

  Widget _chip(
    KugoTheme kugo, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? kugo.primary.withValues(alpha: 0.14)
                : kugo.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kugo.primary : kugo.divider),
          ),
          child: Text(
            label,
            style: kugo.caption.copyWith(
              color: selected ? kugo.primary : kugo.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
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
  final VoidCallback? onToggleReplies;
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
                              _badge(kugo, b),
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
                    for (final r in replies) _FloorReplyTile(reply: r),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 铭牌 chip：VIP 类用主色，身份类（学生/演员/认证/明星）用中性色。
  Widget _badge(KugoTheme kugo, CommentBadge badge) {
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

/// 楼层回复：缩进 + 更小的头像/字号。
class _FloorReplyTile extends StatelessWidget {
  const _FloorReplyTile({required this.reply});

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
