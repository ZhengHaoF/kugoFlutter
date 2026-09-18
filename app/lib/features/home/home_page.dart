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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<PlaylistBrief> _hero = const [];
  List<PlaylistBrief> _playlists = const [];
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

    List<PlaylistBrief> playlists = const [];
    List<Track> songs = const [];
    var filtered = false;
    var denied = false;

    // Square often returns "Access Deny"; fall back to public rank boards.
    try {
      playlists = await playlistRepository.fetchHomeCards(take: 6);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('URL过滤') || msg.contains('拦截')) filtered = true;
      if (msg.contains('Access Deny')) denied = true;
    }
    try {
      songs = await searchRepository.searchSongs('热门', pageSize: 8);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('URL过滤') || msg.contains('拦截')) filtered = true;
      if (msg.contains('Access Deny')) denied = true;
    }

    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _hero = playlists.take(3).toList();
      _songs = songs;
      _loading = false;
      if (playlists.isEmpty && songs.isEmpty) {
        if (filtered) {
          _error = '当前网络被网关拦截（URL过滤），无法访问酷狗。\n请换手机热点 / 关闭路由器「上网行为管理」后重试。';
        } else if (denied) {
          _error = '酷狗接口拒绝访问（Access Deny）。\n稍后重试，或检查是否触发风控。';
        } else {
          _error = '首页数据加载失败，请检查网络后重试';
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 6 => '凌晨好',
      < 12 => '早上好',
      < 18 => '下午好',
      _ => '晚上好',
    };

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
              KugoSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting, style: KugoTypography.greeting),
                const SizedBox(height: 4),
                Text(
                  '为你精选今日旋律',
                  style: KugoTypography.caption.copyWith(fontSize: 13),
                ),
                const SizedBox(height: KugoSpacing.lg),
                _SearchPill(onTap: () => context.push('/search')),
                const SizedBox(height: KugoSpacing.md),
                _DailyEntryTile(onTap: () => context.push('/daily')),
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
        else if (_hero.isNotEmpty)
          SliverToBoxAdapter(child: _HeroCarousel(items: _hero)),
        if (!_loading && _songs.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(
              title: '今日热歌',
              showAccent: true,
            ),
          ),
          SliverList.builder(
            itemCount: _songs.length,
            itemBuilder: (context, index) {
              final track = _songs[index];
              return TrackTile(
                track: track,
                isPlaying: player.current?.id == track.id && player.isPlaying,
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
        if (!_loading && _playlists.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: SectionHeader(title: '推荐歌单', showAccent: true),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: KugoSpacing.lg,
                crossAxisSpacing: KugoSpacing.lg,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlist = _playlists[index];
                return PlaylistCard(
                  playlist: playlist,
                  width: double.infinity,
                  onTap: () => context.push('/playlist/${playlist.id}'),
                );
              }, childCount: _playlists.length),
            ),
          ),
        ],
        if (!_loading && _songs.isEmpty && _playlists.isEmpty)
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
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

class _DailyEntryTile extends StatelessWidget {
  const _DailyEntryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = '${now.month}月${now.day}日 · 每日推荐';

    return Material(
      color: KugoColors.surface,
      borderRadius: BorderRadius.circular(KugoRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KugoRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: KugoColors.accentGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.today_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KugoTypography.body.copyWith(fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      '按日轮换歌单 · 点开即听',
                      style: KugoTypography.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: KugoColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KugoColors.surface,
      borderRadius: BorderRadius.circular(KugoRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KugoRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: KugoColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                '搜索歌曲、歌手、专辑',
                style: KugoTypography.caption.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({required this.items});

  final List<PlaylistBrief> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.86),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KugoRadius.card),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverBox(seed: item.coverUrl, size: 0, radius: 0),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                        stops: const [0.4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: KugoTypography.title),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.description,
                            style: KugoTypography.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
