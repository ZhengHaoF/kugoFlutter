import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/track.dart';
import '../../core/theme/hero_tags.dart';
import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/recommend_repository.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/common.dart';

/// 为你推荐聚合页（对齐 EchoMusic Home.vue「为您推荐」信息架构）。
///
/// 区块独立加载、诚实空态/错误，不造假数据；每日推荐仍走 `/daily` 专页。
class RecommendHubPage extends ConsumerStatefulWidget {
  const RecommendHubPage({super.key});

  @override
  ConsumerState<RecommendHubPage> createState() => _RecommendHubPageState();
}

class _Sec<T> {
  _Sec({this.data, this.loading = true, this.error = ''});

  T? data;
  bool loading;
  String error;
}

class _RecommendHubPageState extends ConsumerState<RecommendHubPage> {
  _Sec<StyleRecommendResult> _style = _Sec(loading: true);
  _Sec<RecommendPlaylistsSection> _playlists = _Sec(loading: true);
  _Sec<RecommendPlaylistsSection> _editorial = _Sec(loading: true);

  final Set<String> _selectedTagIds = <String>{};
  String _activeGroupName = '';
  String _playlistCategoryId = '0';
  int _styleRequestId = 0;
  int _playlistRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadStyle();
    _loadPlaylists();
    _loadEditorial();
  }

  Future<void> _loadStyle({bool useSelectedTags = false}) async {
    final requestId = ++_styleRequestId;
    setState(() {
      _style = _Sec(loading: true);
    });
    final tagids =
        useSelectedTags ? _selectedTagIds.join(',') : '';
    final result = await recommendRepository.fetchStyleRecommend(tagids: tagids);
    if (!mounted || requestId != _styleRequestId) return;
    setState(() {
      _style = _Sec(
        data: result,
        loading: false,
        error: result.tracks.isEmpty && result.groups.isEmpty
            ? result.error
            : '',
      );
      final groups = result.groups;
      if (groups.isNotEmpty) {
        if (_activeGroupName.isEmpty ||
            !groups.any((g) => g.name == _activeGroupName)) {
          _activeGroupName = groups.first.name;
        }
        if (!useSelectedTags && _selectedTagIds.isEmpty) {
          for (final g in groups) {
            for (final t in g.child) {
              if (t.isDefault) _selectedTagIds.add(t.id);
            }
          }
        }
      }
    });
  }

  Future<void> _loadPlaylists() async {
    final requestId = ++_playlistRequestId;
    final categoryId = _playlistCategoryId;
    setState(() {
      _playlists = _Sec(loading: true);
    });
    final result = await recommendRepository.fetchRecommendPlaylists(
      categoryId: categoryId,
    );
    if (!mounted || requestId != _playlistRequestId) return;
    setState(() {
      _playlists = _Sec(
        data: result,
        loading: false,
        error: result.playlists.isEmpty ? result.error : '',
      );
    });
  }

  Future<void> _loadEditorial() async {
    setState(() {
      _editorial = _Sec(loading: true);
    });
    final result = await recommendRepository.fetchEditorialPicks();
    if (!mounted) return;
    setState(() {
      _editorial = _Sec(
        data: result,
        loading: false,
        error: result.playlists.isEmpty ? result.error : '',
      );
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadStyle(useSelectedTags: _selectedTagIds.isNotEmpty),
      _loadPlaylists(),
      _loadEditorial(),
    ]);
  }

  void _toggleStyleTag(StyleTag tag) {
    setState(() {
      if (!_selectedTagIds.remove(tag.id)) {
        _selectedTagIds.add(tag.id);
      }
    });
    _loadStyle(useSelectedTags: true);
  }

  List<Track> get _styleTracks => _style.data?.tracks ?? const [];

  String get _styleSummary {
    if (_selectedTagIds.isEmpty) return '默认推荐';
    final names = <String>[];
    for (final g in _style.data?.groups ?? const <StyleTagGroup>[]) {
      for (final t in g.child) {
        if (_selectedTagIds.contains(t.id)) names.add(t.name);
      }
    }
    return names.isEmpty ? '默认推荐' : names.join(' / ');
  }

  void _playStyleAll() {
    final tracks = _styleTracks;
    if (tracks.isEmpty) return;
    ref.read(playerControllerProvider.notifier).playQueue(tracks, startIndex: 0);
    context.push('/player');
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final player = ref.watch(playerControllerProvider);
    final auth = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (prev, next) {
      final wasLogged = prev?.isLogged ?? false;
      if (!wasLogged && next.isLogged) {
        _refreshAll();
      }
    });

    final hour = DateTime.now().hour;
    final greeting = switch (hour) {
      < 6 => '凌晨好',
      < 9 => '早上好',
      < 12 => '上午好',
      < 14 => '中午好',
      < 18 => '下午好',
      _ => '晚上好',
    };

    final styleTracks = _styleTracks;
    final styleGroups = _style.data?.groups ?? const <StyleTagGroup>[];
    final playlistItems =
        _playlists.data?.playlists ?? const <PlaylistBrief>[];
    final editorialItems =
        _editorial.data?.playlists ?? const <PlaylistBrief>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('为你推荐'),
        actions: [
          if (!auth.isLogged)
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('登录'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  KugoSpacing.lg,
                  KugoSpacing.md,
                  KugoSpacing.lg,
                  KugoSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.isLogged ? greeting : '为你推荐',
                      style: kugo.greeting,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '由此开启好心情 ~',
                      style: kugo.caption.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: KugoSpacing.lg),
                    const _FeatureEntryRow(),
                  ],
                ),
              ),
            ),

            // 风格推荐
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '风格推荐',
                showAccent: true,
                actionLabel: styleTracks.isEmpty ? null : '播放全部',
                onAction: styleTracks.isEmpty ? null : _playStyleAll,
              ),
            ),
            SliverToBoxAdapter(
              child: _StylePanel(
                loading: _style.loading,
                error: _style.error,
                groups: styleGroups,
                activeGroupName: _activeGroupName,
                selectedTagIds: _selectedTagIds,
                summary: _styleSummary,
                tracks: styleTracks,
                isPlaying: (track) =>
                    player.current?.id == track.id && player.isPlaying,
                onGroupTap: (name) => setState(() => _activeGroupName = name),
                onTagTap: _toggleStyleTag,
                onRetry: () => _loadStyle(
                  useSelectedTags: _selectedTagIds.isNotEmpty,
                ),
                onTrackTap: (index) {
                  ref
                      .read(playerControllerProvider.notifier)
                      .playQueue(styleTracks, startIndex: index);
                  context.push('/player');
                },
              ),
            ),

            // 推荐歌单
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '推荐歌单',
                showAccent: true,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final cat
                          in RecommendRepository.recommendPlaylistCategories)
                        ChoiceChip(
                          label: Text(cat.label),
                          selected: _playlistCategoryId == cat.id,
                          onSelected: (_) {
                            if (_playlistCategoryId == cat.id) return;
                            setState(() => _playlistCategoryId = cat.id);
                            _loadPlaylists();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ..._playlistSlivers(
              loading: _playlists.loading,
              error: _playlists.error,
              items: playlistItems,
              onRetry: _loadPlaylists,
            ),

            // 编辑精选
            SliverToBoxAdapter(
              child: const SectionHeader(title: '编辑精选', showAccent: true),
            ),
            ..._playlistSlivers(
              loading: _editorial.loading,
              error: _editorial.error,
              items: editorialItems,
              onRetry: _loadEditorial,
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }

  List<Widget> _playlistSlivers({
    required bool loading,
    required String error,
    required List<PlaylistBrief> items,
    required VoidCallback onRetry,
  }) {
    if (loading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(KugoSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _SectionStatus(
            message: error.isEmpty ? '暂无内容' : error,
            onRetry: onRetry,
          ),
        ),
      ];
    }
    return [
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
            final playlist = items[index];
            return PlaylistCard(
              playlist: playlist,
              width: double.infinity,
              onTap: () =>
                  context.push('/playlist/${playlist.id}', extra: playlist),
            );
          }, childCount: items.length),
        ),
      ),
    ];
  }
}

class _FeatureEntryRow extends StatelessWidget {
  const _FeatureEntryRow();

  @override
  Widget build(BuildContext context) {
    final day = DateTime.now().day.toString();
    return Row(
      children: [
        Expanded(
          child: _FeatureCard(
            key: const ValueKey('hub_daily_card'),
            badge: day,
            heroTag: KugoHeroTags.dailyRecommendBadge,
            title: '每日推荐',
            subtitle: '为你量身定制',
            usePrimaryGradient: true,
            onTap: () => context.push('/daily'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _FeatureCard(
            key: const ValueKey('hub_rank_card'),
            badge: 'TOP',
            title: '排行榜',
            subtitle: '实时热门趋势',
            usePrimaryGradient: false,
            onTap: () => context.push('/ranks'),
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.usePrimaryGradient,
    this.heroTag,
    required this.onTap,
  });

  final String badge;
  final String title;
  final String subtitle;
  final bool usePrimaryGradient;
  final String? heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final gradient = usePrimaryGradient
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kugo.primary,
              Color.lerp(kugo.primary, kugo.secondary, 0.35)!,
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kugo.secondary,
              Color.lerp(kugo.secondary, kugo.primary, 0.40)!,
            ],
          );
    final accent = usePrimaryGradient ? kugo.primary : kugo.secondary;

    final badgeContainer = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: gradient,
      ),
      alignment: Alignment.center,
      child: Text(
        badge,
        style: TextStyle(
          color: Colors.white,
          fontSize: badge.length > 2 ? 12 : 16,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          decoration: TextDecoration.none,
        ),
      ),
    );

    final badgeWidget = (heroTag != null && heroTag!.isNotEmpty)
        ? Hero(
            tag: heroTag!,
            flightShuttleBuilder: heroTag == KugoHeroTags.dailyRecommendBadge
                ? KugoHeroTags.dailyRecommendBadgeFlightShuttle
                : null,
            child: Material(
              type: MaterialType.transparency,
              child: badgeContainer,
            ),
          )
        : badgeContainer;

    return Material(
      color: kugo.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kugo.divider),
          ),
          child: Row(
            children: [
              badgeWidget,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kugo.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: accent,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StylePanel extends StatelessWidget {
  const _StylePanel({
    required this.loading,
    required this.error,
    required this.groups,
    required this.activeGroupName,
    required this.selectedTagIds,
    required this.summary,
    required this.tracks,
    required this.isPlaying,
    required this.onGroupTap,
    required this.onTagTap,
    required this.onRetry,
    required this.onTrackTap,
  });

  final bool loading;
  final String error;
  final List<StyleTagGroup> groups;
  final String activeGroupName;
  final Set<String> selectedTagIds;
  final String summary;
  final List<Track> tracks;
  final bool Function(Track track) isPlaying;
  final ValueChanged<String> onGroupTap;
  final ValueChanged<StyleTag> onTagTap;
  final VoidCallback onRetry;
  final ValueChanged<int> onTrackTap;

  StyleTagGroup? get _active {
    for (final g in groups) {
      if (g.name == activeGroupName) return g;
    }
    return groups.isEmpty ? null : groups.first;
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);

    if (loading && tracks.isEmpty && groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(KugoSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error.isNotEmpty && tracks.isEmpty && groups.isEmpty) {
      return _SectionStatus(message: error, onRetry: onRetry);
    }

    final active = _active;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kugo.surface,
              borderRadius: BorderRadius.circular(KugoRadius.card),
              border: Border.all(color: kugo.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: kugo.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary,
                        style: kugo.caption.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final g = groups[index];
                        final selected = active?.name == g.name;
                        return ChoiceChip(
                          label: Text(g.name),
                          selected: selected,
                          onSelected: (_) => onGroupTap(g.name),
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ),
                ],
                if (active != null && active.child.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in active.child)
                        FilterChip(
                          label: Text(tag.name),
                          selected: selectedTagIds.contains(tag.id),
                          onSelected: (_) => onTagTap(tag),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: KugoSpacing.md),
          if (loading && tracks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(KugoSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            )
          else if (tracks.isEmpty)
            _SectionStatus(
              message: error.isEmpty ? '暂无风格推荐' : error,
              onRetry: onRetry,
            )
          else
            for (var i = 0; i < tracks.length; i++)
              Builder(
                builder: (context) {
                  final track = tracks[i];
                  return TrackTile(
                    track: track,
                    isPlaying: isPlaying(track),
                    onArtistTap: artistTapFor(context, track),
                    onTap: () => onTrackTap(i),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _SectionStatus extends StatelessWidget {
  const _SectionStatus({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KugoSpacing.lg,
        vertical: KugoSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: kugo.caption),
          if (onRetry != null) ...[
            const SizedBox(height: KugoSpacing.sm),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}


