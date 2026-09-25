import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../../data/repositories/search_repository.dart';
import '../settings/settings_controller.dart';

/// Page size used by every tab; also the unit the sources paginate by.
const kSearchPageSize = 30;

/// Per-tab state. Each tab paginates **independently** so switching away and
/// back preserves the user's scroll position / page.
class SearchTabState {
  const SearchTabState({
    this.items = const [],
    this.total,
    this.hasMoreFlag,
    this.page = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error = '',
  });

  final List<Object> items;

  /// Server total when known; `null` means "not reported" (singer tab) —
  /// and always `null` in mixed-source mode, where no single total exists.
  final int? total;

  /// 混排时无法用单一 `total` 推断「还有没有下一页」（任一源还有就算有），
  /// 由控制器算好写在这里。
  final bool? hasMoreFlag;

  /// Highest page loaded so far; `0` = nothing loaded yet.
  final int page;
  final bool loading;
  final bool loadingMore;
  final String error;

  bool get hasLoaded => page > 0;

  bool get isEmpty => items.isEmpty;

  /// Whether another page exists.
  ///
  /// Uses [hasMoreFlag] when the controller could compute it (always, after a
  /// load), otherwise falls back to `total`, then to "did the last page come
  /// back full?" — a thin page means we hit the end.
  bool get hasMore {
    if (!hasLoaded || loading || loadingMore) return false;
    final flag = hasMoreFlag;
    if (flag != null) return flag;
    final t = total;
    if (t != null) return page * kSearchPageSize < t;
    return items.length >= page * kSearchPageSize;
  }

  SearchTabState copyWith({
    List<Object>? items,
    int? total,
    bool? hasMoreFlag,
    int? page,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) {
    return SearchTabState(
      items: items ?? this.items,
      total: total ?? this.total,
      hasMoreFlag: hasMoreFlag ?? this.hasMoreFlag,
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
    this.sourceFilter,
  });

  final String keyword;
  final SearchType active;

  /// Lazily populated — a tab only appears here once it has been requested.
  final Map<SearchType, SearchTabState> tabs;
  final bool searched;

  /// 音源筛选；`null` = 全部源（混排）。与 [keyword] 一样属于「本次搜索的
  /// 条件」，改它必须重搜（见 [SearchController.setSourceFilter]）。
  final MusicPlatform? sourceFilter;

  SearchTabState tab(SearchType type) =>
      tabs[type] ?? const SearchTabState();

  SearchTabState get activeTab => tab(active);

  SearchState copyWith({
    String? keyword,
    SearchType? active,
    Map<SearchType, SearchTabState>? tabs,
    bool? searched,
    MusicPlatform? sourceFilter,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      active: active ?? this.active,
      tabs: tabs ?? this.tabs,
      searched: searched ?? this.searched,
      sourceFilter: sourceFilter ?? this.sourceFilter,
    );
  }
}

/// 跨源搜索。结果**混排**（轮询交错），不做跨源同曲合并（见方案 §10）。
class SearchController extends Notifier<SearchState> {
  SearchController({MusicSourceRegistry? registry})
      : _registry = registry ?? requireMusicSourceRegistry;

  final MusicSourceRegistry _registry;

  /// Guards against a slow response from a previous keyword clobbering the
  /// results of the current one.
  int _requestToken = 0;

  /// 用户是否显式动过音源筛选（见 [applyDefaultSourceFilter]）。
  bool _sourceFilterTouched = false;

  @override
  SearchState build() => const SearchState();

  /// 已注册且**启用**的音源（音源筛选条用）；≤1 时 UI 不显示筛选条。
  ///
  /// 设置里的整源开关（见 `SettingsController.setEnabledSources`）在此过滤：
  /// 停用的源不参与混排；已在页面的旧结果不动，下次搜索生效。
  List<MusicPlatform> get availablePlatforms => _registry.platforms
      .where(ref.read(settingsControllerProvider).enabledSources.contains)
      .toList();

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
    state = SearchState(
      keyword: keyword,
      active: SearchType.song,
      searched: true,
      // 音源筛选是用户偏好，不随关键词重置。
      sourceFilter: state.sourceFilter,
    );
    await _reloadAll();
  }

  /// 切换音源筛选（`null` = 全部源）。已加载的页只属于旧筛选，留着会串源，
  /// 故换筛选即清空重搜。
  Future<void> setSourceFilter(MusicPlatform? platform) async {
    // 用户显式选过（哪怕选回同一个值）就不再让「默认源」覆盖。
    _sourceFilterTouched = true;
    if (state.sourceFilter == platform) return;
    _requestToken++;
    state = SearchState(
      keyword: state.keyword,
      active: state.active,
      searched: state.searched,
      sourceFilter: platform,
    );
    if (!state.searched || state.keyword.isEmpty) return;
    await _reloadAll();
  }

  /// 应用设置里的「默认源」作为本次会话的初始筛选。
  ///
  /// 只在用户还没搜过、也没手动切过筛选时生效（见方案 §11：默认源只是
  /// 初始值，不做全局音源切换）；后续 [setSourceFilter] 仍可改成「全部」。
  void applyDefaultSourceFilter(MusicPlatform platform) {
    if (state.searched || _sourceFilterTouched) return;
    state = SearchState(active: state.active, sourceFilter: platform);
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
    state = SearchState(
      active: state.active,
      sourceFilter: state.sourceFilter,
    );
  }

  Future<void> _reloadAll() async {
    await Future.wait([
      for (final type in SearchType.values) _loadPage(type, 1),
    ]);
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
          hasMoreFlag: result.hasMore,
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

  /// 当前筛选命中的音源（按注册顺序，决定混排优先级）。
  ///
  /// 停用的源一律剔除；筛选指向已停用的源时回落到「全部启用源」，
  /// 否则用户在设置里关源后，搜索页会一直报「没有可用音源」。
  List<MusicSource> _sources() {
    final enabled = ref.read(settingsControllerProvider).enabledSources;
    final filter = state.sourceFilter;
    if (filter != null && enabled.contains(filter)) {
      return _registry.supports(filter) ? [_registry.of(filter)] : const [];
    }
    return _registry.all.where((s) => enabled.contains(s.platform)).toList();
  }

  Future<({List<Object> items, int? total, bool hasMore})> _fetch(
    SearchType type,
    String keyword,
    int page,
  ) async {
    final sources = _sources();
    final settled = await Future.wait([
      for (final s in sources) _fetchOne(s, type, keyword, page),
    ]);

    final pages = <SearchPageResult<Object>>[];
    Object? firstError;
    for (final r in settled) {
      final page_ = r.page;
      if (page_ != null) {
        pages.add(page_);
      } else {
        firstError ??= r.error;
      }
    }

    // 单源失败忽略（另一个源的结果照样可用）；全失败才算这次取页失败。
    if (pages.isEmpty) {
      throw firstError ?? StateError('没有可用音源');
    }

    return (
      items: _interleave(pages),
      // 只有一个源时总数仍然可信；混排没有「总数」这回事，保持 null。
      total: pages.length == 1 ? pages.first.total : null,
      hasMore: pages.any((p) => _sourceHasMore(p, page)),
    );
  }

  Future<({SearchPageResult<Object>? page, Object? error})> _fetchOne(
    MusicSource source,
    SearchType type,
    String keyword,
    int page,
  ) async {
    try {
      return (page: await _callSource(source, type, keyword, page), error: null);
    } catch (e) {
      return (page: null, error: e);
    }
  }

  Future<SearchPageResult<Object>> _callSource(
    MusicSource source,
    SearchType type,
    String keyword,
    int page,
  ) {
    switch (type) {
      case SearchType.song:
        return source.searchSongs(keyword, page: page, pageSize: kSearchPageSize);
      case SearchType.playlist:
        return source.searchPlaylists(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
      case SearchType.album:
        return source.searchAlbums(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
      case SearchType.artist:
        return source.searchArtists(
          keyword,
          page: page,
          pageSize: kSearchPageSize,
        );
    }
  }

  /// 单源「还有下一页吗」：有 total 用 total，没有就看这一页是否满页。
  bool _sourceHasMore(SearchPageResult<Object> p, int page) {
    final t = p.total;
    if (t != null) return page * kSearchPageSize < t;
    return p.items.length >= kSearchPageSize;
  }

  /// 轮询交错：A0 B0 A1 B1 …（单源时即原序）。不做同曲去重（方案 §10）。
  List<Object> _interleave(List<SearchPageResult<Object>> pages) {
    if (pages.length == 1) return List<Object>.of(pages.first.items);
    var maxLen = 0;
    for (final p in pages) {
      if (p.items.length > maxLen) maxLen = p.items.length;
    }
    final out = <Object>[];
    for (var i = 0; i < maxLen; i++) {
      for (final p in pages) {
        if (i < p.items.length) out.add(p.items[i]);
      }
    }
    return out;
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

/// Exposed so tests can inject a registry double.
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
