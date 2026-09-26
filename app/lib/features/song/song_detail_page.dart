import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/mappers.dart' show formatCount;
import '../../core/models/comment.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
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
      page = await source.songComments(
        id,
        page: 1,
        pageSize: _pageSize,
        sort: _sort,
      );
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
    final page = await source.songComments(
      id,
      page: next,
      pageSize: _pageSize,
      sort: _sort,
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

  Future<void> _switchSort(CommentSort sort) async {
    if (sort == _sort) return;
    setState(() => _sort = sort);
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
            ],
          ),
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
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    this.expanded = false,
    this.loadingFloor = false,
    this.replies = const [],
    this.onToggleReplies,
  });

  final Comment comment;
  final bool expanded;
  final bool loadingFloor;
  final List<Comment> replies;
  final VoidCallback? onToggleReplies;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KugoSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.user,
                        style: kugo.caption.copyWith(
                          color: kugo.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
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
