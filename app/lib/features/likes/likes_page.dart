import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/netease_login_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/profile/user_collections_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../core/theme/hero_tags.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart' show CoverHero;
import '../../shared/widgets/removable_row.dart';
import 'likes_controller.dart';
import 'netease_likes_controller.dart';
import '../../shared/widgets/smooth_scroll.dart';

enum LikesSortType {
  added('默认排序'),
  name('歌曲名'),
  artist('歌手名');

  const LikesSortType(this.label);
  final String label;
}

/// 排序选择：底部 sheet，标题行「N 首 · 排序」和 AppBar 图标共用。
Future<void> showLikesSortPicker(
  BuildContext context,
  LikesSortType current,
  ValueChanged<LikesSortType> onSelected,
) async {
  final kugo = KugoTheme.of(context);
  final selected = await showKugoBottomSheet<LikesSortType>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        for (final type in LikesSortType.values)
          ListTile(
            title: Text(type.label, style: kugo.body),
            trailing: type == current
                ? Icon(Icons.check_rounded, color: kugo.primary)
                : null,
            onTap: () => Navigator.pop(sheetContext, type),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  if (selected != null) onSelected(selected);
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

  /// 歌曲 Tab 内的音源筛选：`null` = 全部源。初始值取设置里的「默认源」
  /// （只有一个源时不筛选，见方案 §11「切换音源」轻量机制）。
  MusicPlatform? _sourceFilter;

  /// 上一次渲染时用的 Tab 索引。
  int _tabIndex = 0;

  /// 只在索引**真的变了**时重建。
  ///
  /// 原来这里无条件 setState：TabBarView 拖动期间 offset 每帧都在变，
  /// 三个 Tab 的列表（歌单/歌手/专辑）会被逐帧重编一遍。
  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.index == _tabIndex) return;
    _tabIndex = _tabController.index;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _sourceFilter = _registeredPlatforms().length > 1
        ? ref.read(settingsControllerProvider).effectiveDefaultSource
        : null;
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

  /// 已注册且**启用**的音源（源筛选条用）。设置里的整源开关在此过滤。
  List<MusicPlatform> _registeredPlatforms() {
    final enabled = ref.read(settingsControllerProvider).enabledSources;
    return musicSourceRegistry?.platforms
            .where(enabled.contains)
            .toList() ??
        const [];
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
    final neteaseAuth = ref.watch(neteaseLoginControllerProvider);
    final neteaseLikes = ref.watch(neteaseLikesProvider);

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
    final List<Track> kugouTracks =
        auth.isLogged ? collections.cloudFavoriteTracks : localLikes;
    final List<Track> neteaseTracks = neteaseLikes.tracks;

    // 源筛选：`null` = 全部（酷狗在前、网易云在后；不做跨源同曲合并）。
    final List<Track> songsSource = switch (_sourceFilter) {
      MusicPlatform.kugou => kugouTracks,
      MusicPlatform.netease => neteaseTracks,
      null => [...kugouTracks, ...neteaseTracks],
    };

    final displayedSongs = _applyFilterAndSort(songsSource);
    final displayedSingers = _filterSingers(collections.followedSingers);
    final displayedAlbums = _filterAlbums(collections.favoritedAlbums);

    final platforms = _registeredPlatforms();

    // 筛选指向已停用的源（用户在设置里关掉了它）→ 回落到「全部」，
    // 否则列表空白且筛选条上没有可切回的入口。幂等修正，最多改一次。
    if (_sourceFilter != null && !platforms.contains(_sourceFilter)) {
      _sourceFilter = null;
    }

    // 云端 trackCount 可能先于列表到达；取两者较大值，避免「900 进、300 显示」。
    var songsCount = 0;
    if (_sourceFilter != MusicPlatform.netease) {
      songsCount += [
        kugouTracks.length,
        if (auth.isLogged) collections.defaultLikedPlaylist?.trackCount ?? 0,
      ].reduce((a, b) => a > b ? a : b);
    }
    if (_sourceFilter != MusicPlatform.kugou) {
      songsCount += neteaseTracks.length;
    }

    final bool songsBusy = switch (_sourceFilter) {
      MusicPlatform.kugou => collections.isLoadingFavoriteTracks,
      MusicPlatform.netease => neteaseLikes.loading,
      null => collections.isLoadingFavoriteTracks || neteaseLikes.loading,
    };

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
            if (auth.isLogged || neteaseAuth.isLogged)
              IconButton(
                icon: songsBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: '刷新我喜欢歌曲',
                onPressed: songsBusy ? null : _refreshSongs,
              ),
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: '排序方式',
              onPressed: () => showLikesSortPicker(context, _sortType, (t) {
                setState(() => _sortType = t);
              }),
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
              Tab(text: '歌曲 ($songsCount)'),
              Tab(text: '歌手 (${collections.followedSingers.length})'),
              Tab(text: '专辑 (${collections.favoritedAlbums.length})'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 歌曲（源筛选条 + 列表）
          _buildSongsTab(
            kugo: kugo,
            auth: auth,
            collections: collections,
            neteaseAuth: neteaseAuth,
            neteaseLikes: neteaseLikes,
            displayed: displayedSongs,
            totalCount: songsSource.length,
            player: player,
            platforms: platforms,
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

  /// 刷新当前源筛选下的「我喜欢」。
  Future<void> _refreshSongs() async {
    final collections = ref.read(userCollectionsProvider.notifier);
    final netease = ref.read(neteaseLikesProvider.notifier);
    switch (_sourceFilter) {
      case MusicPlatform.kugou:
        await collections.loadFavoriteTracks(force: true);
      case MusicPlatform.netease:
        await netease.load(force: true);
      case null:
        await Future.wait([
          collections.loadFavoriteTracks(force: true),
          netease.load(force: true),
        ]);
    }
  }

  Widget _buildSongsTab({
    required List<Track> displayed,
    required int totalCount,
    required PlayerState player,
    required KugoTheme kugo,
    required AuthState auth,
    required UserCollectionsState collections,
    required NeteaseLoginState neteaseAuth,
    required NeteaseLikesState neteaseLikes,
    required List<MusicPlatform> platforms,
  }) {
    // 选中网易云但未扫码：给登录引导，而不是一个看不懂的空列表。
    if (_sourceFilter == MusicPlatform.netease && !neteaseAuth.isLogged) {
      return _loginPrompt(
        kugo: kugo,
        icon: Icons.cloud_outlined,
        message: '扫码登录网易云后，即可同步云端「我喜欢」',
        route: '/netease-login',
      );
    }

    final bool isLoading = switch (_sourceFilter) {
      MusicPlatform.kugou => collections.isLoadingFavoriteTracks,
      MusicPlatform.netease => neteaseLikes.loading,
      null => collections.isLoadingFavoriteTracks || neteaseLikes.loading,
    };
    if (isLoading && totalCount == 0) {
      return const AsyncBody(
        loading: true,
        hasError: false,
        isEmpty: false,
        child: SizedBox.shrink(),
      );
    }

    final String error = switch (_sourceFilter) {
      MusicPlatform.kugou =>
        auth.isLogged ? collections.favoriteTracksError : '',
      MusicPlatform.netease => neteaseLikes.error,
      null =>
        auth.isLogged ? collections.favoriteTracksError : neteaseLikes.error,
    };

    if (totalCount == 0) {
      // 未登录酷狗时「重试」应当是去登录，而不是空转一次请求。
      final VoidCallback onRetry =
          !auth.isLogged && _sourceFilter != MusicPlatform.netease
              ? () => context.push('/login')
              : _refreshSongs;
      return AsyncBody(
        loading: false,
        hasError: error.isNotEmpty,
        isEmpty: true,
        emptyMessage: error.isNotEmpty ? error : _songsEmptyMessage(auth),
        errorMessage: error.isEmpty ? '加载失败' : error,
        onRetry: onRetry,
        child: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        SourceFilterBar(
          platforms: platforms,
          selected: _sourceFilter,
          onSelect: (p) {
            // 切源同时改写全局默认源（「全部」不写），下个入口跟着走同一源。
            ref
                .read(settingsControllerProvider.notifier)
                .syncDefaultSourceFromFilter(p);
            setState(() => _sourceFilter = p);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            KugoSpacing.sm,
            KugoSpacing.lg,
            KugoSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: _searchQuery.isNotEmpty
                    ? Text(
                        '找到 ${displayed.length} 首 / 共 $totalCount 首',
                        style: kugo.caption,
                      )
                    : TextButton.icon(
                        onPressed: () => showLikesSortPicker(
                          context,
                          _sortType,
                          (t) => setState(() => _sortType = t),
                        ),
                        icon: Icon(
                          Icons.sort_rounded,
                          size: 16,
                          color: kugo.textSecondary,
                        ),
                        label: Text(
                          '${displayed.length} 首 · ${_sortType.label}',
                          style: kugo.caption,
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
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
                    // 红心只对酷狗曲目生效：网易侧取消红心的写口未实测，
                    // 误点会拿网易 songId 去打酷狗删曲（见接口文档 §五 F4/F5）。
                    final isKugou = track.platform == MusicPlatform.kugou;
                    final tile = TrackTile(
                      track: track,
                      isPlaying: player.current?.id == track.id &&
                          player.isPlaying,
                      showSource: _sourceFilter == null && platforms.length > 1,
                      onArtistTap: artistTapFor(context, track),
                      onTap: () {
                        ref
                            .read(playerControllerProvider.notifier)
                            .playQueue(displayed, startIndex: index);
                        context.push('/player');
                      },
                    );
                    // 非酷狗曲目没有可信的取消红心写口，保持跟原来一致（不给按钮）。
                    if (!isKugou) return tile;
                    return RemovableRow(
                      message: '已取消喜欢',
                      onRemove: () =>
                          ref.read(likesProvider.notifier).removeTrack(track),
                      onUndo: () =>
                          ref.read(likesProvider.notifier).toggle(track),
                      builder: (context, requestRemove) => TrackTile(
                        track: track,
                        isPlaying: player.current?.id == track.id &&
                            player.isPlaying,
                        showSource:
                            _sourceFilter == null && platforms.length > 1,
                        trailing: IconButton(
                          tooltip: '取消喜欢',
                          icon: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFE87A90),
                            size: 20,
                          ),
                          onPressed: requestRemove,
                        ),
                        onArtistTap: artistTapFor(context, track),
                        onTap: () {
                          ref
                              .read(playerControllerProvider.notifier)
                              .playQueue(displayed, startIndex: index);
                          context.push('/player');
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _songsEmptyMessage(AuthState auth) {
    switch (_sourceFilter) {
      case MusicPlatform.netease:
        return '网易云「我喜欢」还没有红心歌曲\n在网易云点 ♥ 即可同步到此处';
      case MusicPlatform.kugou:
      case null:
        return !auth.isLogged
            ? '登录酷狗账号后，即可同步云端「我喜欢」'
            : '还没有红心歌曲\n播放时点 ♥ 即可收藏到云端';
    }
  }

  /// 未登录某源时的统一引导（图标 + 文案 + 去登录）。
  Widget _loginPrompt({
    required KugoTheme kugo,
    required IconData icon,
    required String message,
    required String route,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KugoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: kugo.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: KugoSpacing.md),
            Text(
              message,
              style: kugo.caption.copyWith(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KugoSpacing.lg),
            FilledButton(
              onPressed: () => context.push(route),
              child: const Text('立即登录'),
            ),
          ],
        ),
      ),
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
