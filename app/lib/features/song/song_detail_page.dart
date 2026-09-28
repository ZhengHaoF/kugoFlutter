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
import '../../core/theme/responsive.dart';
import '../../data/repositories/comment_repository.dart' show CommentRepository;
import '../../features/player/player_controller.dart';
import '../mv/mv_entry.dart';
import '../../shared/widgets/comment_composer_sheet.dart';
import '../../shared/widgets/comment_tile.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/kugo_h_scroll.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// Route: /song?id=&platform=&name=&artist=&artistId=&album=&cover=&hash=&mixSongId=&duration=
class SongDetailPage extends ConsumerStatefulWidget {
  const SongDetailPage({
    super.key,
    required this.id,
    this.platform = MusicPlatform.kugou,
    this.name = '',
    this.artist = '',
    this.artistId = '',
    this.album = '',
    this.coverUrl = '',
    this.hash = '',
    this.mixSongId = '',
    this.durationMs = 0,
  });

  final String id;

  /// 深链平台（玩家页 `/song?...&platform=` 已带）。能力插槽按它取源，
  /// **不要写死酷狗** —— 否则网易曲目会拿到酷狗的实现。
  final MusicPlatform platform;

  final String name;
  final String artist;

  /// 歌手 id（酷狗 = 数字 singerid）。**缺了「歌手」按钮就会永远禁用** ——
  /// 所以调用方有 `Track.artistId` 时必须带上（见 `full_player_page`）。
  final String artistId;

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

  /// 当前档位 id（**空串 = 用该源的默认档**，即 `commentSortOptions` 首项）。
  ///
  /// 档位**不是枚举**：酷狗是「全部 / 最热 / 弹幕」三档（弹幕其实是另一个评论池），
  /// 网易是服务端 `sortTypeList` 给的推荐 / 热度 / 时间。UI 只存 id 并原样回传，
  /// 不解读语义 —— 换源时旧 id 若不在新源的档位里，自动回落到默认档。
  String _sortId = '';

  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';

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

  /// chips 的**选项列表** —— 这是歌曲级元数据（这首歌有哪些分类 / 热词），
  /// 只有「全部档 + 无筛选」那一个请求（`cmtlist`）的响应会带。
  ///
  /// **必须独立于 `_comments` 存**：分类/热词接口**不返回**筛选项，若直接读
  /// `_comments.classifyList`，点一下 chip 就会整页替换 `_comments` → 选项变空
  /// → chips 行整行消失 → 那个 chip 再也点不到，于是无法取消筛选
  /// （只能退出重进）。
  List<CommentFilterOption> _classifyOptions = const [];
  List<CommentFilterOption> _hotwordOptions = const [];

  /// 精彩评论。游客态实测拿不到（接口返回空），空就不显示这一块。
  List<Comment> _featured = const [];

  /// MV 入口：有 [MvSearchSource] 能力且歌曲带 `mixSongId` 时显示。
  /// 点击后经共享 [`openMvForTrack`] 拉关联 MV 再跳转（带缓存），拉不到就提示。
  bool _mvOpening = false;

  /// 与列表/播放栏同一判据（`mixSongId` + 能力），不再用 `id` 兜底 ——
  /// `songMvs` 只认 `mixSongId`，用 `id` 判会漏出点开必空转的假入口。
  bool get _canShowMv => canOpenMv(_track);

  Future<void> _openMv() async {
    if (_mvOpening) return;
    setState(() => _mvOpening = true);
    try {
      await openMvForTrack(context, _track);
    } finally {
      if (mounted) setState(() => _mvOpening = false);
    }
  }

  Track get _track => Track(
    id: widget.id,
    platform: widget.platform,
    name: widget.name.isEmpty ? '歌曲' : widget.name,
    artist: widget.artist,
    artistId: widget.artistId,
    album: widget.album,
    coverUrl: widget.coverUrl,
    durationMs: widget.durationMs,
    hash: widget.hash,
    mixSongId: widget.mixSongId,
  );

  /// 评论走能力接口取，UI 不直连 repository；**按页面音源取**。
  /// 平台 id（酷狗的 mixsongid 等）由各源实现自己从 [Track] 解析，页面不参与。
  CommentReadSource? get _source =>
      musicSourceRegistry?.capability<CommentReadSource>(widget.platform);

  /// 列表增强能力（分类 / 热词 / 精彩评论）——**只有酷狗有**。
  /// 网易不 implements ⇒ 这里取到 null ⇒ chips 行与精彩评论块自动不出。
  CommentExtrasSource? get _extras =>
      musicSourceRegistry?.capability<CommentExtrasSource>(widget.platform);

  /// 该源的档位列表（无源时为空）。
  List<({String id, String label})> _sortOptionsOf(CommentReadSource? source) =>
      source?.commentSortOptions ?? const [];

  /// 生效档位 id：当前 id 不在该源档位里（换源 / 首次）时回落到首项。
  String _sortIdOf(CommentReadSource? source) {
    final options = _sortOptionsOf(source);
    if (options.isEmpty) return '';
    return options.any((o) => o.id == _sortId) ? _sortId : options.first.id;
  }

  /// 是否在**默认档**（= 首项）。分类 / 热词筛选只在默认档生效。
  bool _isDefaultSort(CommentReadSource? source) {
    final options = _sortOptionsOf(source);
    if (options.isEmpty) return true;
    return _sortIdOf(source) == options.first.id;
  }

  @override
  void initState() {
    super.initState();
    _loadFirst();
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

    // 只有「全部档 + 无筛选」这一路请求（cmtlist）的响应带筛选项；
    // 点了 chip 之后走的是分类/热词接口，它不返回，所以那时**不要**覆盖，
    // chips 行才能一直留在屏幕上（否则取消入口跟着消失）。
    final refreshesFilters =
        _isDefaultSort(source) && _classifyId.isEmpty && _hotword.isEmpty;

    final page = await _fetchPage(source, 1);
    final err = source.lastError;

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
      if (refreshesFilters) {
        _classifyOptions = page.classifyList;
        _hotwordOptions = page.hotwordList;
      }
      _loadedPage = 1;
      _lastPageFull = page.items.length >= _pageSize;
      _error = '';
    });

    // 精彩评论只在「全部」且未筛选时补一块；游客态拿不到就是空，不显示。
    if (refreshesFilters) {
      unawaited(_loadFeatured());
    }
  }

  /// 还有下一页？
  ///
  /// 两种分页形态，差异收在各源实现里：
  /// - **游标式**（网易）：`nextCursor` 非空即还有 —— 它算好了才给，给不出来就是没了；
  /// - **页码式**（酷狗）：上一页是满页且未到服务端 `maxPage`。
  bool get _pageHasMore {
    if (_comments.nextCursor.isNotEmpty) return true;
    if (!_lastPageFull) return false;
    final max = _comments.maxPage;
    return max == 0 || _loadedPage < max;
  }

  Future<void> _loadMore() async {
    final source = _source;
    if (source == null || _loadingMore || !_pageHasMore) return;

    final next = _loadedPage + 1;
    setState(() => _loadingMore = true);
    final page = await _fetchPage(source, next);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _lastPageFull = page.items.length >= _pageSize;
      if (page.items.isEmpty) return;
      _loadedPage = next;
      // 筛选项不在这里续 —— 它是页面状态（`_classifyOptions` / `_hotwordOptions`），
      // 不跟着「一页评论」走，见字段注释。
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

  /// 按当前「档位 + 筛选」取一页。分类 / 热词只在默认档生效。
  Future<CommentPage> _fetchPage(CommentReadSource source, int page) {
    final track = _track;
    if (_isDefaultSort(source)) {
      if (_hotword.isNotEmpty) {
        return _extras!.hotwordComments(
          track,
          hotWord: _hotword,
          page: page,
          pageSize: _pageSize,
        );
      }
      if (_classifyId.isNotEmpty) {
        return _extras!.classifyComments(
          track,
          typeId: _classifyId,
          page: page,
          pageSize: _pageSize,
        );
      }
    }
    return source.songComments(
      track,
      page: page,
      pageSize: _pageSize,
      sort: _sortIdOf(source),
      // 游标式源靠它翻页（页码式源忽略）。首页为空。
      cursor: page > 1 ? _comments.nextCursor : '',
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

  /// 精彩评论：只在默认档且未筛选时拉一次；空就是空（游客态拿不到），不显示区块。
  ///
  /// 无 [CommentExtrasSource]（网易）时直接不拉 ——「精彩评论」是酷狗独有的口。
  Future<void> _loadFeatured() async {
    final extras = _extras;
    final pool = _comments.childrenId;
    if (extras == null || pool.isEmpty) return;
    final list = await extras.featuredComments(track: _track, childrenId: pool);
    if (!mounted) return;
    setState(() => _featured = list);
  }

  Future<void> _switchSort(String id) async {
    if (id == _sortIdOf(_source)) return;
    setState(() {
      _sortId = id;
      // 分类 / 热词只属于默认档，换档时清掉，免得标签与数据源不一致。
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
      track: _track,
      childrenId: _comments.childrenId,
      rootCommentId: id,
    );
    if (!mounted) return;
    setState(() {
      _floorLoading.remove(id);
      _floors[id] = list;
    });
  }

  // ── 写侧（发评论 / 回复） ────────────────────────────────

  CommentWriteSource? get _writer =>
      musicSourceRegistry?.capability<CommentWriteSource>(widget.platform);

  /// 点赞能力 —— **目前只有网易有**（酷狗没有这个口）。
  /// 取不到就不渲染赞按钮，而不是渲染出来点了才提示不支持。
  CommentLikeSource? get _liker =>
      musicSourceRegistry?.capability<CommentLikeSource>(widget.platform);

  /// 登录态**按源判断**：酷狗看 `AuthTokenHolder` 的 token，网易看 `MUSIC_U`
  /// cookie —— 两者不是一回事。早先统一看酷狗 token，导致网易已扫码登录、
  /// 酷狗没登录时仍提示「登录后才能发表评论」并跳酷狗登录页。
  bool get _isLoggedIn => _writer?.isLoggedIn ?? false;

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

    final track = _track;
    try {
      if (replyTo == null) {
        await writer.sendSongComment(
          track: track,
          childrenId: pool,
          content: text,
        );
        if (!mounted) return;
        _toast('评论已发布');
        await _loadFirst();
      } else {
        await writer.sendFloorReply(
          track: track,
          childrenId: pool,
          rootCommentId: replyTo.id,
          content: text,
          replyToUser: replyTo.user,
          replyToContent: replyTo.content,
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

  /// 点赞 / 取消赞：**乐观更新**（先改本地再发请求），失败回滚。
  Future<void> _toggleLike(Comment c, bool like) async {
    final liker = _liker;
    final pool = _comments.childrenId;
    if (liker == null || pool.isEmpty) {
      _toast('评论池未知，请刷新评论后再试');
      return;
    }
    _applyLike(c.id, liked: like, likeCount: c.likeCount + (like ? 1 : -1));
    try {
      await liker.setCommentLiked(
        childrenId: pool,
        commentId: c.id,
        like: like,
      );
    } on SourceFailure catch (e) {
      _applyLike(c.id, liked: c.liked, likeCount: c.likeCount);
      _toast(e.message);
    } catch (_) {
      _applyLike(c.id, liked: c.liked, likeCount: c.likeCount);
      _toast('点赞失败，请稍后再试');
    }
  }

  /// 就地替换一条评论的赞状态（列表不可变，故重建 [CommentPage]）。
  void _applyLike(String id, {required bool liked, required int likeCount}) {
    setState(() {
      _comments = CommentPage(
        items: [
          for (final c in _comments.items)
            c.id == id ? c.copyWith(liked: liked, likeCount: likeCount) : c,
        ],
        total: _comments.total,
        childrenId: _comments.childrenId,
        maxPage: _comments.maxPage,
        nextCursor: _comments.nextCursor,
        classifyList: _comments.classifyList,
        hotwordList: _comments.hotwordList,
      );
    });
  }

  /// 回复成功后强制重拉该楼层 —— 楼层已缓存，仅展开不会看到新内容。
  Future<void> _reloadFloor(Comment root) async {
    final source = _source;
    if (source == null) return;
    setState(() => _floorLoading.add(root.id));
    final list = await source.floorReplies(
      track: _track,
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

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final track = _track;
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('歌曲详情')),
      body: DesktopContentConstraint.reading(
        child: SmoothListView(
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
              if (_canShowMv) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _mvOpening ? null : _openMv,
                    icon: _mvOpening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.videocam_outlined, size: 18),
                    label: const Text('MV'),
                  ),
                ),
              ],
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
              // 档位由源给出（首项即默认，UI 不解读语义），酷狗三档、网易三档。
              for (final o in _sortOptionsOf(_source))
                _sortButton(kugo, o.id, o.label),
            ],
          ),
          const SizedBox(height: KugoSpacing.sm),
          // 无写侧能力（网易）时**不渲染**「说点什么…」——
          // 渲染出来点了才 toast「不支持」是更差的做法。
          if (_writer != null) _composerEntry(kugo),
          // 分类 / 热词是酷狗独有的增强能力，无该能力（网易）时整行不出。
          if (_extras != null && _isDefaultSort(_source)) _filterChipsRow(kugo),
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
            for (final c in _featured) CommentTile(comment: c),
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
              CommentTile(
                comment: c,
                expanded: _expanded.contains(c.id),
                loadingFloor: _floorLoading.contains(c.id),
                replies: _floors[c.id] ?? const [],
                onToggleReplies: c.hasReplies ? () => _toggleFloor(c) : null,
                onReply: _writer == null ? null : () => _compose(replyTo: c),
                // 点赞要同时满足：源有该能力 + 已登录（未登录点了也是白点）。
                onToggleLike: _liker == null || !_isLoggedIn
                    ? null
                    : (like) => _toggleLike(c, like),
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
      ),
    );
  }

  Widget _sortButton(KugoTheme kugo, String id, String label) {
    final selected = _sortIdOf(_source) == id;
    return TextButton(
      onPressed: () => _switchSort(id),
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
  ///
  /// 读的是页面状态里的选项（**不是** `_comments.classifyList`）——
  /// 否则点一下就整行消失。详见字段注释。
  Widget _filterChipsRow(KugoTheme kugo) {
    final options = <Widget>[
      for (final c in _classifyOptions)
        _chip(
          kugo,
          label: c.count > 0 ? '${c.label} ${formatCount(c.count)}' : c.label,
          selected: _classifyId == c.id,
          onTap: () => _selectClassify(c.id),
        ),
      for (final w in _hotwordOptions)
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
        fadeEdges: false,
        builder: (context, controller, _) => SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Row(children: options),
        ),
      ),
    );
  }

  /// 一个筛选 chip。**选中态右侧带 ✕** —— 提示「再点一次即取消」，
  /// 否则用户看不出还能退出筛选（点整块任意处都算取消）。
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
          padding: EdgeInsets.only(
            left: 12,
            right: selected ? 8 : 12,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? kugo.primary.withValues(alpha: 0.14)
                : kugo.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kugo.primary : kugo.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: kugo.caption.copyWith(
                  color: selected ? kugo.primary : kugo.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(Icons.close_rounded, size: 14, color: kugo.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
