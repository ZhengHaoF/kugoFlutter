import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/features.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/registry.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../features/rank/rank_list_page.dart'
    show rankCoverHeroTag, RankCardSurface, rankHeroFlightShuttle;
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/responsive.dart';
import 'quick_entries.dart';
import '../../shared/widgets/smooth_scroll.dart';

/// Unified browse tab: former Home + Explore merged into one page.
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  /// 当前音源；`null` = 无可用源（均未注册 / 未启用 / 都不具备本页能力）。
  MusicPlatform? _source;

  List<PlaylistBrief> _rankings = const [];
  List<Track> _songs = const [];
  PlaylistBrief? _hotBoard;
  List<PlaylistBrief> _recommendPlaylists = const [];
  List<Track> _newSongs = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  T? _capability<T>(MusicPlatform? platform) => platform == null
      ? null
      : musicSourceRegistry?.capability<T>(platform);

  /// 已启用、且**该源「发现」功能未关**、并具备本页任一能力的音源。
  ///
  /// 本页四块内容分别依赖 [RankSource] / [PlaylistCatalogSource] /
  /// [NewSongFeedSource]，故用「任一能力」判定该源可用于发现页；
  /// 单块是否可用再由各块自己按能力判（缺能力就不渲染那一排）。
  List<MusicPlatform> _availableSources() {
    final registry = musicSourceRegistry;
    if (registry == null) return const [];
    final settings = ref.read(settingsControllerProvider);
    return registry.platforms
        .where(
          (p) =>
              settings.isFeatureEnabled(p, SourceFeature.discovery) &&
              (registry.capability<RankSource>(p) != null ||
                  registry.capability<PlaylistCatalogSource>(p) != null ||
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

  Future<void> _load() async {
    final source = _resolveSource(_availableSources());
    setState(() {
      _source = source;
      _loading = true;
      _error = '';
    });
    if (source == null) {
      // 无任何可用源：内容区出停用空态，页面其余部分（问候语/搜索/快捷入口）保留。
      if (mounted) {
        setState(() {
          _rankings = const [];
          _songs = const [];
          _hotBoard = null;
          _recommendPlaylists = const [];
          _newSongs = const [];
          _loading = false;
        });
      }
      return;
    }

    var filtered = false;
    var denied = false;

    void noteError(Object e) {
      final msg = e.toString();
      if (msg.contains('URL过滤') || msg.contains('拦截')) filtered = true;
      if (msg.contains('Access Deny')) denied = true;
    }

    final rankSource = _capability<RankSource>(source);
    final catalog = _capability<PlaylistCatalogSource>(source);
    final feed = _capability<NewSongFeedSource>(source);

    List<PlaylistBrief> ranks = const [];
    List<Track> songs = const [];
    List<PlaylistBrief> playlists = const [];
    List<Track> freshSongs = const [];
    PlaylistBrief? hotBoard;

    // 三块内容并行取数；某源缺某项能力时该块留空（不渲染对应横排）。
    await Future.wait([
      () async {
        if (rankSource == null) return;
        try {
          ranks = await rankSource.rankBoards();
        } catch (e) {
          noteError(e);
          return;
        }
        // 「今日热歌」= 热歌榜 Top，公开趋势；与 /daily「每日推荐」的
        // `/everyday_song_recommend` 不是同一数据源。
        hotBoard = _pickHotBoard(ranks);
        final board = hotBoard;
        if (board == null) return;
        try {
          final tracks = await rankSource.rankTracks(board.id);
          songs = tracks.take(10).toList();
        } catch (e) {
          noteError(e);
        }
      }(),
      () async {
        if (catalog == null) return;
        try {
          // 空串 = 各源自己的默认分类（酷狗「推荐」/ 网易「全部」）。
          playlists = await catalog.categoryPlaylists(cat: '', pageSize: 12);
        } catch (e) {
          noteError(e);
        }
      }(),
      () async {
        if (feed == null) return;
        try {
          freshSongs = await feed.newSongs(pageSize: 6);
        } catch (e) {
          noteError(e);
        }
      }(),
    ]);

    // 切源（设置改动）后到达的旧响应直接丢弃。
    if (!mounted || source != _source) return;

    setState(() {
      _rankings = ranks.take(12).toList();
      _songs = songs;
      _hotBoard = hotBoard;
      _recommendPlaylists = playlists;
      _newSongs = freshSongs;
      _loading = false;
      if (_rankings.isEmpty &&
          _songs.isEmpty &&
          _recommendPlaylists.isEmpty &&
          _newSongs.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问该音源。\n请换手机热点 / 关闭路由器「上网行为管理」后重试。'
            : denied
                ? '接口拒绝访问（Access Deny）。\n稍后重试，或检查是否触发风控。'
                : '数据加载失败，请检查网络后重试';
      }
    });
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
    final settings = ref.watch(settingsControllerProvider);
    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 6 => '凌晨好',
      < 12 => '早上好',
      < 18 => '下午好',
      _ => '晚上好',
    };

    // 设置里改动整源开关或「发现」功能开关后回到本页：可用源变了就重取（含从「无可用源」恢复）。
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.enabledSources == next.enabledSources &&
          prev?.disabledFeatures == next.disabledFeatures) {
        return;
      }
      if (_resolveSource(_availableSources()) != _source) _load();
    });

    final available = _availableSources();
    final isEmpty = !_loading &&
        _rankings.isEmpty &&
        _songs.isEmpty &&
        _recommendPlaylists.isEmpty &&
        _newSongs.isEmpty;

    // 浏览型页面：内容铺满侧栏之外的全部宽度（与「我的」「历史」一致），
    // 不再做居中限宽——最大化窗口时两侧不会再留大片空白。
    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              KugoSpacing.xl,
              KugoSpacing.lg,
              // 底部交给 SectionHeader 顶距，避免与「为你推荐」叠出过松的空隙。
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: kugo.greeting),
                const SizedBox(height: 4),
                Text(
                  '发现好音乐 · 为你精选今日旋律',
                  style: kugo.caption.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 6),
                // 本页定位是浏览落地页，不放可切换 chips；用一行只读小字
                // 说明当前内容来自哪个音源。
                SourceLabel(
                  platform: _source ?? settings.effectiveDefaultSource,
                ),
                const SizedBox(height: KugoSpacing.lg),
                const _SearchPill(),
                const SizedBox(height: KugoSpacing.md),
                const QuickEntries(),
              ],
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(KugoSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else ...[
          if (_rankings.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '排行榜',
                showAccent: true,
                actionLabel: '全部',
                onAction: () => context.push('/ranks'),
              ),
            ),
            SliverToBoxAdapter(
              child: _RankStrip(
                ranks: _rankings,
                onRankTap: (rank) =>
                    context.push('/rank/${rank.id}', extra: rank),
              ),
            ),
          ],
          if (_recommendPlaylists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '推荐歌单',
                showAccent: true,
                actionLabel: '更多',
                onAction: () => context.push('/discovery'),
              ),
            ),
            SliverToBoxAdapter(
              child: _PlaylistStrip(
                playlists: _recommendPlaylists,
                // 多源时给封面角标标明推荐歌单来自哪个源（单源靠页头小字）。
                platform: available.length > 1 ? _source : null,
                onTap: (playlist) => context.push(
                  _playlistRoute(playlist),
                  extra: playlist,
                ),
              ),
            ),
          ],
          if (_songs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '今日热歌',
                showAccent: true,
                actionLabel: '更多',
                onAction: () {
                  final board = _hotBoard;
                  if (board != null) {
                    context.push('/rank/${board.id}', extra: board);
                  } else {
                    context.push('/ranks');
                  }
                },
              ),
            ),
            SliverList.builder(
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final track = _songs[index];
                return TrackTile(
                  track: track,
                  isPlaying: player.current?.id == track.id && player.isPlaying,
                  onArtistTap: artistTapFor(context, track),
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(_songs, startIndex: index);
                    context.push('/player');
                  },
                );
              },
            ),
          ],
          if (_newSongs.isNotEmpty) ...[
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
            SliverList.builder(
              itemCount: _newSongs.length,
              itemBuilder: (context, index) {
                final track = _newSongs[index];
                return TrackTile(
                  track: track,
                  isPlaying: player.current?.id == track.id && player.isPlaying,
                  onArtistTap: artistTapFor(context, track),
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(_newSongs, startIndex: index);
                    context.push('/player');
                  },
                );
              },
            ),
          ],
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: available.isEmpty
                  ? SourceDisabledView(
                      platform: settings.effectiveDefaultSource,
                      feature: settings.featureSwitchCause(
                        SourceFeature.discovery,
                      ),
                    )
                  : AsyncBody(
                      loading: false,
                      hasError: true,
                      isEmpty: false,
                      errorMessage: _error,
                      onRetry: _load,
                      child: const SizedBox.shrink(),
                    ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

/// Prefer 热歌榜 → TOP/500 → first board for the 「今日热歌」section.
PlaylistBrief? _pickHotBoard(List<PlaylistBrief> ranks) {
  PlaylistBrief? hot;
  PlaylistBrief? top;
  for (final r in ranks) {
    final n = r.name;
    if (hot == null && n.contains('热歌')) hot = r;
    if (top == null &&
        (n.contains('TOP') || n.contains('Top') || n.contains('500'))) {
      top = r;
    }
  }
  return hot ?? top ?? (ranks.isEmpty ? null : ranks.first);
}

/// 发现页「排行榜」横排。
///
/// 桌面：按可用宽度铺满——先取「还能放下几张」，再把这几张等分拉伸到整行，
/// 所以卡片右缘总是贴住内容右缘（不会右侧挂一条空白）。一行放不下的榜单
/// 横向滚动看。手机：保持设计稿的 168 宽卡片 + 露边（提示可滑）。
class _RankStrip extends StatelessWidget {
  const _RankStrip({required this.ranks, required this.onRankTap});

  final List<PlaylistBrief> ranks;
  final ValueChanged<PlaylistBrief> onRankTap;

  /// 设计稿基准尺寸（旧版写死的 168×230，卡面比例由它决定）。
  static const double _baseCardWidth = 168;
  static const double _baseCardHeight = 230;
  static const double _aspectRatio = _baseCardWidth / _baseCardHeight;

  /// 卡片宽度上限：再宽就显得笨了（铺不满时退化为居中）。
  static const double _maxCardWidth = 260;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopView(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = ranks.length;
        final available = constraints.maxWidth - KugoSpacing.lg * 2;

        var cardWidth = _baseCardWidth;
        var side = KugoSpacing.lg;
        if (desktop && count > 0) {
          final fit = fitStripRow(
            available: available,
            count: count,
            minWidth: _baseCardWidth,
            maxWidth: _maxCardWidth,
            gap: _gap,
          );
          cardWidth = fit.width;
          // 卡片被 [_maxCardWidth] 封顶时一行铺不满，居中免得一侧挂空白。
          final rowWidth =
              fit.visible * cardWidth + _gap * (fit.visible - 1);
          side += (available - rowWidth).clamp(0.0, double.infinity) / 2;
        }

        return SizedBox(
          // 卡片等比缩放，高度跟着走，封面裁切与文字比例保持不变。
          height: cardWidth / _aspectRatio,
          child: ListView.separated(
            key: const ValueKey('explore_rank_strip'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: side),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final rank = ranks[index];
              return SizedBox(
                width: cardWidth,
                child: _RankingCard(
                  rank: rank,
                  onTap: () => onRankTap(rank),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.rank, required this.onTap});

  final PlaylistBrief rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 宽度由 [_RankStrip] 按可用空间给出，这里只负责视觉。
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KugoRadius.card),
        child: Hero(
          tag: rankCoverHeroTag(rank.id),
          flightShuttleBuilder: rankHeroFlightShuttle,
          child: RankCardSurface(brief: rank, showTitle: true),
        ),
      ),
    );
  }
}

/// 发现页「推荐歌单」横排。
///
/// 与 [_RankStrip] 同一套铺满逻辑（桌面等分拉伸到整行、一行放不下横向滚动），
/// 只是卡面换成 [PlaylistCard]（1:1 封面 + 两行标题 + 一行描述）。
class _PlaylistStrip extends StatelessWidget {
  const _PlaylistStrip({
    required this.playlists,
    required this.onTap,
    this.platform,
  });

  final List<PlaylistBrief> playlists;
  final ValueChanged<PlaylistBrief> onTap;

  /// 多源时透传给卡片做封面来源角标；单源传 null。
  final MusicPlatform? platform;

  static const double _baseCardWidth = 148;
  static const double _maxCardWidth = 220;
  static const double _gap = 12;

  /// 封面以下的固定文字高度：8 间距 + 两行标题 + 一行描述。
  static const double _belowCover = 66;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopView(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = playlists.length;
        final available = constraints.maxWidth - KugoSpacing.lg * 2;

        var cardWidth = _baseCardWidth;
        var side = KugoSpacing.lg;
        if (desktop && count > 0) {
          final fit = fitStripRow(
            available: available,
            count: count,
            minWidth: _baseCardWidth,
            maxWidth: _maxCardWidth,
            gap: _gap,
          );
          cardWidth = fit.width;
          if (fit.visible > 1) {
            final rowWidth =
                fit.visible * cardWidth + _gap * (fit.visible - 1);
            side += (available - rowWidth).clamp(0.0, double.infinity) / 2;
          }
        }

        return SizedBox(
          height: cardWidth + _belowCover,
          child: ListView.separated(
            key: const ValueKey('explore_playlist_strip'),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: side),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return PlaylistCard(
                playlist: playlist,
                width: cardWidth,
                platform: platform,
                onTap: () => onTap(playlist),
              );
            },
          ),
        );
      },
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill();

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Hero(
      tag: KugoHeroTags.searchBar,
      flightShuttleBuilder: KugoHeroTags.searchBarFlightShuttle,
      child: Material(
        color: kugo.surface,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        child: InkWell(
          onTap: () => context.push('/search'),
          borderRadius: BorderRadius.circular(KugoRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: kugo.textSecondary),
                const SizedBox(width: 10),
                Text(
                  '搜索歌曲、歌手、专辑',
                  style: kugo.caption.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
