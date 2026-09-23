import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../data/repositories/search_repository.dart';

/// Page size used by every tab, matching the repository default.
const kSearchPageSize = 30;

/// Per-tab state. Each tab paginates **independently** so switching away and
/// back preserves the user's scroll position / page.
class SearchTabState {
  const SearchTabState({
    this.items = const [],
    this.total,
    this.page = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error = '',
  });

  final List<Object> items;

  /// Server total when known; `null` means "not reported" (singer tab).
  final int? total;

  /// Highest page loaded so far; `0` = nothing loaded yet.
  final int page;
  final bool loading;
  final bool loadingMore;
  final String error;

  bool get hasLoaded => page > 0;

  bool get isEmpty => items.isEmpty;

  /// Whether another page exists.
  ///
  /// Uses `total` when available, otherwise falls back to "did the last page
  /// come back full?" — a thin page means we hit the end.
  bool get hasMore {
    if (!hasLoaded || loading || loadingMore) return false;
    final t = total;
    if (t != null) return page * kSearchPageSize < t;
    return items.length >= page * kSearchPageSize;
  }

  SearchTabState copyWith({
    List<Object>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) {
    return SearchTabState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error ?? this.error,
    );
  }
}

class SearchState {
  const SearchState({
    this.keyword = '',
    this.active = SearchType.song,
    this.tabs = const {},
    this.searched = false,
  });

  final String keyword;
  final SearchType active;

  /// Lazily populated — a tab only appears here once it has been requested.
  final Map<SearchType, SearchTabState> tabs;
  final bool searched;

  SearchTabState tab(SearchType type) =>
      tabs[type] ?? const SearchTabState();

  SearchTabState get activeTab => tab(active);

  SearchState copyWith({
    String? keyword,
    SearchType? active,
    Map<SearchType, SearchTabState>? tabs,
    bool? searched,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      active: active ?? this.active,
      tabs: tabs ?? this.tabs,
      searched: searched ?? this.searched,
    );
  }
}

class SearchController extends Notifier<SearchState> {
  SearchController({SearchRepository? repository})
      : _repo = repository ?? searchRepository;

  final SearchRepository _repo;

  /// Guards against a slow response from a previous keyword clobbering the
  /// results of the current one.
  int _requestToken = 0;

  @override
  SearchState build() => const SearchState();

  /// Runs a fresh search. Clears every tab — a new keyword invalidates all of
  /// them, even the ones the user has not opened yet.
  ///
  /// Also returns to the song tab: a brand-new keyword should always start
  /// from the same place, not from whichever tab the user happened to be
  /// looking at when they typed it.
  ///
  /// All four tabs load in parallel so counts fill in without extra taps and
  /// every request shows up in the network log immediately.
  Future<void> submit(String rawKeyword) async {
    final keyword = rawKeyword.trim();
    if (keyword.isEmpty) return;
    _requestToken++;
    state = const SearchState(active: SearchType.song).copyWith(
      keyword: keyword,
      searched: true,
    );
    await Future.wait([
      for (final type in SearchType.values) _loadPage(type, 1),
    ]);
  }

  /// Switches tab, loading its first page on demand.
  ///
  /// An already-loaded tab is shown as-is — switching back must not refetch.
  Future<void> select(SearchType type) async {
    if (state.active == type) return;
    state = state.copyWith(active: type);
    final tab = state.tab(type);
    if (tab.hasLoaded || tab.loading) return;
    if (state.keyword.isEmpty) return;
    await _loadPage(type, 1);
  }

  /// Loads the next page for a tab, if there is one.
  Future<void> loadMore(SearchType type) async {
    final tab = state.tab(type);
    if (!tab.hasMore) return;
    await _loadPage(type, tab.page + 1);
  }

  Future<void> retry(SearchType type) async {
    if (state.keyword.isEmpty) return;
    await _loadPage(type, 1);
  }

  /// Clears results and returns to the hot-keyword view.
  void reset() {
    _requestToken++;
    state = SearchState(active: state.active);
  }

  Future<void> _loadPage(SearchType type, int page) async {
    final keyword = state.keyword;
    if (keyword.isEmpty) return;
    final token = _requestToken;
    final isFirstPage = page <= 1;

    _patch(type, (t) => t.copyWith(
          loading: isFirstPage,
          loadingMore: !isFirstPage,
          error: '',
        ));

    try {
      final result = await _fetch(type, keyword, page);
      if (token != _requestToken) return; // A newer search superseded this one.

      final fetched = List<Object>.of(result.items, growable: true);

      _patch(type, (t) {
        final merged = isFirstPage
            ? fetched
            : (List<Object>.of(t.items, growable: true)..addAll(fetched));
        return t.copyWith(
          items: merged,
          total: result.total,
          page: page,
          loading: false,
          loadingMore: false,
          error: '',
        );
      });
    } catch (e) {
      if (token != _requestToken) return;
      _patch(type, (t) => t.copyWith(
            loading: false,
            loadingMore: false,
            error: _friendlyError(e),
          ));
    }
  }

  Future<SearchPageResult<Object>> _fetch(
    SearchType type,
    String keyword,
    int page,
  ) async {
    switch (type) {
      case SearchType.song:
        final r = await _repo.searchSongsPage(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
        return SearchPageResult<Object>(items: r.items, total: r.total);
      case SearchType.playlist:
        final r = await _repo.searchPlaylists(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
        return SearchPageResult<Object>(items: r.items, total: r.total);
      case SearchType.album:
        final r = await _repo.searchAlbums(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
        return SearchPageResult<Object>(items: r.items, total: r.total);
      case SearchType.artist:
        final r = await _repo.searchArtists(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
        return SearchPageResult<Object>(items: r.items, total: r.total);
    }
  }

  void _patch(SearchType type, SearchTabState Function(SearchTabState) fn) {
    final next = Map<SearchType, SearchTabState>.of(state.tabs);
    next[type] = fn(state.tab(type));
    state = state.copyWith(tabs: next);
  }

  /// Mirrors the wording the old single-tab page used for network failures.
  String _friendlyError(Object e) {
    final msg = e.toString();
    final network = msg.contains('Handshake') ||
        msg.contains('URL过滤') ||
        msg.contains('Access Deny') ||
        msg.contains('Connection terminated') ||
        msg.contains('timeout') ||
        msg.contains('SocketException');
    return network ? '网络不可达或被网关拦截，请检查网络后重试' : '搜索失败，请重试';
  }
}

/// Exposed so tests can inject a repository double.
final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

/// Convenience for the UI layer: typed view of a song tab's items.
List<Track> songItemsOf(SearchTabState tab) =>
    tab.items.whereType<Track>().toList();

List<PlaylistBrief> playlistItemsOf(SearchTabState tab) =>
    tab.items.whereType<PlaylistBrief>().toList();

List<AlbumBrief> albumItemsOf(SearchTabState tab) =>
    tab.items.whereType<AlbumBrief>().toList();

List<ArtistBrief> artistItemsOf(SearchTabState tab) =>
    tab.items.whereType<ArtistBrief>().toList();
