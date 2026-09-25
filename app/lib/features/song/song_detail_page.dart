import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/song_detail_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/cover_box.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../shared/widgets/smooth_scroll.dart';

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
  String? _resolvedMixId;

  Track get _track => Track(
        id: widget.id,
        name: widget.name.isEmpty ? '歌曲' : widget.name,
        artist: widget.artist,
        album: widget.album,
        coverUrl: widget.coverUrl,
        durationMs: widget.durationMs,
        hash: widget.hash,
        mixSongId: _resolvedMixId ?? widget.mixSongId,
      );

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  /// cmtlist needs album_audio_id as mixsongid (NOT audio_id).
  /// EchoMusic: mixSongId || resourceId, with search-backed detailSong.
  Future<List<String>> _mixSongIdCandidates() async {
    final out = <String>[];
    void add(String? v) {
      if (v == null) return;
      var s = v.trim();
      if (s.isEmpty || s == '0' || s.toLowerCase() == 'null') return;
      // Hash-like values are never valid mixsongid.
      if (s.length >= 32 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return;
      if (!out.contains(s)) out.add(s);
    }

    final name = widget.name.trim();
    final artist = widget.artist.trim();
    final hash = widget.hash.trim().toLowerCase();

    // Prefer live search album_audio_id — old queue stores audio_id.
    Future<void> searchOnce(String keyword) async {
      if (keyword.isEmpty) return;
      try {
        final hits = await searchRepository.searchSongs(keyword, pageSize: 10);
        Track? byHash;
        Track? byNameArtist;
        Track? byName;
        for (final t in hits) {
          if (hash.isNotEmpty &&
              t.hash.isNotEmpty &&
              t.hash.toLowerCase() == hash) {
            byHash = t;
            break;
          }
        }
        for (final t in hits) {
          final nOk = name.isEmpty || t.name == name;
          final aOk = artist.isEmpty ||
              t.artist.contains(artist) ||
              artist.contains(t.artist);
          if (nOk && aOk) {
            byNameArtist = t;
            break;
          }
        }
        for (final t in hits) {
          if (name.isNotEmpty && t.name == name) {
            byName = t;
            break;
          }
        }
        final match = byHash ??
            byNameArtist ??
            byName ??
            (hits.isNotEmpty ? hits.first : null);
        if (match != null) {
          add(match.mixSongId);
          _resolvedMixId ??= match.mixSongId;
        }
        // Also collect other album_audio_ids for the same title (covers/Live).
        for (final t in hits) {
          if (name.isNotEmpty && t.name.startsWith(name)) add(t.mixSongId);
        }
      } catch (_) {}
    }

    await searchOnce([if (name.isNotEmpty) name, if (artist.isNotEmpty) artist].join(' ').trim());
    if (out.isEmpty) await searchOnce(name);
    if (out.isEmpty && hash.isNotEmpty) await searchOnce(hash);

    add(_resolvedMixId);
    add(widget.mixSongId);
    add(widget.id);
    return out;
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

    final candidates = await _mixSongIdCandidates();
    var list = const <SongComment>[];
    var err = '';
    for (final id in candidates) {
      list = await songDetailRepository.fetchComments(
        mixSongId: id,
        page: _page,
      );
      if (list.isNotEmpty) {
        _resolvedMixId = id;
        break;
      }
      err = songDetailRepository.lastError;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (list.isEmpty && _comments.isEmpty) {
        _error = err.isEmpty ? '暂无评论' : err;
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
    final kugo = KugoTheme.of(context);
    final track = _track;
    final player = ref.watch(playerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('歌曲详情')),
      body: SmoothListView(
        padding: const EdgeInsets.fromLTRB(
          KugoSpacing.lg,
          KugoSpacing.md,
          KugoSpacing.lg,
          40,
        ),
        children: [
          Row(
            children: [
              if (track.id.isNotEmpty || track.hash.isNotEmpty)
                CoverHero(
                  tag: track.id.isNotEmpty
                      ? 'player-cover-${track.id}'
                      : KugoHeroTags.songCover(track.hash),
                  seed: track.coverUrl,
                  size: 88,
                  radius: KugoRadius.card,
                )
              else
                CoverBox(seed: track.coverUrl, size: 88, radius: KugoRadius.card),
              const SizedBox(width: KugoSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.name, style: kugo.title),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.artist.isEmpty ? '未知歌手' : track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.caption,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SourceBadge(platform: track.platform),
                      ],
                    ),
                    if (track.album.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kugo.caption.copyWith(
                          color: kugo.textTertiary,
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
                  onPressed: artistTapFor(context, track),
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
                style: kugo.caption.copyWith(
                  color: kugo.primary,
                ),
              ),
            ),
          const SizedBox(height: KugoSpacing.xl),
          Text('评论', style: kugo.section),
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
                style: kugo.caption,
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
    final kugo = KugoTheme.of(context);
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
                        style: kugo.caption.copyWith(
                          color: kugo.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (comment.timeLabel.isNotEmpty)
                      Text(comment.timeLabel, style: kugo.caption),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: kugo.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up_off_alt_rounded,
                      size: 14,
                      color: kugo.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likeCount}',
                      style: kugo.caption.copyWith(
                        color: kugo.textTertiary,
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
