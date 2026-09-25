import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/catalog_models.dart';
import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../data/repositories/discovery_repository.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// 探索发现 — EchoMusic `Explore.vue` 五 Tab：歌单 / 排行榜 / 新碟上架 / 新歌速递 / 歌手。
///
/// 数据按**音源能力**取（见 `core/source/capabilities.dart`）：
/// - 歌单 / 新歌速递：酷狗与网易都实现（[PlaylistCatalogSource] / [NewSongFeedSource]）；
/// - 排行榜：复用 [RankSource]（网易天生只有官方三榜）；
/// - 新碟上架 / 歌手：本期仅酷狗有接口，非酷狗源出「暂不支持」空态，不做假入口。
class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({super.key});

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['歌单', '排行榜', '新碟上架', '新歌速递', '歌手'];

  late final TabController _tabController;
  int _tab = 0;

  /// 当前音源；`null` = 无可用源（均未注册、未启用或都不具备本页能力）。
  MusicPlatform? _source;

  // 歌单
  List<PlaylistTagGroup> _tagGroups = const [];
  PlaylistTag? _activeTag;
  List<PlaylistBrief> _playlists = const [];
  bool _playlistsLoading = true;
  String _playlistsError = '';
  bool _tagsLoaded = false;

  // 排行榜
  List<PlaylistBrief> _ranks = const [];
  PlaylistBrief? _activeRank;
  List<Track> _rankTracks = const [];
  // 懒加载：初始必须是 false，否则 `isEmpty && !loading` 永远进不去。
  bool _ranksLoading = false;
  bool _rankTracksLoading = false;
  String _ranksError = '';

  // 新碟
  String _albumType = 'all';
  List<AlbumBrief> _albums = const [];
  bool _albumsLoading = false;
  String _albumsError = '';

  // 新歌
  List<Track> _newSongs = const [];
  bool _newSongsLoading = false;
  String _newSongsError = '';

  // 歌手
  String _artistSex = '0';
  String _artistType = '0:0';
  String _activeLetter = '全部';
  List<DiscoveryArtist> _artists = const [];
  bool _artistsLoading = false;
  String _artistsError = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // 选中瞬间就触发懒加载（含 animateTo 中的 indexIsChanging），
    // 不要等动画 settle —— 否则切换过来的 Tab 会先闪一帧空态。
    _tabController.addListener(_handleTabTick);
    _source = _resolveSource(_availableSources());
    _loadPlaylists();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabTick);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabTick() {
    final index = _tabController.index;
    if (_tab != index) {
      setState(() => _tab = index);
    }
    _ensureTab(index);
  }

  void _ensureTab(int index) {
    switch (index) {
      case 0:
        if (!_tagsLoaded && !_playlistsLoading) _loadPlaylists();
      case 1:
        if (_ranks.isEmpty && !_ranksLoading) _loadRanks();
      case 2:
        if (_albums.isEmpty && !_albumsLoading) _loadAlbums();
      case 3:
        if (_newSongs.isEmpty && !_newSongsLoading) _loadNewSongs();
      case 4:
        if (_artists.isEmpty && !_artistsLoading) _loadArtists();
    }
  }

  T? _capability<T>(MusicPlatform? platform) => platform == null
      ? null
      : musicSourceRegistry?.capability<T>(platform);

  /// 已启用、且**该源「发现」功能未关**、并具备本页任一能力的音源。
  ///
  /// 本页各 Tab 能力不同（网易有歌单/榜单/新歌，酷狗五 Tab 齐全），故用「任一能力」
  /// 判定「该源可用于探索发现」；单个 Tab 是否可用再由各 Tab 自己按能力判。
  List<MusicPlatform> _availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final settings = ref.read(settingsControllerProvider);
    return registry.platforms
        .where(
          (p) =>
              settings.isFeatureEnabled(p, SourceFeature.discovery) &&
              (registry.capability<PlaylistCatalogSource>(p) != null ||
                  registry.capability<RankSource>(p) != null ||
                  registry.capability<NewSongFeedSource>(p) != null),
        )
        .toList();
  }

  /// 首选项是设置里的「默认源」；不可用时退首个可用源。
  MusicPlatform? _resolveSource(List<MusicPlatform> available) {
    if (available.isEmpty) return null;
    final preferred =
        ref.read(settingsControllerProvider).effectiveDefaultSource;
    return available.contains(preferred) ? preferred : available.first;
  }

  /// 新碟上架 / 歌手：本期只有酷狗有对应接口（网易无 `/weapi/album/new`、
  /// `/weapi/artist/list` 实测口径），故非酷狗源整 Tab 出「暂不支持」空态；
  /// 不做假入口，等网易接口实测通过后再补能力。
  bool get _legacyCatalogSupported => _source == MusicPlatform.kugou;

  void _switchTo(MusicPlatform platform) {
    if (platform == _source) return;
    setState(() {
      _source = platform;
      _resetData();
    });
    _ensureTab(_tab);
  }

  /// 切源必须清缓存：标签 id / 榜单 id / 曲目 id 都是各源私有的，混用会串源。
  void _resetData() {
    _tagGroups = const [];
    _activeTag = null;
    _tagsLoaded = false;
    _playlists = const [];
    _playlistsLoading = false;
    _playlistsError = '';
    _ranks = const [];
    _activeRank = null;
    _rankTracks = const [];
    _ranksLoading = false;
    _rankTracksLoading = false;
    _ranksError = '';
    _albums = const [];
    _albumsLoading = false;
    _albumsError = '';
    _newSongs = const [];
    _newSongsLoading = false;
    _newSongsError = '';
    _artists = const [];
    _artistsLoading = false;
    _artistsError = '';
    _activeLetter = '全部';
  }

  String _errorText(Object e, String fallback) =>
      e is SourceFailure && e.message.isNotEmpty ? e.message : fallback;

  Future<void> _loadPlaylists() async {
    final source = _source;
    final catalog = _capability<PlaylistCatalogSource>(source);
    if (catalog == null) {
      setState(() {
        _playlists = const [];
        _playlistsLoading = false;
        _playlistsError = '';
      });
      return;
    }
    setState(() {
      _playlistsLoading = true;
      _playlistsError = '';
    });
    if (!_tagsLoaded) {
      List<PlaylistTagGroup> groups;
      try {
        groups = await catalog.playlistTagGroups();
      } catch (_) {
        // 分类拿不到不挡歌单：下面用各源自己的默认分类兜底。
        groups = const [];
      }
      if (!mounted || source != _source) return;
      _tagGroups = groups;
      _tagsLoaded = true;
      _activeTag = groups.isEmpty ? null : groups.first.child.first;
    }

    List<PlaylistBrief> playlists = const [];
    var error = '';
    try {
      playlists = await catalog.categoryPlaylists(
        cat: _activeTag?.id ?? '',
        pageSize: 30,
      );
    } catch (e) {
      error = _errorText(e, '歌单加载失败，请检查网络后重试');
    }
    // 切源后到达的旧响应直接丢弃。
    if (!mounted || source != _source) return;
    setState(() {
      _playlists = playlists;
      _playlistsLoading = false;
      _playlistsError = error;
    });
  }

  Future<void> _loadRanks() async {
    final source = _source;
    final rankSource = _capability<RankSource>(source);
    if (rankSource == null) {
      setState(() {
        _ranks = const [];
        _ranksLoading = false;
        _ranksError = '';
      });
      return;
    }
    setState(() {
      _ranksLoading = true;
      _ranksError = '';
    });
    List<PlaylistBrief> ranks = const [];
    var error = '';
    try {
      ranks = await rankSource.rankBoards();
    } catch (e) {
      error = _errorText(e, '排行榜加载失败，请检查网络后重试');
    }
    if (!mounted || source != _source) return;
    setState(() {
      _ranks = ranks;
      _ranksLoading = false;
      if (ranks.isEmpty) {
        _ranksError =
            error.isEmpty ? '排行榜加载失败，请检查网络后重试' : error;
      } else {
        _activeRank = ranks.first;
      }
    });
    final active = _activeRank;
    if (active != null && _rankTracks.isEmpty) {
      await _loadRankTracks(active);
    }
  }

  Future<void> _loadRankTracks(PlaylistBrief rank) async {
    final source = _source;
    final rankSource = _capability<RankSource>(source);
    if (rankSource == null) return;
    setState(() {
      _activeRank = rank;
      _rankTracksLoading = true;
    });
    List<Track> tracks = const [];
    try {
      tracks = await rankSource.rankTracks(rank.id);
    } catch (_) {
      tracks = const [];
    }
    if (!mounted || source != _source) return;
    setState(() {
      _rankTracks = tracks;
      _rankTracksLoading = false;
    });
  }

  Future<void> _loadAlbums() async {
    if (!_legacyCatalogSupported) {
      setState(() {
        _albums = const [];
        _albumsLoading = false;
        _albumsError = '';
      });
      return;
    }
    setState(() {
      _albumsLoading = true;
      _albumsError = '';
    });
    final result = await discoveryRepository.fetchNewAlbums(type: _albumType);
    if (!mounted) return;
    setState(() {
      _albums = result.items;
      _albumsLoading = false;
      _albumsError = result.error;
    });
  }

  Future<void> _loadNewSongs() async {
    final source = _source;
    final feed = _capability<NewSongFeedSource>(source);
    if (feed == null) {
      setState(() {
        _newSongs = const [];
        _newSongsLoading = false;
        _newSongsError = '';
      });
      return;
    }
    setState(() {
      _newSongsLoading = true;
      _newSongsError = '';
    });
    List<Track> songs = const [];
    var error = '';
    try {
      songs = await feed.newSongs(pageSize: 50);
    } catch (e) {
      error = _errorText(e, '新歌加载失败，请检查网络后重试');
    }
    if (!mounted || source != _source) return;
    setState(() {
      _newSongs = songs;
      _newSongsLoading = false;
      _newSongsError = error;
    });
  }

  Future<void> _loadArtists() async {
    if (!_legacyCatalogSupported) {
      setState(() {
        _artists = const [];
        _artistsLoading = false;
        _artistsError = '';
      });
      return;
    }
    setState(() {
      _artistsLoading = true;
      _artistsError = '';
    });
    final sex = int.tryParse(_artistSex) ?? 0;
    final parts = _artistType.split(':');
    final result = await discoveryRepository.fetchArtists(
      sextype: sex,
      type: int.tryParse(parts.elementAt(0)) ?? 0,
      musician: int.tryParse(parts.elementAt(1)) ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _artists = result.items;
      _artistsLoading = false;
      _artistsError = result.error;
      if (_artists.isNotEmpty) {
        final hot = _artists
            .map((a) => a.letter)
            .firstWhere((l) => l.isNotEmpty, orElse: () => '全部');
        if (_activeLetter != '全部' &&
            !_artists.any((a) => a.letter == _activeLetter)) {
          _activeLetter = hot == '' ? '全部' : hot;
        }
      }
    });
  }

  /// 榜单来源说明：同源榜单共用同一个 `rankTypeName` 时说明「共几个」——
  /// 网易天生只有官方三榜，不说明用户容易以为漏了榜。
  String get _rankHint {
    if (_ranks.isEmpty) return '';
    final labels = <String>{
      for (final r in _ranks)
        if (r.rankTypeName.trim().isNotEmpty) r.rankTypeName.trim(),
    };
    if (labels.length != 1) return '';
    return '${labels.first} · 共 ${_ranks.length} 个榜单';
  }

  /// 非酷狗源必须带 `?src=`，详情页据此按源取数（同 common.dart `artistTapFor`）。
  String _playlistRoute(PlaylistBrief playlist) {
    final src = playlist.platform == MusicPlatform.kugou
        ? ''
        : '?src=${playlist.platform.wireName}';
    return '/playlist/${playlist.id}$src';
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final settings = ref.watch(settingsControllerProvider);

    // 设置里改动整源开关或「发现」功能开关后回到本页：重算可用源，必要时切源并清缓存重取。
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.enabledSources == next.enabledSources &&
          prev?.disabledFeatures == next.disabledFeatures) {
        return;
      }
      final available = _availableSources();
      if (available.isEmpty) {
        if (_source != null) {
          setState(() {
            _source = null;
            _resetData();
          });
        }
        return;
      }
      if (_source == null || !available.contains(_source)) {
        _switchTo(_resolveSource(available) ?? available.first);
      }
    });

    final available = _availableSources();
    if (available.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('探索发现')),
        body: SourceDisabledView(
          platform: settings.effectiveDefaultSource,
          feature: settings.featureSwitchCause(SourceFeature.discovery),
        ),
      );
    }
    final active = _source ?? available.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('探索发现'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _tabs) Tab(text: t)],
        ),
      ),
      body: Column(
        children: [
          if (available.length > 1)
            SourceFilterBar(
              platforms: available,
              selected: active,
              showAll: false,
              onSelect: (p) {
                // 切源同时改写全局默认源（「全部」不写），下个入口跟着走同一源。
                ref
                    .read(settingsControllerProvider.notifier)
                    .syncDefaultSourceFromFilter(p);
                if (p != null) _switchTo(p);
              },
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _capability<PlaylistCatalogSource>(active) == null
                    ? _unsupportedTab('歌单')
                    : _buildPlaylistsTab(kugo),
                _capability<RankSource>(active) == null
                    ? _unsupportedTab('排行榜')
                    : _buildRanksTab(kugo),
                !_legacyCatalogSupported
                    ? _unsupportedTab('新碟上架')
                    : _buildAlbumsTab(kugo),
                _capability<NewSongFeedSource>(active) == null
                    ? _unsupportedTab('新歌速递')
                    : _buildNewSongsTab(kugo),
                !_legacyCatalogSupported
                    ? _unsupportedTab('歌手')
                    : _buildArtistsTab(kugo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「该源不支持这个 Tab」：不做假入口，也不用整源停用文案（源其实开着）。
  Widget _unsupportedTab(String tab) {
    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: KugoSpacing.xxl),
            child: AsyncBody(
              loading: false,
              hasError: false,
              isEmpty: true,
              emptyMessage:
                  '${_source?.label ?? ''}暂不支持「$tab」，可切换其他音源查看',
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chipRow(List<Widget> children) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ]),
    );
  }

  Widget _buildPlaylistsTab(KugoTheme kugo) {
    final tags = [
      for (final g in _tagGroups)
        for (final t in g.child)
          ChoiceChip(
            label: Text(t.name),
            selected: _activeTag?.id == t.id,
            onSelected: (_) {
              if (_activeTag?.id == t.id) return;
              setState(() => _activeTag = t);
              _loadPlaylists();
            },
          ),
    ];
    return SmoothCustomScrollView(
      slivers: [
        if (tags.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KugoSpacing.md),
              child: _chipRow(tags),
            ),
          ),
        _gridSliver(
          loading: _playlistsLoading,
          error: _playlistsError,
          empty: _playlists.isEmpty,
          emptyMessage: '暂无歌单',
          onRetry: _loadPlaylists,
          itemCount: _playlists.length,
          itemBuilder: (context, index) {
            final playlist = _playlists[index];
            return PlaylistCard(
              playlist: playlist,
              width: double.infinity,
              // 多源时给封面角标标明这份歌单来自哪个源（单源靠页头/底部小字）。
              platform: _availableSources().length > 1 ? _source : null,
              onTap: () => context.push(
                _playlistRoute(playlist),
                extra: playlist,
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildRanksTab(KugoTheme kugo) {
    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              KugoSpacing.md,
              KugoSpacing.lg,
              KugoSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _RankPicker(
                    ranks: _ranks,
                    active: _activeRank,
                    onChanged: (r) {
                      if (r == null || r.id == _activeRank?.id) return;
                      _loadRankTracks(r);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => context.push('/ranks'),
                  child: const Text('全部榜单'),
                ),
              ],
            ),
          ),
        ),
        if (_rankHint.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KugoSpacing.lg,
                0,
                KugoSpacing.lg,
                KugoSpacing.sm,
              ),
              child: Text(
                _rankHint,
                style: kugo.caption.copyWith(color: kugo.textTertiary),
              ),
            ),
          ),
        if (_rankTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: SectionHeader(
              title: _activeRank?.name ?? '排行榜',
              showAccent: true,
              actionLabel: '播放全部',
              onAction: () {
                ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(_rankTracks, startIndex: 0);
                context.push('/player');
              },
            ),
          ),
        _songSliver(
          loading: _ranksLoading || _rankTracksLoading,
          error: _ranksError,
          songs: _rankTracks,
          emptyMessage: '暂无榜单歌曲',
          onRetry: () {
            final r = _activeRank;
            if (r != null) {
              _loadRankTracks(r);
            } else {
              _loadRanks();
            }
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildAlbumsTab(KugoTheme kugo) {
    final chips = [
      for (final t in DiscoveryRepository.albumTypes)
        ChoiceChip(
          label: Text(t.label),
          selected: _albumType == t.id,
          onSelected: (_) {
            if (_albumType == t.id) return;
            setState(() => _albumType = t.id);
            _loadAlbums();
          },
        ),
    ];
    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KugoSpacing.md),
            child: _chipRow(chips),
          ),
        ),
        _gridSliver(
          loading: _albumsLoading,
          error: _albumsError,
          empty: _albums.isEmpty,
          emptyMessage: '暂无新碟',
          onRetry: _loadAlbums,
          itemCount: _albums.length,
          itemBuilder: (context, index) {
            final album = _albums[index];
            return _AlbumGridCard(
              album: album,
              onTap: () => context.push('/album/${album.id}'),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildNewSongsTab(KugoTheme kugo) {
    return SmoothCustomScrollView(
      slivers: [
        if (_newSongs.isNotEmpty)
          SliverToBoxAdapter(
            child: SectionHeader(
              title: '新歌速递',
              showAccent: true,
              actionLabel: '播放全部',
              onAction: () {
                ref
                    .read(playerControllerProvider.notifier)
                    .playQueue(_newSongs, startIndex: 0);
                context.push('/player');
              },
            ),
          ),
        _songSliver(
          loading: _newSongsLoading,
          error: _newSongsError,
          songs: _newSongs,
          emptyMessage: '暂无新歌',
          onRetry: _loadNewSongs,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildArtistsTab(KugoTheme kugo) {
    final sexChips = [
      for (final t in DiscoveryRepository.artistSexTypes)
        ChoiceChip(
          label: Text(t.label),
          selected: _artistSex == t.id,
          onSelected: (_) {
            if (_artistSex == t.id) return;
            setState(() => _artistSex = t.id);
            _loadArtists();
          },
        ),
    ];
    final typeChips = [
      for (final t in DiscoveryRepository.artistTypes)
        ChoiceChip(
          label: Text(t.label),
          selected: _artistType == t.id,
          onSelected: (_) {
            if (_artistType == t.id) return;
            setState(() => _artistType = t.id);
            _loadArtists();
          },
        ),
    ];
    final letters = <String>{'全部'};
    for (final a in _artists) {
      if (a.letter.isNotEmpty) letters.add(a.letter);
    }
    final visible = _activeLetter == '全部'
        ? _artists
        : _artists.where((a) => a.letter == _activeLetter).toList();

    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KugoSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chipRow(sexChips),
                const SizedBox(height: 8),
                _chipRow(typeChips),
                if (letters.length > 1) ...[
                  const SizedBox(height: 8),
                  _chipRow([
                    for (final l in letters)
                      ChoiceChip(
                        label: Text(l),
                        selected: _activeLetter == l,
                        onSelected: (_) =>
                            setState(() => _activeLetter = l),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ),
        _gridSliver(
          loading: _artistsLoading,
          error: _artistsError,
          empty: visible.isEmpty,
          emptyMessage: '暂无歌手',
          onRetry: _loadArtists,
          itemCount: visible.length,
          // 歌手头像要比歌单封面更碎：宽屏 8 列会把圆撑到 300px+。
          // 0.78 留出「圆 + 间距 + 名字」的高度，避免 BOTTOM OVERFLOW。
          preferredExtent: 112,
          maxColumns: 16,
          mobileAspectRatio: 0.78,
          desktopAspectRatio: 0.78,
          itemBuilder: (context, index) {
            final artist = visible[index];
            return _ArtistGridCard(
              artist: artist,
              onTap: () => context.push('/artist/${artist.id}'),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _gridSliver({
    required bool loading,
    required String error,
    required bool empty,
    required String emptyMessage,
    required VoidCallback onRetry,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    double preferredExtent = kDesktopCoverExtent,
    int maxColumns = 8,
    double mobileAspectRatio = 0.72,
    double desktopAspectRatio = 0.72,
  }) {
    if (loading && itemCount == 0) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(KugoSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (empty && error.isNotEmpty) {
      return SliverToBoxAdapter(
        child: AsyncBody(
          loading: false,
          hasError: true,
          isEmpty: false,
          errorMessage: error,
          onRetry: onRetry,
          child: const SizedBox.shrink(),
        ),
      );
    }
    if (empty) {
      return SliverToBoxAdapter(
        child: AsyncBody(
          loading: false,
          hasError: false,
          isEmpty: true,
          emptyMessage: emptyMessage,
          onRetry: onRetry,
          child: const SizedBox.shrink(),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width - KugoSpacing.lg * 2;
            final grid = coverGridDelegateForWidth(
              context,
              width,
              preferredExtent: preferredExtent,
              mobileAspectRatio: mobileAspectRatio,
              desktopAspectRatio: desktopAspectRatio,
              mainAxisSpacing: KugoSpacing.lg,
              crossAxisSpacing: KugoSpacing.lg,
              maxColumns: maxColumns,
            );
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: grid,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            );
          },
        ),
      ),
    );
  }

  Widget _songSliver({
    required bool loading,
    required String error,
    required List<Track> songs,
    required String emptyMessage,
    required VoidCallback onRetry,
  }) {
    if (loading && songs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(KugoSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (songs.isEmpty) {
      return SliverToBoxAdapter(
        child: AsyncBody(
          loading: false,
          hasError: error.isNotEmpty,
          isEmpty: error.isEmpty,
          errorMessage: error.isEmpty ? emptyMessage : error,
          emptyMessage: emptyMessage,
          onRetry: onRetry,
          child: const SizedBox.shrink(),
        ),
      );
    }
    final player = ref.watch(playerControllerProvider);
    return SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final track = songs[index];
        return TrackTile(
          track: track,
          index: index + 1,
          isPlaying: player.current?.id == track.id && player.isPlaying,
          onArtistTap: artistTapFor(context, track),
          onTap: () {
            ref
                .read(playerControllerProvider.notifier)
                .playQueue(songs, startIndex: index);
            context.push('/player');
          },
        );
      },
    );
  }
}

class _RankPicker extends StatelessWidget {
  const _RankPicker({
    required this.ranks,
    required this.active,
    required this.onChanged,
  });

  final List<PlaylistBrief> ranks;
  final PlaylistBrief? active;
  final ValueChanged<PlaylistBrief?> onChanged;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final activeId = active?.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kugo.surface,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        border: Border.all(color: kugo.divider),
      ),
      child: DropdownButton<String>(
        value: ranks.any((r) => r.id == activeId) ? activeId : null,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        hint: Text('选择榜单', style: kugo.caption.copyWith(fontSize: 13)),
        items: [
          for (final r in ranks)
            DropdownMenuItem<String>(
              value: r.id,
              child: Text(
                r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kugo.body.copyWith(fontSize: 13),
              ),
            ),
        ],
        onChanged: ranks.isEmpty
            ? null
            : (id) {
                if (id == null) return;
                for (final r in ranks) {
                  if (r.id == id) {
                    onChanged(r);
                    return;
                  }
                }
              },
      ),
    );
  }
}

class _AlbumGridCard extends StatelessWidget {
  const _AlbumGridCard({required this.album, required this.onTap});

  final AlbumBrief album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final meta = [
      if (album.artist.isNotEmpty) album.artist,
      if (album.publishDate.isNotEmpty) album.publishDate,
      if (album.trackCount > 0) '${album.trackCount}首',
    ].join(' · ');
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KugoRadius.card),
              child: CoverBox(
                seed: album.coverUrl,
                size: double.infinity,
                radius: KugoRadius.card,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kugo.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kugo.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ArtistGridCard extends StatelessWidget {
  const _ArtistGridCard({required this.artist, required this.onTap});

  final DiscoveryArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const labelH = 18.0;
    const gap = 6.0;
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 圆直径取 min(宽, 高-名字行)，保证名字永远放得下、圆也不会被拉高。
          final byWidth = constraints.maxWidth;
          final byHeight = constraints.maxHeight - labelH - gap;
          final d = (byWidth < byHeight ? byWidth : byHeight).clamp(0.0, 240.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: d,
                height: d,
                child: ClipOval(
                  child: CoverBox(
                    seed: artist.avatarUrl,
                    size: d,
                    radius: 999,
                  ),
                ),
              ),
              const SizedBox(height: gap),
              SizedBox(
                height: labelH,
                child: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: KugoTheme.of(context).body.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
