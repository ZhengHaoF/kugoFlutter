import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/profile/user_collections_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/responsive.dart';
import '../../features/rank/rank_list_page.dart'
    show rankCoverHeroTag, RankDetailHeaderSurface, rankHeroFlightShuttle;
import '../../shared/widgets/smooth_scroll.dart';

/// 榜单内排序（保持榜单顺序为默认）。
enum RankSortType {
  board('榜单顺序'),
  name('歌名'),
  artist('歌手');

  const RankSortType(this.label);
  final String label;
}

class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.id,
    this.initialBrief,
    this.isRank,
    this.userRepository,
  });

  final String id;
  final PlaylistBrief? initialBrief;
  final bool? isRank;
  final UserRepository? userRepository;

  @override
  ConsumerState<PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  PlaylistBrief? _brief;
  List<Track> _tracks = const [];
  bool _loading = true;
  String _error = '';

  /// 页内换榜后的当前 id；空 = 用路由 [PlaylistDetailPage.id]。
  String? _activeRankId;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  RankSortType _sortType = RankSortType.board;

  List<PlaylistBrief> _allRanks = const [];
  bool _rankPickerLoading = false;
  String _rankPickerGroup = '';

  UserRepository get _userRepo => widget.userRepository ?? userRepository;

  bool get _isRankView => widget.isRank ?? widget.initialBrief?.isRank ?? false;
  String get _effectiveId => _activeRankId ?? widget.id;

  @override
  void initState() {
    super.initState();
    _brief = widget.initialBrief;
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final isRank = _isRankView;
    final targetId = _effectiveId;

    if (isRank) {
      final rank = await playlistRepository.fetchRankDetail(targetId);
      if (!mounted) return;
      if (rank != null && rank.tracks.isNotEmpty) {
        _applyLoaded(rank.brief, rank.tracks, isRank: true);
        return;
      }
    } else {
      final auth = ref.read(authControllerProvider);
      final collections = ref.read(userCollectionsProvider);
      final brief = widget.initialBrief ?? _brief;
      final id = targetId;

      // Check if identified as a user cloud playlist
      PlaylistBrief? matchingCreated;
      for (final p in collections.createdPlaylists) {
        if (p.id == id) {
          matchingCreated = p;
          break;
        }
      }
      PlaylistBrief? matchingCollected;
      for (final p in collections.collectedPlaylists) {
        if (p.id == id) {
          matchingCollected = p;
          break;
        }
      }
      final matchedPlaylist = brief ?? matchingCreated ?? matchingCollected;

      final isUserPlaylist = matchedPlaylist != null &&
          (matchedPlaylist.isDefault ||
              matchedPlaylist.userId.isNotEmpty ||
              matchingCreated != null ||
              matchingCollected != null);

      if (isUserPlaylist && auth.isLogged && auth.user != null) {
        final isCollected = matchingCollected != null ||
            (matchedPlaylist.userId.isNotEmpty &&
                matchedPlaylist.userId != auth.user!.userId);

        final userTracksResult = await _userRepo.fetchUserPlaylistTracks(
          listId: id,
          userId: auth.user!.userId,
          token: auth.user!.token,
          type: isCollected ? 1 : 0,
          page: 1,
          pageSize: 300,
        );
        if (!mounted) return;
        if (userTracksResult.tracks.isNotEmpty) {
          _applyLoaded(matchedPlaylist, userTracksResult.tracks, isRank: false);
          return;
        } else if (userTracksResult.error.isEmpty) {
          _applyLoaded(matchedPlaylist, const [], isRank: false);
          return;
        }
      }

      // Try public special playlist
      final remote = await playlistRepository.fetchPlaylist(id);
      if (!mounted) return;
      if (remote != null && remote.tracks.isNotEmpty) {
        _applyLoaded(remote.brief, remote.tracks, isRank: false);
        return;
      }

      // Fallback: If public failed and user is logged in, attempt user playlist tracks
      if (auth.isLogged && auth.user != null && !isUserPlaylist) {
        final userTracksResult = await _userRepo.fetchUserPlaylistTracks(
          listId: id,
          userId: auth.user!.userId,
          token: auth.user!.token,
          type: 0,
          page: 1,
          pageSize: 300,
        );
        if (!mounted) return;
        if (userTracksResult.tracks.isNotEmpty) {
          final fallbackBrief = matchedPlaylist ??
              PlaylistBrief(
                id: id,
                name: '歌单',
                coverUrl: '',
                trackCount: userTracksResult.tracks.length,
              );
          _applyLoaded(fallbackBrief, userTracksResult.tracks, isRank: false);
          return;
        }
      }
    }

    // Fallback if preferred type failed.
    final fallback = isRank
        ? await playlistRepository.fetchPlaylist(targetId)
        : await playlistRepository.fetchRankDetail(targetId);
    if (!mounted) return;
    if (fallback != null && fallback.tracks.isNotEmpty) {
      _applyLoaded(fallback.brief, fallback.tracks, isRank: !isRank);
      return;
    }

    setState(() {
      _loading = false;
      _error = '${isRank ? "榜单" : "歌单"}加载失败：接口不可用或该 ID 无公开数据';
    });
  }

  void _applyLoaded(
    PlaylistBrief loadedBrief,
    List<Track> loadedTracks, {
    required bool isRank,
  }) {
    final existingCover = _brief?.coverUrl ?? '';
    final remoteCover = loadedBrief.coverUrl;
    var cover = (remoteCover.isNotEmpty &&
            !remoteCover.contains('mock://') &&
            !remoteCover.endsWith('/$_effectiveId'))
        ? remoteCover
        : (existingCover.isNotEmpty && !existingCover.contains('mock://')
            ? existingCover
            : '');

    if (cover.isEmpty && loadedTracks.isNotEmpty) {
      for (final t in loadedTracks) {
        if (t.coverUrl.isNotEmpty &&
            !t.coverUrl.contains('mock://') &&
            (t.coverUrl.startsWith('http://') ||
                t.coverUrl.startsWith('https://'))) {
          cover = t.coverUrl;
          break;
        }
      }
    }

    final genericName = isRank ? '榜单' : '歌单';
    final name = (loadedBrief.name.isNotEmpty && loadedBrief.name != genericName)
        ? loadedBrief.name
        : (_brief?.name ?? loadedBrief.name);

    setState(() {
      _brief = PlaylistBrief(
        id: loadedBrief.id.isNotEmpty ? loadedBrief.id : _effectiveId,
        name: name,
        coverUrl: cover,
        description: loadedBrief.description.isNotEmpty
            ? loadedBrief.description
            : (_brief?.description ?? ''),
        creator: loadedBrief.creator.isNotEmpty
            ? loadedBrief.creator
            : (_brief?.creator ?? ''),
        trackCount: loadedTracks.isNotEmpty
            ? loadedTracks.length
            : loadedBrief.trackCount,
        playCountLabel: loadedBrief.playCountLabel.isNotEmpty
            ? loadedBrief.playCountLabel
            : (_brief?.playCountLabel ?? ''),
        isRank: isRank,
        source: loadedBrief.source,
        userId: loadedBrief.userId,
        isDefault: loadedBrief.isDefault,
        rankTypeName: loadedBrief.rankTypeName.isNotEmpty
            ? loadedBrief.rankTypeName
            : (_brief?.rankTypeName ?? ''),
        updateFrequency: loadedBrief.updateFrequency.isNotEmpty
            ? loadedBrief.updateFrequency
            : (_brief?.updateFrequency ?? ''),
      );
      _tracks = loadedTracks;
      _loading = false;
    });
  }

  List<Track> _applyFilterAndSort(List<Track> source) {
    var result = source;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((t) {
        return t.name.toLowerCase().contains(query) ||
            t.artist.toLowerCase().contains(query) ||
            t.album.toLowerCase().contains(query);
      }).toList();
    } else {
      result = List.of(result);
    }

    switch (_sortType) {
      case RankSortType.board:
        break;
      case RankSortType.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case RankSortType.artist:
        result.sort(
          (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        );
        break;
    }
    return result;
  }

  /// 榜单名次 = 在原始榜单中的位置，搜索/排序后仍显示原名次。
  Map<String, int> get _rankIndexOf {
    final map = <String, int>{};
    for (var i = 0; i < _tracks.length; i++) {
      final key = _tracks[i].id.isNotEmpty ? _tracks[i].id : _tracks[i].hash;
      if (key.isNotEmpty) map[key] = i + 1;
    }
    return map;
  }

  /// 关弹窗并换榜。必须用弹窗自己的 [dialogContext] pop：
  /// `showDialog` 默认挂在 root navigator，用页面 context pop 会把
  /// 详情路由弹回榜单列表，弹窗反而留在上层。
  Future<void> _switchRank(BuildContext dialogContext, PlaylistBrief rank) async {
    Navigator.of(dialogContext).pop();
    if (rank.id == _effectiveId) return;
    if (!mounted) return;
    setState(() {
      _activeRankId = rank.id;
      _brief = rank.copyWith(isRank: true);
      _tracks = const [];
      _searchQuery = '';
      _searchController.clear();
      _sortType = RankSortType.board;
      _error = '';
    });
    await _load();
  }

  Map<String, List<PlaylistBrief>> get _rankGroups {
    final groups = <String, List<PlaylistBrief>>{};
    for (final rank in _allRanks) {
      final key = rank.rankTypeName.trim().isEmpty
          ? '推荐'
          : rank.rankTypeName.trim();
      groups.putIfAbsent(key, () => []).add(rank);
    }
    return groups;
  }

  Future<void> _openRankPicker() async {
    setState(() => _rankPickerLoading = true);
    if (_allRanks.isEmpty) {
      try {
        _allRanks = await playlistRepository.fetchRankList();
      } catch (_) {
        _allRanks = const [];
      }
    }
    final groups = _rankGroups;
    if (_rankPickerGroup.isEmpty || !groups.containsKey(_rankPickerGroup)) {
      _rankPickerGroup = _brief?.rankTypeName.trim().isNotEmpty == true
          ? _brief!.rankTypeName.trim()
          : (groups.isNotEmpty ? groups.keys.first : '');
    }
    setState(() => _rankPickerLoading = false);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      // 与详情页同一 navigator，返回手势/ESC 只关弹窗。
      useRootNavigator: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final kugo = KugoTheme.of(dialogContext);
            final groupKeys = groups.keys.toList();
            final activeGroup = _rankPickerGroup.isNotEmpty &&
                    groups.containsKey(_rankPickerGroup)
                ? _rankPickerGroup
                : (groupKeys.isNotEmpty ? groupKeys.first : '');
            final ranks = groups[activeGroup] ?? const <PlaylistBrief>[];
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
                child: Padding(
                  padding: const EdgeInsets.all(KugoSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('切换榜单', style: kugo.section),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            tooltip: '关闭',
                          ),
                        ],
                      ),
                      if (_rankPickerLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_allRanks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('暂无榜单', style: kugo.caption),
                          ),
                        )
                      else ...[
                        if (groupKeys.length > 1) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: groupKeys.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final key = groupKeys[index];
                                final selected = key == activeGroup;
                                return ChoiceChip(
                                  label: Text(key),
                                  selected: selected,
                                  onSelected: (_) {
                                    setDialogState(() => _rankPickerGroup = key);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: ranks.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final rank = ranks[index];
                              final selected = rank.id == _effectiveId;
                              return ListTile(
                                dense: true,
                                selected: selected,
                                title: Text(rank.name),
                                subtitle: [
                                  if (rank.updateFrequency.isNotEmpty)
                                    rank.updateFrequency,
                                  if (rank.playCountLabel.isNotEmpty)
                                    rank.playCountLabel,
                                ].join(' · ').isEmpty
                                    ? null
                                    : Text(
                                        [
                                          if (rank.updateFrequency.isNotEmpty)
                                            rank.updateFrequency,
                                          if (rank.playCountLabel.isNotEmpty)
                                            rank.playCountLabel,
                                        ].join(' · '),
                                        style: kugo.caption,
                                      ),
                                trailing: selected
                                    ? Icon(Icons.check_rounded,
                                        color: kugo.primary, size: 18)
                                    : null,
                                onTap: () => _switchRank(dialogContext, rank),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  void _playAll(List<Track> queue) {
    if (queue.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playQueue(queue, startIndex: 0);
    context.push('/player');
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final brief = _brief;
    final isRankView = _isRankView;
    final tracks = _tracks;
    final displayed = isRankView ? _applyFilterAndSort(tracks) : tracks;
    final rankIndexOf = _rankIndexOf;
    final desktop = isDesktopView(context);

    return Scaffold(
      // 浏览型详情页：铺满侧栏之外的全部宽度，与发现/探索/榜单一致。
      body: SmoothCustomScrollView(
        slivers: [
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              leading: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              actions: [
                if (isRankView)
                  IconButton(
                    onPressed: _openRankPicker,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    tooltip: '切换榜单',
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Hero(
                  tag: isRankView
                      ? rankCoverHeroTag(_effectiveId)
                      : KugoHeroTags.playlistCover(_effectiveId),
                  flightShuttleBuilder: rankHeroFlightShuttle,
                  child: RankDetailHeaderSurface(
                    brief: brief,
                    tracksCount: tracks.isNotEmpty
                        ? tracks.length
                        : (brief?.trackCount ??
                            widget.initialBrief?.trackCount ??
                            0),
                    fallbackId: _effectiveId,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KugoSpacing.lg,
                  KugoSpacing.lg,
                  KugoSpacing.lg,
                  KugoSpacing.sm,
                ),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: displayed.isEmpty
                          ? null
                          : () => _playAll(displayed),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                    ),
                    if (isRankView) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _openRankPicker,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('切换榜单'),
                      ),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed: _load,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
            if (isRankView && !_loading && tracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KugoSpacing.lg,
                    0,
                    KugoSpacing.lg,
                    KugoSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: KugoTheme.of(context).body,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '搜索歌名、歌手、专辑…',
                            hintStyle: KugoTheme.of(context).caption,
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18),
                                    tooltip: '清空',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(KugoRadius.tile),
                              borderSide: BorderSide(
                                color: KugoTheme.of(context).divider,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(KugoRadius.tile),
                              borderSide: BorderSide(
                                color: KugoTheme.of(context).divider,
                              ),
                            ),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<RankSortType>(
                        icon: const Icon(Icons.sort_rounded),
                        tooltip: '排序方式',
                        initialValue: _sortType,
                        onSelected: (type) => setState(() => _sortType = type),
                        itemBuilder: (context) => [
                          for (final type in RankSortType.values)
                            PopupMenuItem(
                              value: type,
                              child: Row(
                                children: [
                                  Expanded(child: Text(type.label)),
                                  if (_sortType == type)
                                    Icon(Icons.check_rounded,
                                        color: KugoTheme.of(context).primary,
                                        size: 18),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (desktop) ...[
                        const SizedBox(width: 4),
                        Text(
                          _searchQuery.isEmpty
                              ? '${displayed.length} 首'
                              : '${displayed.length} / ${tracks.length} 首',
                          style: KugoTheme.of(context).caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                // SkeletonList is a ListView (a viewport), so the sliver must
                // treat it as a scrolling body or intrinsic layout asserts.
                child: SkeletonList(),
              )
            else if (tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AsyncBody(
                  loading: false,
                  hasError: _error.isNotEmpty,
                  isEmpty: true,
                  errorMessage: _error,
                  emptyMessage: '暂无歌曲',
                  onRetry: _load,
                  child: const SizedBox.shrink(),
                ),
              )
            else if (displayed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AsyncBody(
                  loading: false,
                  hasError: false,
                  isEmpty: true,
                  emptyMessage: '没有匹配的歌曲',
                  onRetry: () => setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                  child: const SizedBox.shrink(),
                ),
              )
            else
              SliverList.builder(
                itemCount: displayed.length,
                itemBuilder: (context, index) {
                  final track = displayed[index];
                  final key = track.id.isNotEmpty ? track.id : track.hash;
                  final rankNo = isRankView ? (rankIndexOf[key] ?? index + 1) : index + 1;
                  return TrackTile(
                    track: track,
                    index: rankNo,
                    isPlaying:
                        player.current?.id == track.id && player.isPlaying,
                    onArtistTap: artistTapFor(context, track),
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .playQueue(displayed, startIndex: index);
                      context.push('/player');
                    },
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
      ),
    );
  }
}
