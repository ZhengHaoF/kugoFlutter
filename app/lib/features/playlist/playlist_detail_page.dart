import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/profile/user_collections_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/responsive.dart';
import '../../features/rank/rank_list_page.dart'
    show rankCoverHeroTag, RankDetailHeaderSurface, rankHeroFlightShuttle;

class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.id,
    this.initialBrief,
    this.isRank,
    this.userRepository,
  });

  final String id;
  final PlaylistBrief? initialBrief;
  final bool? isRank;
  final UserRepository? userRepository;

  @override
  ConsumerState<PlaylistDetailPage> createState() =>
      _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  PlaylistBrief? _brief;
  List<Track> _tracks = const [];
  bool _loading = true;
  String _error = '';

  UserRepository get _userRepo => widget.userRepository ?? userRepository;

  @override
  void initState() {
    super.initState();
    _brief = widget.initialBrief;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final isRank = widget.isRank ?? widget.initialBrief?.isRank ?? false;

    if (isRank) {
      final rank = await playlistRepository.fetchRankDetail(widget.id);
      if (!mounted) return;
      if (rank != null && rank.tracks.isNotEmpty) {
        _applyLoaded(rank.brief, rank.tracks, isRank: true);
        return;
      }
    } else {
      final auth = ref.read(authControllerProvider);
      final collections = ref.read(userCollectionsProvider);
      final brief = widget.initialBrief ?? _brief;

      // Check if identified as a user cloud playlist
      PlaylistBrief? matchingCreated;
      for (final p in collections.createdPlaylists) {
        if (p.id == widget.id) {
          matchingCreated = p;
          break;
        }
      }
      PlaylistBrief? matchingCollected;
      for (final p in collections.collectedPlaylists) {
        if (p.id == widget.id) {
          matchingCollected = p;
          break;
        }
      }
      final matchedPlaylist = brief ?? matchingCreated ?? matchingCollected;

      final isUserPlaylist = matchedPlaylist != null &&
          (matchedPlaylist.isDefault ||
              matchedPlaylist.userId.isNotEmpty ||
              matchingCreated != null ||
              matchingCollected != null);

      if (isUserPlaylist && auth.isLogged && auth.user != null) {
        final isCollected = matchingCollected != null ||
            (matchedPlaylist.userId.isNotEmpty &&
                matchedPlaylist.userId != auth.user!.userId);

        final userTracksResult = await _userRepo.fetchUserPlaylistTracks(
          listId: widget.id,
          userId: auth.user!.userId,
          token: auth.user!.token,
          type: isCollected ? 1 : 0,
          page: 1,
          pageSize: 300,
        );
        if (!mounted) return;
        if (userTracksResult.tracks.isNotEmpty) {
          _applyLoaded(matchedPlaylist, userTracksResult.tracks, isRank: false);
          return;
        } else if (userTracksResult.error.isEmpty) {
          _applyLoaded(matchedPlaylist, const [], isRank: false);
          return;
        }
      }

      // Try public special playlist
      final remote = await playlistRepository.fetchPlaylist(widget.id);
      if (!mounted) return;
      if (remote != null && remote.tracks.isNotEmpty) {
        _applyLoaded(remote.brief, remote.tracks, isRank: false);
        return;
      }

      // Fallback: If public failed and user is logged in, attempt user playlist tracks
      if (auth.isLogged && auth.user != null && !isUserPlaylist) {
        final userTracksResult = await _userRepo.fetchUserPlaylistTracks(
          listId: widget.id,
          userId: auth.user!.userId,
          token: auth.user!.token,
          type: 0,
          page: 1,
          pageSize: 300,
        );
        if (!mounted) return;
        if (userTracksResult.tracks.isNotEmpty) {
          final fallbackBrief = matchedPlaylist ??
              PlaylistBrief(
                id: widget.id,
                name: '歌单',
                coverUrl: '',
                trackCount: userTracksResult.tracks.length,
              );
          _applyLoaded(fallbackBrief, userTracksResult.tracks, isRank: false);
          return;
        }
      }
    }

    // Fallback if preferred type failed.
    final fallback = isRank
        ? await playlistRepository.fetchPlaylist(widget.id)
        : await playlistRepository.fetchRankDetail(widget.id);
    if (!mounted) return;
    if (fallback != null && fallback.tracks.isNotEmpty) {
      _applyLoaded(fallback.brief, fallback.tracks, isRank: !isRank);
      return;
    }

    setState(() {
      _loading = false;
      _error = '${isRank ? "榜单" : "歌单"}加载失败：接口不可用或该 ID 无公开数据';
    });
  }

  void _applyLoaded(PlaylistBrief loadedBrief, List<Track> loadedTracks, {required bool isRank}) {
    final existingCover = _brief?.coverUrl ?? '';
    final remoteCover = loadedBrief.coverUrl;
    var cover = (remoteCover.isNotEmpty &&
            !remoteCover.contains('mock://') &&
            !remoteCover.endsWith('/${widget.id}'))
        ? remoteCover
        : (existingCover.isNotEmpty && !existingCover.contains('mock://')
            ? existingCover
            : '');

    if (cover.isEmpty && loadedTracks.isNotEmpty) {
      for (final t in loadedTracks) {
        if (t.coverUrl.isNotEmpty &&
            !t.coverUrl.contains('mock://') &&
            (t.coverUrl.startsWith('http://') ||
                t.coverUrl.startsWith('https://'))) {
          cover = t.coverUrl;
          break;
        }
      }
    }

    final genericName = isRank ? '榜单' : '歌单';
    final name = (loadedBrief.name.isNotEmpty && loadedBrief.name != genericName)
        ? loadedBrief.name
        : (_brief?.name ?? loadedBrief.name);

    setState(() {
      _brief = PlaylistBrief(
        id: loadedBrief.id.isNotEmpty ? loadedBrief.id : widget.id,
        name: name,
        coverUrl: cover,
        description: loadedBrief.description.isNotEmpty
            ? loadedBrief.description
            : (_brief?.description ?? ''),
        creator: loadedBrief.creator.isNotEmpty
            ? loadedBrief.creator
            : (_brief?.creator ?? ''),
        trackCount: loadedTracks.isNotEmpty ? loadedTracks.length : loadedBrief.trackCount,
        playCountLabel: loadedBrief.playCountLabel.isNotEmpty
            ? loadedBrief.playCountLabel
            : (_brief?.playCountLabel ?? ''),
        isRank: isRank,
        source: loadedBrief.source,
        userId: loadedBrief.userId,
        isDefault: loadedBrief.isDefault,
      );
      _tracks = loadedTracks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerControllerProvider);
    final brief = _brief;
    final tracks = _tracks;

    return Scaffold(
      body: DesktopContentConstraint(
        child: CustomScrollView(
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
              background: Hero(
                tag: (widget.isRank ?? widget.initialBrief?.isRank ?? false)
                    ? rankCoverHeroTag(widget.id)
                    : KugoHeroTags.playlistCover(widget.id),
                flightShuttleBuilder: rankHeroFlightShuttle,
                child: RankDetailHeaderSurface(
                  brief: brief,
                  tracksCount: tracks.isNotEmpty
                      ? tracks.length
                      : (brief?.trackCount ?? widget.initialBrief?.trackCount ?? 0),
                  fallbackId: widget.id,
                ),
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
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            ref
                                .read(playerControllerProvider.notifier)
                                .playQueue(tracks, startIndex: 0);
                            context.push('/player');
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('播放全部'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _load,
                    child: const Text('重新加载'),
                  ),
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
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AsyncBody(
                loading: false,
                hasError: _error.isNotEmpty,
                isEmpty: true,
                errorMessage: _error,
                emptyMessage: '暂无歌曲',
                onRetry: _load,
                child: const SizedBox.shrink(),
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  index: index + 1,
                  isPlaying:
                      player.current?.id == track.id && player.isPlaying,
                  onArtistTap: artistTapFor(context, track),
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue(tracks, startIndex: index);
                    context.push('/player');
                  },
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      ),
    );
  }
}
