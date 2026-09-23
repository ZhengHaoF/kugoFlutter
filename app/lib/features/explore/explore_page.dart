import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../features/player/player_controller.dart';
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
  List<PlaylistBrief> _rankings = const [];
  List<Track> _songs = const [];
  PlaylistBrief? _hotBoard;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    List<PlaylistBrief> ranks = const [];
    List<Track> songs = const [];
    var filtered = false;
    var denied = false;

    void noteError(Object e) {
      final msg = e.toString();
      if (msg.contains('URL过滤') || msg.contains('拦截')) filtered = true;
      if (msg.contains('Access Deny')) denied = true;
    }

    try {
      ranks = await playlistRepository.fetchRankList();
    } catch (e) {
      noteError(e);
    }
    // 「今日热歌」= 热歌榜 Top，公开趋势；与 /daily「每日推荐」的
    // `/everyday_song_recommend` 不是同一数据源。
    final hotBoard = _pickHotBoard(ranks);
    if (hotBoard != null) {
      try {
        final detail = await playlistRepository.fetchRankDetail(
          hotBoard.id,
          pageSize: 10,
        );
        songs = detail?.tracks.take(10).toList() ?? const [];
      } catch (e) {
        noteError(e);
      }
    }

    if (!mounted) return;

    final rankList = ranks.take(12).toList();

    setState(() {
      _rankings = rankList;
      _songs = songs;
      _hotBoard = hotBoard;
      _loading = false;
      if (rankList.isEmpty && songs.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点 / 关闭路由器「上网行为管理」后重试。'
            : denied
                ? '酷狗接口拒绝访问（Access Deny）。\n稍后重试，或检查是否触发风控。'
                : '数据加载失败，请检查网络后重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 6 => '凌晨好',
      < 12 => '早上好',
      < 18 => '下午好',
      _ => '晚上好',
    };
    final isEmpty = !_loading && _rankings.isEmpty && _songs.isEmpty;

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
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AsyncBody(
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
