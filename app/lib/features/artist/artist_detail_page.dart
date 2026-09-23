import 'dart:async';

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
import '../../shared/widgets/smooth_scroll.dart';

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

  final List<Track> _songs = [];
  bool _loadingSongs = true;
  bool _loadingMore = false;
  String _songsError = '';
  int _songPage = 0;
  int _songTotal = 0;
  bool _hasMore = false;
  ArtistSongSort _songSort = ArtistSongSort.hot;
  int _songFetchToken = 0;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _songFetchToken++;
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadDetail(), _loadSongs(reset: true)]);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final remote = await catalogRepository.fetchArtist(widget.id);
    if (!mounted) return;
    if (remote != null) {
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

  Future<void> _loadSongs({bool reset = false}) async {
    final token = ++_songFetchToken;
    if (reset) {
      setState(() {
        _songs.clear();
        _songPage = 0;
        _songTotal = 0;
        _hasMore = false;
        _loadingSongs = true;
        _songsError = '';
        _loadingMore = false;
      });
    }

    final page = reset ? 1 : _songPage + 1;
    final result = await catalogRepository.fetchArtistSongs(
      widget.id,
      page: page,
      pageSize: 50,
      sort: _songSort,
    );
    if (!mounted || token != _songFetchToken) return;

    if (result.songs.isEmpty && page > 1) {
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
      return;
    }

    setState(() {
      if (reset) _songs.clear();
      _songs.addAll(result.songs);
      _songPage = page;
      _songTotal = result.total > 0
          ? result.total
          : (_artist?.songCount ?? _songs.length);
      _hasMore = result.hasMore;
      _loadingSongs = false;
      _loadingMore = false;
      if (reset && _songs.isEmpty) {
        _songsError = '暂无公开歌曲';
      }
    });

    // Background-fill remaining pages (Echo-style) so search/queue see full set.
    if (_hasMore) {
      unawaited(_loadRemaining(token));
    }
  }

  Future<void> _loadRemaining(int token) async {
    while (mounted &&
        token == _songFetchToken &&
        _hasMore &&
        !_loadingMore) {
      setState(() => _loadingMore = true);
      final page = _songPage + 1;
      final result = await catalogRepository.fetchArtistSongs(
        widget.id,
        page: page,
        pageSize: 50,
        sort: _songSort,
      );
      if (!mounted || token != _songFetchToken) return;
      if (result.songs.isEmpty) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
        return;
      }
      setState(() {
        _songs.addAll(result.songs);
        _songPage = page;
        if (result.total > 0) _songTotal = result.total;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    }
  }

  void _switchSort(ArtistSongSort sort) {
    if (sort == _songSort) return;
    setState(() => _songSort = sort);
    unawaited(_loadSongs(reset: true));
  }

  List<Track> get _displayedSongs {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_songs);
    return _songs.where((t) {
      return t.name.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q);
    }).toList();
  }

  void _playAll() {
    final songs = _displayedSongs;
    if (songs.isEmpty) return;
    ref
        .read(playerControllerProvider.notifier)
        .playQueue(songs, startIndex: 0);
    context.push('/player');
  }

  void _playAt(List<Track> songs, int index) {
    ref
        .read(playerControllerProvider.notifier)
        .playQueue(songs, startIndex: index);
    context.push('/player');
  }

  void _locateCurrent() {
    final player = ref.read(playerControllerProvider);
    final current = player.current;
    if (current == null || !_scrollController.hasClients) return;
    final displayed = _displayedSongs;
    var index = displayed.indexWhere((t) => t.id == current.id);
    if (index < 0) {
      index = _songs.indexWhere((t) => t.id == current.id);
    }
    if (index < 0) return;
    // Header (~320) + toolbar (~56) + row offset.
    final target = (index * 72.0) + 280.0;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  void _showIntroDialog(String intro) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final kugo = KugoTheme.of(context);
        return AlertDialog(
          backgroundColor: kugo.surface,
          title: Text('歌手介绍', style: kugo.section),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                intro,
                style: kugo.caption.copyWith(
                  fontSize: 13,
                  height: 1.6,
                  color: kugo.textSecondary,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  String get _statsLine {
    final artist = _artist;
    final songCount =
        (artist?.songCount ?? 0) > 0 ? artist!.songCount : _songs.length;
    final parts = <String>[
      '$songCount 歌曲',
      if ((artist?.albumCount ?? 0) > 0) '${artist!.albumCount} 专辑',
      if ((artist?.mvCount ?? 0) > 0) '${artist!.mvCount} MV',
    ];
    return parts.join(' · ');
  }

  String get _metaLine {
    final artist = _artist;
    final parts = <String>[
      if (artist != null && artist.fansLabel.isNotEmpty)
        '${artist.fansLabel} 粉丝',
      if (artist != null && artist.birthday.isNotEmpty) artist.birthday,
    ];
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final artist = _artist;
    final displayName = artist?.name ?? Uri.decodeComponent(widget.id);
    final displayed = _displayedSongs;
    final hasSongs = _songs.isNotEmpty;
    final isFiltered = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      body: SmoothCustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            backgroundColor: kugo.bg.withValues(alpha: 0.92),
            flexibleSpace: FlexibleSpaceBar(
              background: _ArtistHero(
                artist: artist,
                displayName: displayName,
                metaLine: _metaLine,
                statusLine: _loading
                    ? '在线加载'
                    : (_error.isNotEmpty ? _error : _statsLine),
                canPlay: hasSongs,
                onPlay: _playAll,
                onReload: _loadAll,
              ),
            ),
          ),
          if (artist != null && artist.intro.isNotEmpty)
            SliverToBoxAdapter(
              child: _IntroSection(
                intro: artist.intro,
                onExpand: () => _showIntroDialog(artist.intro),
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
              child: _SongsToolbar(
                sort: _songSort,
                onSort: _switchSort,
                searchController: _searchController,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                onLocate: _locateCurrent,
                countLabel: isFiltered
                    ? '${displayed.length} / ${_songs.length}'
                    : (_songTotal > 0 ? '$_songTotal' : '${_songs.length}'),
              ),
            ),
          ),
          if (_loadingSongs && _songs.isEmpty)
            const SliverFillRemaining(
              // SkeletonList is a ListView (a viewport), so the sliver must
              // treat it as a scrolling body or intrinsic layout asserts.
              child: SkeletonList(),
            )
          else if (_songs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AsyncBody(
                loading: false,
                hasError: true,
                isEmpty: false,
                errorMessage: _songsError.isNotEmpty
                    ? _songsError
                    : '歌曲加载失败：接口不可用或无公开数据',
                onRetry: () => _loadSongs(reset: true),
                child: const SizedBox.shrink(),
              ),
            )
          else if (displayed.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AsyncBody(
                loading: false,
                hasError: false,
                isEmpty: true,
                emptyMessage: '未找到匹配的歌曲',
                onRetry: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const SizedBox.shrink(),
              ),
            )
          else
            SliverList.builder(
              itemCount: displayed.length + (_hasMore || _loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= displayed.length) {
                  return Padding(
                    padding: const EdgeInsets.all(KugoSpacing.lg),
                    child: Center(
                      child: Text(
                        _loadingMore ? '正在加载更多歌曲…' : '上拉或稍候加载更多',
                        style: kugo.caption,
                      ),
                    ),
                  );
                }
                final track = displayed[index];
                return TrackTile(
                  track: track,
                  index: index + 1,
                  showAlbum: true,
                  isPlaying:
                      player.current?.id == track.id && player.isPlaying,
                  onTap: () => _playAt(displayed, index),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({
    required this.artist,
    required this.displayName,
    required this.metaLine,
    required this.statusLine,
    required this.canPlay,
    required this.onPlay,
    required this.onReload,
  });

  final ArtistDetail? artist;
  final String displayName;
  final String metaLine;
  final String statusLine;
  final bool canPlay;
  final VoidCallback onPlay;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final avatarSeed = artist?.avatarUrl ?? displayName;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kugo.primary.withValues(alpha: 0.12),
            kugo.bg,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KugoSpacing.lg,
            56,
            KugoSpacing.lg,
            KugoSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CoverHero(
                tag: KugoHeroTags.artistAvatar(
                  artist?.id ?? displayName,
                ),
                seed: avatarSeed,
                size: 148,
                radius: 20,
                child: artist?.avatarUrl.isNotEmpty != true
                    ? const Icon(
                        Icons.person_rounded,
                        size: 56,
                        color: Colors.white70,
                      )
                    : null,
              ),
              const SizedBox(width: KugoSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kugo.title.copyWith(fontSize: 28),
                          ),
                        ),
                        const SizedBox(width: KugoSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: kugo.primary),
                            borderRadius: BorderRadius.circular(KugoRadius.chip),
                          ),
                          child: Text(
                            'ARTIST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: kugo.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: artist == null
                            ? kugo.textSecondary
                            : kugo.primary,
                      ),
                    ),
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        metaLine,
                        style: kugo.caption.copyWith(
                          color: kugo.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: KugoSpacing.lg),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: canPlay ? onPlay : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放热门'),
                        ),
                        const SizedBox(width: KugoSpacing.sm),
                        TextButton(
                          onPressed: onReload,
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
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

class _IntroSection extends StatelessWidget {
  const _IntroSection({required this.intro, required this.onExpand});

  final String intro;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KugoSpacing.lg,
        KugoSpacing.md,
        KugoSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('歌手介绍', style: kugo.section.copyWith(fontSize: 16)),
          const SizedBox(height: KugoSpacing.sm),
          Text(
            intro,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: kugo.caption.copyWith(height: 1.5),
          ),
          TextButton(
            onPressed: onExpand,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              minimumSize: const Size(0, 28),
            ),
            child: Text(
              '查看详情',
              style: kugo.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kugo.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsToolbar extends StatelessWidget {
  const _SongsToolbar({
    required this.sort,
    required this.onSort,
    required this.searchController,
    required this.onSearchChanged,
    required this.onLocate,
    required this.countLabel,
  });

  final ArtistSongSort sort;
  final ValueChanged<ArtistSongSort> onSort;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onLocate;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Row(
      children: [
        Text('歌曲', style: kugo.section.copyWith(fontSize: 17)),
        const SizedBox(width: KugoSpacing.sm),
        Text(countLabel, style: kugo.caption),
        const Spacer(),
        SegmentedButton<ArtistSongSort>(
          segments: const [
            ButtonSegment(
              value: ArtistSongSort.hot,
              label: Text('热门'),
            ),
            ButtonSegment(
              value: ArtistSongSort.newest,
              label: Text('最新'),
            ),
          ],
          selected: {sort},
          onSelectionChanged: (s) => onSort(s.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: KugoSpacing.sm),
        SizedBox(
          width: 180,
          height: 36,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: kugo.caption.copyWith(color: kugo.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索歌曲…',
              hintStyle: kugo.caption,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: kugo.textTertiary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              filled: true,
              fillColor: kugo.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KugoRadius.tile),
                borderSide: BorderSide(color: kugo.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KugoRadius.tile),
                borderSide: BorderSide(color: kugo.divider),
              ),
            ),
          ),
        ),
        const SizedBox(width: KugoSpacing.xs),
        IconButton(
          onPressed: onLocate,
          tooltip: '定位当前播放',
          icon: const Icon(Icons.my_location_rounded, size: 18),
          color: kugo.textSecondary,
        ),
      ],
    );
  }
}
