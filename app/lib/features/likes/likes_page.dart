import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/profile/user_collections_controller.dart';
import '../../core/theme/hero_tags.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart' show CoverHero;
import 'likes_controller.dart';
import '../../shared/widgets/smooth_scroll.dart';

enum LikesSortType {
  added('默认排序'),
  name('歌曲名'),
  artist('歌手名');

  const LikesSortType(this.label);
  final String label;
}

class LikesPage extends ConsumerStatefulWidget {
  const LikesPage({super.key});

  @override
  ConsumerState<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends ConsumerState<LikesPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  bool _isSearching = false;
  String _searchQuery = '';
  LikesSortType _sortType = LikesSortType.added;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    // Actively pull cloud collections when the page opens (EchoMusic onMounted).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (!auth.isLogged) return;
      final collections = ref.read(userCollectionsProvider);
      if (!collections.loaded) {
        ref.read(userCollectionsProvider.notifier).loadAll();
      } else if (collections.cloudFavoriteTracks.isEmpty &&
          collections.favoriteTracksError.isEmpty) {
        ref.read(userCollectionsProvider.notifier).loadFavoriteTracks();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Track> _applyFilterAndSort(List<Track> source) {
    var result = source;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((t) {
        final name = t.name.toLowerCase();
        final artist = t.artist.toLowerCase();
        final album = t.album.toLowerCase();
        return name.contains(query) ||
            artist.contains(query) ||
            album.contains(query);
      }).toList();
    } else {
      result = List.of(result);
    }

    switch (_sortType) {
      case LikesSortType.added:
        break;
      case LikesSortType.name:
        result.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case LikesSortType.artist:
        result.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
    }

    return result;
  }

  List<ArtistBrief> _filterSingers(List<ArtistBrief> source) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where((s) => s.name.toLowerCase().contains(query))
        .toList();
  }

  List<AlbumBrief> _filterAlbums(List<AlbumBrief> source) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((a) {
      return a.name.toLowerCase().contains(query) ||
          a.artist.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final auth = ref.watch(authControllerProvider);
    final collections = ref.watch(userCollectionsProvider);
    final localLikes = ref.watch(likesProvider);
    final player = ref.watch(playerControllerProvider);

    // Keep local heart cache in sync with cloud favorites.
    if (auth.isLogged && collections.cloudFavoriteTracks.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(likesProvider.notifier)
            .absorbCloudTracks(collections.cloudFavoriteTracks);
      });
    }

    // 登录后只认云端「我喜欢」；本地红心仅作离线缓存/红心态，不拼进列表。
    final List<Track> songsSource =
        auth.isLogged ? collections.cloudFavoriteTracks : localLikes;

    final displayedSongs = _applyFilterAndSort(songsSource);
    final displayedSingers = _filterSingers(collections.followedSingers);
    final displayedAlbums = _filterAlbums(collections.favoritedAlbums);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: kugo.body,
                decoration: InputDecoration(
                  hintText: _tabController.index == 0
                      ? '搜索歌名、歌手、专辑...'
                      : (_tabController.index == 1
                          ? '搜索关注的歌手...'
                          : '搜索收藏的专辑或歌手...'),
                  hintStyle: kugo.caption,
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text('我喜欢'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? '关闭搜索' : '搜索',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (_tabController.index == 0) ...[
            if (auth.isLogged)
              IconButton(
                icon: collections.isLoadingFavoriteTracks
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: '刷新我喜欢歌曲',
                onPressed: collections.isLoadingFavoriteTracks
                    ? null
                    : () => ref
                        .read(userCollectionsProvider.notifier)
                        .loadFavoriteTracks(force: true),
              ),
            PopupMenuButton<LikesSortType>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: '排序方式',
              initialValue: _sortType,
              onSelected: (type) => setState(() => _sortType = type),
              itemBuilder: (context) => [
                for (final type in LikesSortType.values)
                  PopupMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Expanded(child: Text(type.label)),
                        if (_sortType == type)
                          Icon(Icons.check_rounded,
                              color: kugo.primary, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          ]
          else if (_tabController.index == 1 && auth.isLogged)
            IconButton(
              icon: collections.isLoadingFollow
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: '刷新关注歌手',
              onPressed: collections.isLoadingFollow
                  ? null
                  : () => ref
                      .read(userCollectionsProvider.notifier)
                      .loadFollow(),
            )
          else if (_tabController.index == 2 && auth.isLogged)
            IconButton(
              icon: collections.isLoadingPlaylists
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: '刷新收藏专辑',
              onPressed: collections.isLoadingPlaylists
                  ? null
                  : () => ref
                      .read(userCollectionsProvider.notifier)
                      .loadPlaylists(),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: TabBar(
            controller: _tabController,
            labelColor: kugo.primary,
            unselectedLabelColor: kugo.textSecondary,
            indicatorColor: kugo.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: '歌曲 (${songsSource.length})'),
              Tab(text: '歌手 (${collections.followedSingers.length})'),
              Tab(text: '专辑 (${collections.favoritedAlbums.length})'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 歌曲
          _buildSongsTab(
            displayed: displayedSongs,
            totalCount: songsSource.length,
            isLoading: collections.isLoadingFavoriteTracks && songsSource.isEmpty,
            error: auth.isLogged ? collections.favoriteTracksError : '',
            auth: auth,
            player: player,
            kugo: kugo,
          ),
          // Tab 2: 歌手
          _buildSingersTab(
            auth: auth,
            singers: displayedSingers,
            totalCount: collections.followedSingers.length,
            isLoading: collections.isLoadingFollow && !collections.loaded,
            error: collections.followError,
            kugo: kugo,
          ),
          // Tab 3: 专辑
          _buildAlbumsTab(
            auth: auth,
            albums: displayedAlbums,
            totalCount: collections.favoritedAlbums.length,
            isLoading: collections.isLoadingPlaylists && !collections.loaded,
            error: collections.playlistsError,
            kugo: kugo,
          ),
        ],
      ),
    );
  }

  Widget _buildSongsTab({
    required List<Track> displayed,
    required int totalCount,
    required PlayerState player,
    required KugoTheme kugo,
    required AuthState auth,
    bool isLoading = false,
    String error = '',
  }) {
    if (isLoading) {
      return const AsyncBody(
        loading: true,
        hasError: false,
        isEmpty: false,
        child: SizedBox.shrink(),
      );
    }

    if (totalCount == 0) {
      final emptyMessage = !auth.isLogged
          ? '登录酷狗账号后，即可同步云端「我喜欢」'
          : (error.isNotEmpty
              ? error
              : '还没有红心歌曲\n播放时点 ♥ 即可收藏到云端');
      return AsyncBody(
        loading: false,
        hasError: error.isNotEmpty,
        isEmpty: true,
        emptyMessage: emptyMessage,
        errorMessage: error.isEmpty ? '加载失败' : error,
        onRetry: auth.isLogged
            ? () => ref
                .read(userCollectionsProvider.notifier)
                .loadFavoriteTracks(force: true)
            : () => context.push('/login'),
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                _searchQuery.isNotEmpty
                    ? '找到 ${displayed.length} 首 / 共 $totalCount 首'
                    : '${displayed.length} 首 · ${_sortType.label}',
                style: kugo.caption,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: displayed.isEmpty
                    ? null
                    : () {
                        ref
                            .read(playerControllerProvider.notifier)
                            .playQueue(displayed, startIndex: 0);
                        context.push('/player');
                      },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('播放全部'),
              ),
            ],
          ),
        ),
        Expanded(
          child: displayed.isEmpty
              ? AsyncBody(
                  loading: false,
                  hasError: false,
                  isEmpty: true,
                  emptyMessage: '未找到匹配的歌曲\n换个关键词试试',
                  onRetry: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const SizedBox.shrink(),
                )
              : SmoothListViewBuilder(
                  itemCount: displayed.length,
                  itemBuilder: (context, index) {
                    final track = displayed[index];
                    return TrackTile(
                      track: track,
                      isPlaying: player.current?.id == track.id &&
                          player.isPlaying,
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFFE87A90),
                          size: 20,
                        ),
                        onPressed: () => ref
                            .read(likesProvider.notifier)
                            .removeTrack(track),
                      ),
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
        ),
      ],
    );
  }

  Widget _buildSingersTab({
    required AuthState auth,
    required List<ArtistBrief> singers,
    required int totalCount,
    required bool isLoading,
    required String error,
    required KugoTheme kugo,
  }) {
    if (!auth.isLogged) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: kugo.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: KugoSpacing.md),
              Text(
                '登录酷狗账号后，即可同步关注的歌手',
                style: kugo.caption.copyWith(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KugoSpacing.lg),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (totalCount == 0) {
      return AsyncBody(
        loading: false,
        hasError: error.isNotEmpty,
        isEmpty: true,
        emptyMessage: error.isNotEmpty ? error : '暂无关注的歌手\n搜索歌手并点击关注即可在此查看',
        errorMessage: error.isEmpty ? '加载失败' : error,
        onRetry: () =>
            ref.read(userCollectionsProvider.notifier).loadFollow(),
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                _searchQuery.isNotEmpty
                    ? '找到 ${singers.length} 位 / 共 $totalCount 位'
                    : '共 $totalCount 位关注歌手',
                style: kugo.caption,
              ),
            ],
          ),
        ),
        Expanded(
          child: singers.isEmpty
              ? AsyncBody(
                  loading: false,
                  hasError: false,
                  isEmpty: true,
                  emptyMessage: '未找到匹配的歌手',
                  onRetry: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const SizedBox.shrink(),
                )
              : SmoothListViewBuilder(
                  itemCount: singers.length,
                  itemBuilder: (context, index) {
                    final singer = singers[index];
                    final desc = singer.sourceDesc.isNotEmpty
                        ? singer.sourceDesc
                        : '歌手';
                    final sub = singer.songCount > 0
                        ? '$desc · ${singer.songCount} 首单曲'
                        : desc;
                    return ListTile(
                      leading: CoverHero(
                        tag: KugoHeroTags.artistAvatar(singer.id),
                        seed: singer.avatarUrl.isNotEmpty
                            ? singer.avatarUrl
                            : singer.id,
                        size: 48,
                        radius: 999,
                        child: singer.avatarUrl.isEmpty
                            ? const Icon(Icons.person_rounded,
                                color: Colors.white70)
                            : null,
                      ),
                      title: Text(singer.name, style: kugo.body),
                      subtitle: Text(sub, style: kugo.caption),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: kugo.textSecondary,
                      ),
                      onTap: () => context.push('/artist/${singer.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAlbumsTab({
    required AuthState auth,
    required List<AlbumBrief> albums,
    required int totalCount,
    required bool isLoading,
    required String error,
    required KugoTheme kugo,
  }) {
    if (!auth.isLogged) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.album_outlined,
                size: 48,
                color: kugo.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: KugoSpacing.md),
              Text(
                '登录酷狗账号后，即可同步收藏的专辑',
                style: kugo.caption.copyWith(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: KugoSpacing.lg),
              FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('立即登录'),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (totalCount == 0) {
      return AsyncBody(
        loading: false,
        hasError: error.isNotEmpty,
        isEmpty: true,
        emptyMessage: error.isNotEmpty ? error : '暂无收藏的专辑\n在专辑详情中点击收藏即可在此查看',
        errorMessage: error.isEmpty ? '加载失败' : error,
        onRetry: () =>
            ref.read(userCollectionsProvider.notifier).loadPlaylists(),
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                _searchQuery.isNotEmpty
                    ? '找到 ${albums.length} 张 / 共 $totalCount 张'
                    : '共 $totalCount 张收藏专辑',
                style: kugo.caption,
              ),
            ],
          ),
        ),
        Expanded(
          child: albums.isEmpty
              ? AsyncBody(
                  loading: false,
                  hasError: false,
                  isEmpty: true,
                  emptyMessage: '未找到匹配的专辑',
                  onRetry: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const SizedBox.shrink(),
                )
              : SmoothListViewBuilder(
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final sub = '${album.artist}${album.trackCount > 0 ? " · ${album.trackCount}首" : ""}';
                    return ListTile(
                      leading: CoverHero(
                        tag: KugoHeroTags.albumCover(album.id),
                        seed: album.coverUrl.isNotEmpty
                            ? album.coverUrl
                            : album.id,
                        size: 48,
                        radius: KugoRadius.card,
                        child: album.coverUrl.isEmpty
                            ? const Icon(Icons.album_rounded,
                                color: Colors.white70)
                            : null,
                      ),
                      title: Text(album.name, style: kugo.body),
                      subtitle: Text(sub, style: kugo.caption),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: kugo.textSecondary,
                      ),
                      onTap: () => context.push('/album/${album.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
