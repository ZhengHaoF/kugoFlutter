import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/song_detail_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/cover_box.dart';

/// Route: /song?id=&name=&artist=&album=&cover=&hash=&mixSongId=&duration=
class SongDetailPage extends ConsumerStatefulWidget {
  const SongDetailPage({
    super.key,
    required this.id,
    this.name = '',
    this.artist = '',
    this.album = '',
    this.coverUrl = '',
    this.hash = '',
    this.mixSongId = '',
    this.durationMs = 0,
  });

  final String id;
  final String name;
  final String artist;
  final String album;
  final String coverUrl;
  final String hash;
  final String mixSongId;
  final int durationMs;

  @override
  ConsumerState<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends ConsumerState<SongDetailPage> {
  List<SongComment> _comments = const [];
  bool _loading = true;
  String _error = '';
  int _page = 1;
  bool _hasMore = true;

  Track get _track => Track(
        id: widget.id,
        name: widget.name.isEmpty ? '歌曲' : widget.name,
        artist: widget.artist,
        album: widget.album,
        coverUrl: widget.coverUrl,
        durationMs: widget.durationMs,
        hash: widget.hash,
        mixSongId: widget.mixSongId,
      );

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = '';
        _page = 1;
        _hasMore = true;
        _comments = const [];
      });
    }
    final mixId = widget.mixSongId.isNotEmpty ? widget.mixSongId : widget.id;
    final list = await songDetailRepository.fetchComments(
      mixSongId: mixId,
      page: _page,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (list.isEmpty && _comments.isEmpty) {
        _error = songDetailRepository.lastError.isEmpty
            ? '暂无评论'
            : songDetailRepository.lastError;
        _hasMore = false;
      } else {
        _comments = reset ? list : [..._comments, ...list];
        _hasMore = list.length >= 20;
        _error = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('歌曲详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          KugoSpacing.md,
          KugoSpacing.lg,
          40,
        ),
        children: [
          Row(
            children: [
              CoverBox(seed: track.coverUrl, size: 88, radius: KugoRadius.card),
              const SizedBox(width: KugoSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, style: KugoTypography.title),
                    const SizedBox(height: 6),
                    Text(
                      track.artist.isEmpty ? '未知歌手' : track.artist,
                      style: KugoTypography.caption,
                    ),
                    if (track.album.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KugoTypography.caption.copyWith(
                          color: KugoColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: KugoSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .playQueue([track], startIndex: 0);
                    context.push('/player');
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('播放'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/artist/${Uri.encodeComponent(track.artist)}'),
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: const Text('歌手'),
                ),
              ),
            ],
          ),
          if (player.current?.id == track.id)
            Padding(
              padding: const EdgeInsets.only(top: KugoSpacing.sm),
              child: Text(
                player.isPlaying ? '正在播放' : '已加入播放',
                style: KugoTypography.caption.copyWith(
                  color: KugoColors.primary,
                ),
              ),
            ),
          const SizedBox(height: KugoSpacing.xl),
          Text('评论', style: KugoTypography.section),
          const SizedBox(height: KugoSpacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(KugoSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(KugoSpacing.lg),
              child: Text(
                _error.isEmpty ? '暂无评论' : _error,
                style: KugoTypography.caption,
              ),
            )
          else ...[
            for (final c in _comments) _CommentTile(comment: c),
            if (_hasMore)
              TextButton(
                onPressed: () {
                  _page += 1;
                  _load();
                },
                child: const Text('加载更多'),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final SongComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KugoSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverBox(
            seed: comment.avatarUrl.isEmpty
                ? 'avatar-${comment.user}'
                : comment.avatarUrl,
            size: 36,
            radius: 999,
            child: const Icon(Icons.person_rounded, size: 18, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.user,
                        style: KugoTypography.caption.copyWith(
                          color: KugoColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (comment.timeLabel.isNotEmpty)
                      Text(comment.timeLabel, style: KugoTypography.caption),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: KugoTypography.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.thumb_up_off_alt_rounded,
                      size: 14,
                      color: KugoColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likeCount}',
                      style: KugoTypography.caption.copyWith(
                        color: KugoColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
