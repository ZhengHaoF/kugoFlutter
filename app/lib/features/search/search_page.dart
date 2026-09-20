import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kugo_theme.dart';
import '../../core/theme/kugo_tokens.dart';
import '../../data/repositories/search_repository.dart';
import '../../features/player/player_controller.dart';
import '../../shared/widgets/async_body.dart';
import '../../shared/widgets/common.dart';
import 'search_controller.dart';

/// Multi-type search: songs / playlists / albums / artists.
///
/// Each tab hits its own kugou endpoint (see [SearchType]) and paginates
/// independently. The hot-keyword view is shown until the first search runs.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _repo = searchRepository;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  List<String> _hot = const [];

  @override
  void initState() {
    super.initState();
    _loadHot();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = GoRouterState.of(context).uri.queryParameters['q'];
      if (q == null || q.trim().isEmpty) return;
      _controller.text = q.trim();
      _submit(q.trim());
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHot() async {
    final hot = await _repo.hotKeywords();
    if (!mounted) return;
    setState(() => _hot = hot);
  }

  Future<void> _submit(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    _focus.unfocus();
    await ref.read(searchControllerProvider.notifier).submit(kw);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining > 320) return;
    final notifier = ref.read(searchControllerProvider.notifier);
    final active = ref.read(searchControllerProvider).active;
    notifier.loadMore(active);
  }

  Future<void> _switchTab(SearchType type) async {
    await ref.read(searchControllerProvider.notifier).select(type);
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final state = ref.watch(searchControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KugoSpacing.lg,
              0,
              KugoSpacing.lg,
              KugoSpacing.md,
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: false,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              style: kugo.body,
              decoration: InputDecoration(
                hintText: '搜索歌曲、歌单、专辑、歌手',
                hintStyle: kugo.caption,
                filled: true,
                fillColor: kugo.surface,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: kugo.textSecondary,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    _controller.clear();
                    ref.read(searchControllerProvider.notifier).reset();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!state.searched)
            Expanded(
              child: _HotKeywords(
                hot: _hot,
                onTap: (kw) {
                  _controller.text = kw;
                  _submit(kw);
                },
              ),
            )
          else ...[
            _TabBar(
              active: state.active,
              tabs: state.tabs,
              onSelect: _switchTab,
            ),
            Expanded(
              child: _TabResults(
                scroll: _scroll,
                onRetry: () => ref
                    .read(searchControllerProvider.notifier)
                    .retry(state.active),
                onPlaySong: (index) => _playSong(state, index),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _playSong(SearchState state, int index) async {
    final tracks = songItemsOf(state.activeTab);
    if (index < 0 || index >= tracks.length) return;
    await ref
        .read(playerControllerProvider.notifier)
        .playQueue(tracks, startIndex: index);
    if (mounted) context.push('/player');
  }
}

/// The four type tabs, each showing whether it has already been loaded and
/// how many rows it holds.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.active,
    required this.tabs,
    required this.onSelect,
  });

  final SearchType active;

  /// Only holds entries for tabs that have been requested (lazy loading).
  final Map<SearchType, SearchTabState> tabs;
  final ValueChanged<SearchType> onSelect;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KugoSpacing.lg),
        children: [
          for (final type in SearchType.values) ...[
            _TabChip(
              label: type.label,
              selected: type == active,
              count: _countOf(type),
              onTap: () => onSelect(type),
              kugo: kugo,
            ),
            const SizedBox(width: KugoSpacing.sm),
          ],
        ],
      ),
    );
  }

  /// `null` until the tab has been loaded, so an unopened tab shows no count
  /// rather than a misleading 0.
  int? _countOf(SearchType type) {
    final tab = tabs[type];
    if (tab == null || !tab.hasLoaded) return null;
    return tab.items.length;
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.count,
    required this.onTap,
    required this.kugo,
  });

  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;
  final KugoTheme kugo;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kugo.primary : kugo.surface,
          borderRadius: BorderRadius.circular(KugoRadius.chip),
        ),
        child: Text(
          count == null ? label : '$label $count',
          style: kugo.caption.copyWith(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? kugo.onAccent : kugo.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Renders the active tab: song rows, or one of the brief-card layouts.
class _TabResults extends ConsumerWidget {
  const _TabResults({
    required this.scroll,
    required this.onRetry,
    required this.onPlaySong,
  });

  final ScrollController scroll;
  final VoidCallback onRetry;
  final ValueChanged<int> onPlaySong;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchControllerProvider);
    final tab = state.activeTab;
    final type = state.active;

    // A first-page load shows the skeleton; a failed load shows retry.
    if (tab.loading && tab.isEmpty) {
      return const SkeletonList();
    }
    if (tab.error.isNotEmpty && tab.isEmpty) {
      return AsyncBody(
        loading: false,
        hasError: true,
        isEmpty: false,
        errorMessage: tab.error,
        onRetry: onRetry,
        child: const SizedBox.shrink(),
      );
    }
    if (tab.isEmpty) {
      return AsyncBody(
        loading: false,
        hasError: false,
        isEmpty: true,
        emptyMessage: '没有找到相关${type.label}',
        onRetry: onRetry,
        child: const SizedBox.shrink(),
      );
    }

    final rows = _rowsFor(context, ref, state, type);
    return ListView.builder(
      controller: scroll,
      // One extra slot for the load-more footer.
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == rows.length) return _Footer(tab: tab, onRetry: onRetry);
        return rows[index];
      },
    );
  }

  List<Widget> _rowsFor(
    BuildContext context,
    WidgetRef ref,
    SearchState state,
    SearchType type,
  ) {
    final tab = state.activeTab;
    final player = ref.watch(playerControllerProvider);
    switch (type) {
      case SearchType.song:
        final tracks = songItemsOf(tab);
        return [
          for (var i = 0; i < tracks.length; i++)
            TrackTile(
              track: tracks[i],
              isPlaying:
                  player.current?.id == tracks[i].id && player.isPlaying,
              onArtistTap: artistTapFor(context, tracks[i]),
              onTap: () => onPlaySong(i),
            ),
        ];
      case SearchType.playlist:
        return [
          for (final p in playlistItemsOf(tab))
            SearchResultRow(
              imageSeed: p.coverUrl,
              title: p.name,
              subtitle: p.creator,
              trailingLabel:
                  p.trackCount > 0 ? '${p.trackCount}首' : p.playCountLabel,
              onTap: p.id.isEmpty
                  ? null
                  : () => context.push('/playlist/${p.id}', extra: p),
            ),
        ];
      case SearchType.album:
        return [
          for (final a in albumItemsOf(tab))
            SearchResultRow(
              imageSeed: a.coverUrl,
              title: a.name,
              subtitle: a.artist,
              trailingLabel: a.trackCount > 0 ? '${a.trackCount}首' : '',
              onTap:
                  a.id.isEmpty ? null : () => context.push('/album/${a.id}'),
            ),
        ];
      case SearchType.artist:
        return [
          for (final a in artistItemsOf(tab))
            SearchResultRow(
              imageSeed: '',
              title: a.name,
              round: true,
              // `search/singer` returns no artwork; a per-row lookup would be
              // an N+1 request storm, so artists render as a plain circle.
              onTap:
                  a.id.isEmpty ? null : () => context.push('/artist/${a.id}'),
            ),
        ];
    }
  }
}

/// Bottom-of-list state: spinner while loading more, retry on failure,
/// or a quiet end-of-results marker.
class _Footer extends StatelessWidget {
  const _Footer({required this.tab, required this.onRetry});

  final SearchTabState tab;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final Widget child;
    if (tab.loadingMore) {
      child = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (tab.error.isNotEmpty && tab.items.isNotEmpty) {
      // A failed *page* keeps the rows we already have and offers a retry,
      // rather than blowing the whole tab away.
      child = TextButton(
        onPressed: onRetry,
        child: Text('加载失败，点击重试', style: kugo.caption),
      );
    } else if (!tab.hasMore) {
      child = Text('没有更多了', style: kugo.caption.copyWith(fontSize: 12));
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KugoSpacing.lg),
      child: Center(child: child),
    );
  }
}

class _HotKeywords extends StatelessWidget {
  const _HotKeywords({required this.hot, required this.onTap});

  final List<String> hot;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final kugo = KugoTheme.of(context);
    final items = hot.isEmpty
        ? const ['周杰伦', '林俊杰', '陈奕迅', '民谣', '说唱', '粤语']
        : hot;
    return ListView(
      padding: const EdgeInsets.all(KugoSpacing.lg),
      children: [
        Text(
          '热门搜索',
          style: kugo.section.copyWith(fontSize: 16),
        ),
        const SizedBox(height: KugoSpacing.md),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kw in items)
              ActionChip(
                label: Text(kw),
                backgroundColor: kugo.surface,
                labelStyle: kugo.caption.copyWith(fontSize: 13),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KugoRadius.chip),
                ),
                onPressed: () => onTap(kw),
              ),
          ],
        ),
      ],
    );
  }
}
