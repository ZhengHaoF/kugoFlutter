import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/catalog_models.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../data/repositories/recommend_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// 为你推荐聚合页（对齐 EchoMusic Home.vue「为您推荐」信息架构）。
///
/// 区块独立加载、诚实空态/错误，不造假数据；每日推荐仍走 `/daily` 专页。
class RecommendHubPage extends ConsumerStatefulWidget {
  const RecommendHubPage({super.key});

  @override
  ConsumerState<RecommendHubPage> createState() => _RecommendHubPageState();
}

class _Sec<T> {
  _Sec({this.data, this.loading = true, this.error = ''});

  T? data;
  bool loading;
  String error;
}

class _RecommendHubPageState extends ConsumerState<RecommendHubPage> {
  /// 当前音源；`null` = 无可用源（均未注册 / 未启用 / 都不具备本页能力）。
  MusicPlatform? _source;

  // 「风格」：酷狗是歌曲流（`everyday_style_recommend` 专属链路，无能力契约）；
  // 网易退化为「风格歌单」（标签 chips + 歌单网格，复用 [PlaylistCatalogSource]）。
  _Sec<StyleRecommendResult> _style = _Sec(loading: true);
  List<PlaylistTagGroup> _styleTags = const [];
  PlaylistTag? _activeStyleTag;
  List<PlaylistBrief> _stylePlaylists = const [];
  bool _stylePlaylistsLoading = true;
  String _stylePlaylistsError = '';

  // 「推荐歌单」「编辑精选」：按 [RecommendFeedSource] 能力分发。
  _Sec<List<PlaylistBrief>> _playlists = _Sec(loading: true);
  _Sec<List<PlaylistBrief>> _editorial = _Sec(loading: true);

  final Set<String> _selectedTagIds = <String>{};
  String _activeGroupName = '';
  String _playlistCategoryId = '0';
  int _styleRequestId = 0;
  int _stylePlaylistRequestId = 0;
  int _playlistRequestId = 0;
  int _editorialRequestId = 0;

  @override
  void initState() {
    super.initState();
    _source = _resolveSource(_availableSources());
    _loadAll();
  }

  void _loadAll() {
    _loadStyle();
    _loadPlaylists();
    _loadEditorial();
  }

  T? _capability<T>(MusicPlatform? platform) => platform == null
      ? null
      : musicSourceRegistry?.capability<T>(platform);

  /// 已注册、已启用且具备「推荐聚合」能力的音源（本页三块内容都依赖它）。
  List<MusicPlatform> _availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final enabled = ref.read(settingsControllerProvider).enabledSources;
    return registry.platforms
        .where(
          (p) =>
              enabled.contains(p) &&
              registry.capability<RecommendFeedSource>(p) != null,
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

  /// 「风格」是否退化为歌单形态：只有酷狗有风格歌曲流专属链路。
  bool get _styleAsPlaylists => _source != MusicPlatform.kugou;

  String _errorText(Object e, String fallback) =>
      e is SourceFailure && e.message.isNotEmpty ? e.message : fallback;

  void _switchTo(MusicPlatform platform) {
    if (platform == _source) return;
    setState(() {
      _source = platform;
      _resetData();
    });
    _loadAll();
  }

  /// 切源必须清缓存：标签 id / 歌单 id / 曲目 id 都是各源私有的，混用会串源；
  /// 同时递增请求号，把在途的旧响应全部作废。
  void _resetData() {
    _style = _Sec(loading: true);
    _styleTags = const [];
    _activeStyleTag = null;
    _stylePlaylists = const [];
    _stylePlaylistsLoading = true;
    _stylePlaylistsError = '';
    _playlists = _Sec(loading: true);
    _editorial = _Sec(loading: true);
    _selectedTagIds.clear();
    _activeGroupName = '';
    _playlistCategoryId = '0';
    _styleRequestId++;
    _stylePlaylistRequestId++;
    _playlistRequestId++;
    _editorialRequestId++;
  }

  /// 风格板块入口：酷狗走歌曲流，其余源走风格歌单。
  Future<void> _loadStyle({bool useSelectedTags = false}) {
    if (_styleAsPlaylists) return _loadStylePlaylists(reloadTags: true);
    return _loadKugouStyle(useSelectedTags: useSelectedTags);
  }

  Future<void> _loadKugouStyle({bool useSelectedTags = false}) async {
    if (_source != MusicPlatform.kugou) return;
    final requestId = ++_styleRequestId;
    setState(() {
      _style = _Sec(loading: true);
    });
    final tagids =
        useSelectedTags ? _selectedTagIds.join(',') : '';
    final result = await recommendRepository.fetchStyleRecommend(tagids: tagids);
    if (!mounted || requestId != _styleRequestId) return;
    setState(() {
      _style = _Sec(
        data: result,
        loading: false,
        error: result.tracks.isEmpty && result.groups.isEmpty
            ? result.error
            : '',
      );
      final groups = result.groups;
      if (groups.isNotEmpty) {
        if (_activeGroupName.isEmpty ||
            !groups.any((g) => g.name == _activeGroupName)) {
          _activeGroupName = groups.first.name;
        }
        if (!useSelectedTags && _selectedTagIds.isEmpty) {
          for (final g in groups) {
            for (final t in g.child) {
              if (t.isDefault) _selectedTagIds.add(t.id);
            }
          }
        }
      }
    });
  }

  /// 非酷狗源的「风格歌单」：一次取标签，之后切换标签只重取歌单。
  Future<void> _loadStylePlaylists({bool reloadTags = false}) async {
    final source = _source;
    final catalog = _capability<PlaylistCatalogSource>(source);
    if (catalog == null) return;
    final requestId = ++_stylePlaylistRequestId;
    setState(() {
      _stylePlaylistsLoading = true;
      _stylePlaylistsError = '';
    });

    if (reloadTags || _styleTags.isEmpty) {
      List<PlaylistTagGroup> tags;
      try {
        tags = await catalog.playlistTagGroups();
      } catch (_) {
        // 标签拿不到不挡歌单：下面用该源默认分类（空串）兜底。
        tags = const [];
      }
      if (!mounted || requestId != _stylePlaylistRequestId) return;
      setState(() {
        _styleTags = tags;
        final current = _activeStyleTag?.id;
        final flat = [for (final g in tags) ...g.child];
        if (flat.isNotEmpty &&
            (current == null || !flat.any((t) => t.id == current))) {
          _activeStyleTag = flat.first;
        }
      });
    }

    List<PlaylistBrief> playlists = const [];
    var error = '';
    try {
      playlists = await catalog.categoryPlaylists(
        cat: _activeStyleTag?.id ?? '',
        pageSize: 30,
      );
    } catch (e) {
      error = _errorText(e, '风格歌单加载失败，请检查网络后重试');
    }
    if (!mounted || requestId != _stylePlaylistRequestId) return;
    setState(() {
      _stylePlaylists = playlists;
      _stylePlaylistsLoading = false;
      _stylePlaylistsError = error;
    });
  }

  Future<void> _loadPlaylists() async {
    final feed = _capability<RecommendFeedSource>(_source);
    if (feed == null) return;
    final requestId = ++_playlistRequestId;
    final cat = _playlistCategoryId;
    setState(() {
      _playlists = _Sec(loading: true);
    });
    List<PlaylistBrief> items = const [];
    var error = '';
    try {
      items = await feed.recommendPlaylists(cat: cat);
    } catch (e) {
      error = _errorText(e, '推荐歌单加载失败，请检查网络后重试');
    }
    if (!mounted || requestId != _playlistRequestId) return;
    setState(() {
      _playlists = _Sec(
        data: items,
        loading: false,
        error: items.isEmpty ? error : '',
      );
    });
  }

  Future<void> _loadEditorial() async {
    final feed = _capability<RecommendFeedSource>(_source);
    if (feed == null) return;
    final requestId = ++_editorialRequestId;
    setState(() {
      _editorial = _Sec(loading: true);
    });
    List<PlaylistBrief> items = const [];
    var error = '';
    try {
      items = await feed.editorialPlaylists();
    } catch (e) {
      error = _errorText(e, '编辑精选加载失败，请检查网络后重试');
    }
    if (!mounted || requestId != _editorialRequestId) return;
    setState(() {
      _editorial = _Sec(
        data: items,
        loading: false,
        error: items.isEmpty ? error : '',
      );
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadStyle(useSelectedTags: _selectedTagIds.isNotEmpty),
      _loadPlaylists(),
      _loadEditorial(),
    ]);
  }

  void _toggleStyleTag(StyleTag tag) {
    setState(() {
      if (!_selectedTagIds.remove(tag.id)) {
        _selectedTagIds.add(tag.id);
      }
    });
    _loadKugouStyle(useSelectedTags: true);
  }

  void _selectStyleTag(PlaylistTag tag) {
    if (_activeStyleTag?.id == tag.id) return;
    setState(() => _activeStyleTag = tag);
    _loadStylePlaylists();
  }

  List<Track> get _styleTracks => _style.data?.tracks ?? const [];

  String get _styleSummary {
    if (_selectedTagIds.isEmpty) return '默认推荐';
    final names = <String>[];
    for (final g in _style.data?.groups ?? const <StyleTagGroup>[]) {
      for (final t in g.child) {
        if (_selectedTagIds.contains(t.id)) names.add(t.name);
      }
    }
    return names.isEmpty ? '默认推荐' : names.join(' / ');
  }

  void _playStyleAll() {
    final tracks = _styleTracks;
    if (tracks.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playQueue(tracks, startIndex: 0);
    context.push('/player');
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
    final player = ref.watch(playerControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);

    ref.listen(authControllerProvider, (prev, next) {
      final wasLogged = prev?.isLogged ?? false;
      if (!wasLogged && next.isLogged) {
        _refreshAll();
      }
    });

    // 设置里改动整源开关后回到本页：可用源变了就切源并清缓存重取。
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.enabledSources == next.enabledSources) return;
      final avail = _availableSources();
      if (avail.isEmpty) {
        if (_source != null) {
          setState(() {
            _source = null;
            _resetData();
          });
        }
        return;
      }
      if (_source == null || !avail.contains(_source)) {
        _switchTo(_resolveSource(avail) ?? avail.first);
      }
    });

    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 6 => '凌晨好',
      < 9 => '早上好',
      < 12 => '上午好',
      < 14 => '中午好',
      < 18 => '下午好',
      _ => '晚上好',
    };

    final styleTracks = _styleTracks;
    final styleGroups = _style.data?.groups ?? const <StyleTagGroup>[];
    final playlistItems = _playlists.data ?? const <PlaylistBrief>[];
    final editorialItems = _editorial.data ?? const <PlaylistBrief>[];

    // 整源开关：所有可用源都被停用/未注册 → 整页停用空态
    // （区别于「源可用但板块无数据」的板块级空态）。
    final available = _availableSources();
    final active = _source ?? (available.isEmpty ? null : available.first);
    if (active == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('为你推荐')),
        body: SourceDisabledView(platform: settings.effectiveDefaultSource),
      );
    }

    // 只有酷狗有「风格歌曲流」；其余源这一块退化为「风格歌单」。
    final styleAsPlaylists = active != MusicPlatform.kugou;

    return Scaffold(
      appBar: AppBar(
        title: const Text('为你推荐'),
        actions: [
          if (!auth.isLogged)
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (available.length > 1)
            SourceFilterBar(
              platforms: available,
              selected: active,
              showAll: false,
              onSelect: (p) {
                if (p != null) _switchTo(p);
              },
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              child: SmoothCustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KugoSpacing.lg,
                        KugoSpacing.md,
                        KugoSpacing.lg,
                        KugoSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.isLogged ? greeting : '为你推荐',
                            style: kugo.greeting,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '由此开启好心情 ~',
                            style: kugo.caption.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: KugoSpacing.lg),
                          const _FeatureEntryRow(),
                        ],
                      ),
                    ),
                  ),

                  // 风格：酷狗 = 风格歌曲流；其余源 = 风格歌单
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: styleAsPlaylists ? '风格歌单' : '风格推荐',
                      showAccent: true,
                      actionLabel:
                          styleAsPlaylists || styleTracks.isEmpty ? null : '播放全部',
                      onAction:
                          styleAsPlaylists || styleTracks.isEmpty ? null : _playStyleAll,
                    ),
                  ),
                  if (styleAsPlaylists)
                    ..._stylePlaylistSlivers()
                  else
                    SliverToBoxAdapter(
                      child: _StylePanel(
                        loading: _style.loading,
                        error: _style.error,
                        groups: styleGroups,
                        activeGroupName: _activeGroupName,
                        selectedTagIds: _selectedTagIds,
                        summary: _styleSummary,
                        tracks: styleTracks,
                        isPlaying: (track) =>
                            player.current?.id == track.id && player.isPlaying,
                        onGroupTap: (name) =>
                            setState(() => _activeGroupName = name),
                        onTagTap: _toggleStyleTag,
                        onRetry: () => _loadStyle(
                          useSelectedTags: _selectedTagIds.isNotEmpty,
                        ),
                        onTrackTap: (index) {
                          ref
                              .read(playerControllerProvider.notifier)
                              .playQueue(styleTracks, startIndex: index);
                          context.push('/player');
                        },
                      ),
                    ),

                  // 推荐歌单
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: '推荐歌单',
                      showAccent: true,
                    ),
                  ),
                  // 分类 chips 是酷狗口径（categoryid）；网易个性推荐无分类维度。
                  if (!styleAsPlaylists)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final cat
                                  in RecommendRepository
                                      .recommendPlaylistCategories)
                                ChoiceChip(
                                  label: Text(cat.label),
                                  selected: _playlistCategoryId == cat.id,
                                  onSelected: (_) {
                                    if (_playlistCategoryId == cat.id) return;
                                    setState(
                                      () => _playlistCategoryId = cat.id,
                                    );
                                    _loadPlaylists();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ..._playlistSlivers(
                    loading: _playlists.loading,
                    error: _playlists.error,
                    items: playlistItems,
                    onRetry: _loadPlaylists,
                    emptyMessage: '暂无推荐歌单',
                  ),

                  // 编辑精选
                  SliverToBoxAdapter(
                    child: const SectionHeader(title: '编辑精选', showAccent: true),
                  ),
                  ..._playlistSlivers(
                    loading: _editorial.loading,
                    error: _editorial.error,
                    items: editorialItems,
                    onRetry: _loadEditorial,
                    emptyMessage: '暂无编辑精选',
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 140)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 非酷狗源「风格歌单」：标签 chips + 歌单网格（对齐探索发现「歌单」Tab 形态）。
  List<Widget> _stylePlaylistSlivers() {
    final tags = [
      for (final g in _styleTags)
        for (final t in g.child)
          ChoiceChip(
            label: Text(t.name),
            selected: _activeStyleTag?.id == t.id,
            onSelected: (_) => _selectStyleTag(t),
          ),
    ];
    return [
      if (tags.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              0,
              KugoSpacing.lg,
              KugoSpacing.md,
            ),
            child: Wrap(spacing: 8, runSpacing: 8, children: tags),
          ),
        ),
      ..._playlistSlivers(
        loading: _stylePlaylistsLoading,
        error: _stylePlaylistsError,
        items: _stylePlaylists,
        onRetry: () => _loadStylePlaylists(),
        emptyMessage: '暂无风格歌单',
      ),
    ];
  }

  List<Widget> _playlistSlivers({
    required bool loading,
    required String error,
    required List<PlaylistBrief> items,
    required VoidCallback onRetry,
    String emptyMessage = '暂无内容',
  }) {
    if (loading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(KugoSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _SectionStatus(
            message: error.isEmpty ? emptyMessage : error,
            onRetry: onRetry,
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth.isFinite &&
                      constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width - KugoSpacing.lg * 2;
              final grid = coverGridDelegateForWidth(
                context,
                contentWidth,
                preferredExtent: kDesktopCoverExtent,
                mobileAspectRatio: 0.72,
                desktopAspectRatio: 0.72,
                mainAxisSpacing: KugoSpacing.lg,
                crossAxisSpacing: KugoSpacing.lg,
                maxColumns: 10,
              );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: grid,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final playlist = items[index];
                  return PlaylistCard(
                    playlist: playlist,
                    width: double.infinity,
                    onTap: () => context.push(
                      _playlistRoute(playlist),
                      extra: playlist,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ];
  }
}

class _FeatureEntryRow extends StatelessWidget {
  const _FeatureEntryRow();

  @override
  Widget build(BuildContext context) {
    final day = DateTime.now().day.toString();
    return Row(
      children: [
        Expanded(
          child: _FeatureCard(
            key: const ValueKey('hub_daily_card'),
            badge: day,
            heroTag: KugoHeroTags.dailyRecommendBadge,
            title: '每日推荐',
            subtitle: '为你量身定制',
            usePrimaryGradient: true,
            onTap: () => context.push('/daily'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FeatureCard(
            key: const ValueKey('hub_rank_card'),
            badge: 'TOP',
            title: '排行榜',
            subtitle: '实时热门趋势',
            usePrimaryGradient: false,
            onTap: () => context.push('/ranks'),
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.usePrimaryGradient,
    this.heroTag,
    required this.onTap,
  });

  final String badge;
  final String title;
  final String subtitle;
  final bool usePrimaryGradient;
  final String? heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final gradient = usePrimaryGradient
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kugo.primary,
              Color.lerp(kugo.primary, kugo.secondary, 0.35)!,
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kugo.secondary,
              Color.lerp(kugo.secondary, kugo.primary, 0.40)!,
            ],
          );
    final accent = usePrimaryGradient ? kugo.primary : kugo.secondary;

    final badgeContainer = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: gradient,
      ),
      alignment: Alignment.center,
      child: Text(
        badge,
        style: TextStyle(
          color: Colors.white,
          fontSize: badge.length > 2 ? 12 : 16,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          decoration: TextDecoration.none,
        ),
      ),
    );

    final badgeWidget = (heroTag != null && heroTag!.isNotEmpty)
        ? Hero(
            tag: heroTag!,
            flightShuttleBuilder: heroTag == KugoHeroTags.dailyRecommendBadge
                ? KugoHeroTags.dailyRecommendBadgeFlightShuttle
                : null,
            child: Material(
              type: MaterialType.transparency,
              child: badgeContainer,
            ),
          )
        : badgeContainer;

    return Material(
      color: kugo.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kugo.divider),
          ),
          child: Row(
            children: [
              badgeWidget,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StylePanel extends StatelessWidget {
  const _StylePanel({
    required this.loading,
    required this.error,
    required this.groups,
    required this.activeGroupName,
    required this.selectedTagIds,
    required this.summary,
    required this.tracks,
    required this.isPlaying,
    required this.onGroupTap,
    required this.onTagTap,
    required this.onRetry,
    required this.onTrackTap,
  });

  final bool loading;
  final String error;
  final List<StyleTagGroup> groups;
  final String activeGroupName;
  final Set<String> selectedTagIds;
  final String summary;
  final List<Track> tracks;
  final bool Function(Track track) isPlaying;
  final ValueChanged<String> onGroupTap;
  final ValueChanged<StyleTag> onTagTap;
  final VoidCallback onRetry;
  final ValueChanged<int> onTrackTap;

  StyleTagGroup? get _active {
    for (final g in groups) {
      if (g.name == activeGroupName) return g;
    }
    return groups.isEmpty ? null : groups.first;
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);

    if (loading && tracks.isEmpty && groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(KugoSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error.isNotEmpty && tracks.isEmpty && groups.isEmpty) {
      return _SectionStatus(message: error, onRetry: onRetry);
    }

    final active = _active;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kugo.surface,
              borderRadius: BorderRadius.circular(KugoRadius.card),
              border: Border.all(color: kugo.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: kugo.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary,
                        style: kugo.caption.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final g = groups[index];
                        final selected = active?.name == g.name;
                        return ChoiceChip(
                          label: Text(g.name),
                          selected: selected,
                          onSelected: (_) => onGroupTap(g.name),
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ),
                ],
                if (active != null && active.child.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in active.child)
                        FilterChip(
                          label: Text(tag.name),
                          selected: selectedTagIds.contains(tag.id),
                          onSelected: (_) => onTagTap(tag),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: KugoSpacing.md),
          if (loading && tracks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(KugoSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            )
          else if (tracks.isEmpty)
            _SectionStatus(
              message: error.isEmpty ? '暂无风格推荐' : error,
              onRetry: onRetry,
            )
          else
            for (var i = 0; i < tracks.length; i++)
              Builder(
                builder: (context) {
                  final track = tracks[i];
                  return TrackTile(
                    track: track,
                    isPlaying: isPlaying(track),
                    onArtistTap: artistTapFor(context, track),
                    onTap: () => onTrackTap(i),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _SectionStatus extends StatelessWidget {
  const _SectionStatus({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KugoSpacing.lg,
        vertical: KugoSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: kugo.caption),
          if (onRetry != null) ...[
            const SizedBox(height: KugoSpacing.sm),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}


