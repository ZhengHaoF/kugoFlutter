import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../features/rank/rank_list_page.dart'
    show rankCoverHeroTag, RankCardSurface, rankHeroFlightShuttle;
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import 'quick_entries.dart';

/// Unified browse tab: former Home + Explore merged into one page.
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  List<PlaylistBrief> _rankings = const [];
  List<Track> _songs = const [];
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
    try {
      songs = await searchRepository.searchSongs('热门', pageSize: 10);
    } catch (e) {
      noteError(e);
    }

    if (!mounted) return;

    final rankList = ranks.take(6).toList();

    setState(() {
      _rankings = rankList;
      _songs = songs;
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

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
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
              child: SizedBox(
                height: 230,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
                  itemCount: _rankings.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final rank = _rankings[index];
                    return _RankingCard(
                      rank: rank,
                      onTap: () => context.push('/rank/${rank.id}', extra: rank),
                    );
                  },
                ),
              ),
            ),
          ],
          if (_songs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(title: '今日热歌', showAccent: true),
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

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.rank, required this.onTap});

  final PlaylistBrief rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KugoRadius.card),
          child: Hero(
            tag: rankCoverHeroTag(rank.id),
            flightShuttleBuilder: rankHeroFlightShuttle,
            child: RankCardSurface(brief: rank, showTitle: true),
          ),
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
