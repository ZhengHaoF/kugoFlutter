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
import '../../shared/widgets/cover_box.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  List<String> _hot = const [];
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
    List<String> hot = const [];
    List<PlaylistBrief> ranks = const [];
    List<Track> songs = const [];
    var filtered = false;
    try {
      hot = await searchRepository.hotKeywords();
    } catch (e) {
      if (e.toString().contains('拦截')) filtered = true;
    }
    try {
      ranks = await playlistRepository.fetchRankList();
    } catch (e) {
      if (e.toString().contains('拦截')) filtered = true;
    }
    try {
      songs = await searchRepository.searchSongs('新歌', pageSize: 10);
    } catch (e) {
      if (e.toString().contains('拦截')) filtered = true;
    }
    if (!mounted) return;
    setState(() {
      _hot = hot;
      _rankings = ranks.take(6).toList();
      _songs = songs;
      _loading = false;
      if (hot.isEmpty && ranks.isEmpty && songs.isEmpty) {
        _error = filtered
            ? '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点 / 关闭路由器「上网行为管理」后重试。'
            : '发现页数据加载失败，请检查网络';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              KugoSpacing.xl,
              KugoSpacing.lg,
              KugoSpacing.md,
            ),
            child: Text('发现', style: KugoTypography.greeting),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
            child: Material(
              color: KugoColors.surface,
              borderRadius: BorderRadius.circular(KugoRadius.chip),
              child: InkWell(
                onTap: () => context.push('/search'),
                borderRadius: BorderRadius.circular(KugoRadius.chip),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: KugoColors.textSecondary,
                      ),
                      SizedBox(width: 10),
                      Text(
                        '搜索歌曲、歌手、专辑',
                        style: TextStyle(
                          color: KugoColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              KugoSpacing.md,
              KugoSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _EntryCard(
                    icon: Icons.radio_rounded,
                    title: '私人 FM',
                    subtitle: '黑胶电台 · 动态歌池',
                    onTap: () => context.push('/fm'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EntryCard(
                    icon: Icons.search_rounded,
                    title: '搜索',
                    subtitle: '歌曲 / 歌手 / 歌单',
                    onTap: () => context.push('/search'),
                  ),
                ),
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
          if (_hot.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KugoSpacing.lg,
                    vertical: KugoSpacing.sm,
                  ),
                  itemCount: _hot.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ActionChip(
                      label: Text(_hot[index]),
                      backgroundColor: KugoColors.surface,
                      labelStyle: KugoTypography.caption.copyWith(fontSize: 13),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KugoRadius.chip),
                      ),
                      onPressed: () => context.push('/search'),
                    );
                  },
                ),
              ),
            ),
          if (_rankings.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '排行榜',
                showAccent: true,
                actionLabel: _rankings.isEmpty ? null : '全部',
                onAction: _rankings.isEmpty ? null : () => context.push('/ranks'),
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
                      onTap: () => context.push('/playlist/${rank.id}'),
                    );
                  },
                ),
              ),
            ),
          ],
          if (_songs.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: SectionHeader(title: '新歌速递', showAccent: true),
            ),
            SliverList.builder(
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final track = _songs[index];
                return TrackTile(
                  track: track,
                  isPlaying:
                      player.current?.id == track.id && player.isPlaying,
                  onArtistTap: () => context.push(
                    '/artist/${Uri.encodeComponent(track.artist)}',
                  ),
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
          if (_hot.isEmpty && _rankings.isEmpty && _songs.isEmpty)
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverBox(seed: rank.coverUrl, size: 0, radius: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rank.name,
                      style: KugoTypography.section.copyWith(fontSize: 17),
                    ),
                    if (rank.playCountLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        rank.playCountLabel,
                        style: KugoTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KugoColors.surface,
      borderRadius: BorderRadius.circular(KugoRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KugoRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(KugoSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: KugoColors.primary),
              const SizedBox(height: 10),
              Text(title, style: KugoTypography.body),
              const SizedBox(height: 2),
              Text(subtitle, style: KugoTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
