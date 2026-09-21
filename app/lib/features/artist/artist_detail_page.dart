import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';

class ArtistDetailPage extends ConsumerStatefulWidget {
  const ArtistDetailPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends ConsumerState<ArtistDetailPage> {
  ArtistDetail? _artist;
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
    final remote = await catalogRepository.fetchArtist(widget.id);
    if (!mounted) return;
    if (remote != null && remote.songs.isNotEmpty) {
      setState(() {
        _artist = remote;
        _loading = false;
      });
      return;
    }
    setState(() {
      _artist = null;
      _loading = false;
      _error = '歌手加载失败：接口不可用或无公开数据';
    });
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final artist = _artist;
    final songs = artist?.songs ?? const <Track>[];
    final displayName = artist?.name ?? Uri.decodeComponent(widget.id);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CoverHero(
                    tag: KugoHeroTags.artistAvatar(widget.id),
                    seed: artist?.avatarUrl ?? widget.id,
                    size: 0,
                    radius: 0,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          kugo.bg.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: KugoSpacing.lg,
                    right: KugoSpacing.lg,
                    bottom: KugoSpacing.lg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, style: kugo.title),
                        const SizedBox(height: 6),
                        Text(
                          artist == null
                              ? '在线加载'
                              : [
                                  if (artist.fansLabel.isNotEmpty)
                                    '粉丝 ${artist.fansLabel}',
                                  '${songs.length} 首',
                                ].join(' · '),
                          style: kugo.caption,
                        ),
                      ],
                    ),
                  ),
                ],
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
                    onPressed: songs.isEmpty
                        ? null
                        : () {
                            ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(songs, startIndex: 0);
                            context.push('/player');
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放热门'),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _load, child: const Text('重新加载')),
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
          else if (songs.isEmpty)
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
            )
          else
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final track = songs[index];
                return TrackTile(
                  track: track,
                  index: index + 1,
                  isPlaying:
                      player.current?.id == track.id && player.isPlaying,
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(songs, startIndex: index);
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
