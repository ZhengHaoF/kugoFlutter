import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugo_client.dart';
import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/search/search_controller.dart';

/// Records every call and serves scripted pages so we can assert on
/// laziness / per-tab pagination without touching the network.
class _RecordingRepo implements SearchRepository {
  _RecordingRepo({this.total = 90});

  /// Server-reported total for the endpoints that report one.
  final int total;

  final List<String> calls = [];

  /// Optional per-request delay so we can test request-token cancelling.
  Duration delay = Duration.zero;

  /// Endpoints that should throw.
  final Set<SearchType> failing = {};

  @override
  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _serve(
      SearchType.song,
      'song:$keyword:$page',
      page,
      pageSize,
      (n) => SearchPageResult<Track>(
        items: List.generate(
          n,
          (i) => Track(
            id: 'song-$page-$i',
            name: 'song-$page-$i',
            artist: 'a',
            album: 'al',
            coverUrl: 'u',
            durationMs: 1,
          ),
        ),
        total: total,
      ),
    );
  }

  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _serve(
      SearchType.playlist,
      'playlist:$keyword:$page',
      page,
      pageSize,
      (n) => SearchPageResult<PlaylistBrief>(
        items: List.generate(
          n,
          (i) => PlaylistBrief(
            id: '${page}0$i',
            name: 'playlist-$page-$i',
            coverUrl: 'u',
          ),
        ),
        total: total,
      ),
    );
  }

  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _serve(
      SearchType.album,
      'album:$keyword:$page',
      page,
      pageSize,
      (n) => SearchPageResult<AlbumBrief>(
        items: List.generate(
          n,
          (i) => AlbumBrief(
            id: '${page}0$i',
            name: 'album-$page-$i',
            coverUrl: 'u',
          ),
        ),
        total: total,
      ),
    );
  }

  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    // Mirrors the real endpoint: no total reported.
    return _serve(
      SearchType.artist,
      'artist:$keyword:$page',
      page,
      pageSize,
      (n) => SearchPageResult<ArtistBrief>(
        items: List.generate(
          n,
          (i) => ArtistBrief(id: '${page}0$i', name: 'artist-$page-$i'),
        ),
      ),
    );
  }

  Future<T> _serve<T>(
    SearchType type,
    String label,
    int page,
    int pageSize,
    T Function(int count) build,
  ) async {
    calls.add(label);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failing.contains(type)) throw Exception('boom');
    // Always return a full page so `hasMore` stays true while total allows.
    return build(pageSize);
  }

  @override
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const [];

  @override
  Future<List<String>> hotKeywords({int count = 20}) async => const [];

  @override
  Future<List<String>> suggest(String keyword) async => const [];
}

/// Throws the same exception the real client does when the network gateway
/// swallows a kugou call, so we can assert on the network-specific wording.
class _GatewayBlockedRepo extends _RecordingRepo {
  @override
  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    throw KugoApiException('网络网关拦截（URL过滤），无法访问酷狗接口', filtered: true);
  }
}

ProviderContainer _container(_RecordingRepo repo) {  final c = ProviderContainer(
    overrides: [
      searchControllerProvider.overrideWith(
        () => SearchController(repository: repo),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('submit', () {
    test('searches the active tab and marks the state as searched', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      await c.read(searchControllerProvider.notifier).submit('jay');
      final s = c.read(searchControllerProvider);

      expect(s.searched, isTrue);
      expect(s.keyword, 'jay');
      expect(s.active, SearchType.song);
      expect(repo.calls, ['song:jay:1']);
      expect(s.activeTab.items, hasLength(30));
    });

    test('ignores blank keywords', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);

      await c.read(searchControllerProvider.notifier).submit('   ');
      expect(repo.calls, isEmpty);
      expect(c.read(searchControllerProvider).searched, isFalse);
    });

    test('trims the keyword', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      await c.read(searchControllerProvider.notifier).submit('  jay ');
      expect(c.read(searchControllerProvider).keyword, 'jay');
    });

    test('a new keyword clears previously loaded tabs', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('a');
      await n.select(SearchType.album);
      expect(
        c.read(searchControllerProvider).tab(SearchType.album).hasLoaded,
        isTrue,
      );

      await n.submit('b');
      final s = c.read(searchControllerProvider);
      expect(s.tab(SearchType.album).hasLoaded, isFalse);
      expect(s.tab(SearchType.song).items, hasLength(30));
      expect(repo.calls, ['song:a:1', 'album:a:1', 'song:b:1']);
    });

    test('does not accumulate duplicate items on repeat submits', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('a');
      expect(c.read(searchControllerProvider).activeTab.items, hasLength(30));
      await n.submit('b');
      expect(c.read(searchControllerProvider).activeTab.items, hasLength(30));
    });
  });

  group('select — lazy loading', () {
    test('only fetches the tab the user actually opens', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      // Four tabs exist but only the song tab has been requested.
      expect(repo.calls, ['song:jay:1']);

      await n.select(SearchType.artist);
      expect(repo.calls, ['song:jay:1', 'artist:jay:1']);
      final s = c.read(searchControllerProvider);
      expect(s.tab(SearchType.playlist).hasLoaded, isFalse);
      expect(s.tab(SearchType.album).hasLoaded, isFalse);
    });

    test('switching back to an already-loaded tab does not refetch', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      await n.select(SearchType.album);
      await n.select(SearchType.song);
      await n.select(SearchType.album);

      expect(repo.calls, ['song:jay:1', 'album:jay:1']);
    });

    test('selecting the already-active tab is a no-op', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      await n.select(SearchType.song);
      expect(repo.calls, ['song:jay:1']);
    });

    test('selecting before any search does not hit the network', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      await c.read(searchControllerProvider.notifier).select(SearchType.album);
      expect(repo.calls, isEmpty);
    });
  });

  group('per-tab pagination', () {
    test('each tab keeps its own page counter', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x'); // song page 1
      await n.loadMore(SearchType.song); // song page 2
      await n.select(SearchType.album); // album page 1

      final s = c.read(searchControllerProvider);
      // Song tab accumulated both pages.
      expect(s.tab(SearchType.song).page, 2);
      expect(s.tab(SearchType.song).items, hasLength(60));
      expect(s.tab(SearchType.album).page, 1);
      expect(s.tab(SearchType.album).items, hasLength(30));
      expect(repo.calls, ['song:x:1', 'song:x:2', 'album:x:1']);
    });

    test('loadMore appends rather than replacing', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      final first = c.read(searchControllerProvider).activeTab.items.first;
      await n.loadMore(SearchType.song);
      final items = c.read(searchControllerProvider).activeTab.items;

      expect(items.first, same(first));
      expect(items, hasLength(60));
      // Page 2 rows really are present, not page 1 twice.
      expect(songItemsOf(c.read(searchControllerProvider).activeTab).last.id,
          'song-2-29');
    });

    test('loadMore does nothing when the tab is unloaded', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      await c.read(searchControllerProvider.notifier).loadMore(
            SearchType.album,
          );
      expect(repo.calls, isEmpty);
    });

    test('stops paginating once the page count covers total', () async {
      // total = 30 → only one page exists.
      final repo = _RecordingRepo(total: 30);
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      expect(c.read(searchControllerProvider).activeTab.hasMore, isFalse);

      await n.loadMore(SearchType.song);
      expect(repo.calls, ['song:x:1']); // no page 2 requested
    });

    test('falls back to page fullness when total is absent (artist tab)',
        () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.select(SearchType.artist);

      final tab = c.read(searchControllerProvider).tab(SearchType.artist);
      // A full page and no total → assume there may be more.
      expect(tab.total, isNull);
      expect(tab.hasMore, isTrue);

      await n.loadMore(SearchType.artist);
      expect(repo.calls, contains('artist:x:2'));
    });
  });

  group('errors', () {
    test('records a friendly message on failure and clears loading', () async {
      final repo = _RecordingRepo()..failing.add(SearchType.album);
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.select(SearchType.album);

      final tab = c.read(searchControllerProvider).tab(SearchType.album);
      // `Exception('boom')` carries no network marker, so we get the
      // generic wording rather than the gateway-blocked one.
      expect(tab.error, '搜索失败，请重试');
      expect(tab.loading, isFalse);
      expect(tab.hasLoaded, isFalse);
    });

    test('uses the network wording for gateway-blocked failures', () async {
      final repo = _GatewayBlockedRepo();
      final c = ProviderContainer(
        overrides: [
          searchControllerProvider.overrideWith(
            () => SearchController(repository: repo),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(searchControllerProvider.notifier).submit('x');
      final tab = c.read(searchControllerProvider).activeTab;
      expect(tab.error, '网络不可达或被网关拦截，请检查网络后重试');
    });

    test('retry refetches the tab', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.select(SearchType.album);
      repo.calls.clear();
      await n.retry(SearchType.album);
      expect(repo.calls, ['album:x:1']);
    });
  });

  group('reset', () {
    test('clears keyword, tabs and searched flag', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      n.reset();

      final s = c.read(searchControllerProvider);
      expect(s.keyword, isEmpty);
      expect(s.searched, isFalse);
      expect(s.tabs, isEmpty);
    });
  });

  group('stale responses', () {
    test('a slow earlier search cannot clobber a newer one', () async {
      final repo = _RecordingRepo()..delay = const Duration(milliseconds: 60);
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      final slow = n.submit('first');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      repo.delay = Duration.zero;
      await n.submit('second');
      await slow;

      final s = c.read(searchControllerProvider);
      expect(s.keyword, 'second');
      // Items must belong to the second search, not the late first one.
      final songs = songItemsOf(s.activeTab);
      expect(songs, hasLength(30));
      expect(songs.first.id, startsWith('song-1-'));
    });
  });

  group('typed accessors', () {
    test('expose correctly typed lists per tab', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      expect(
        songItemsOf(c.read(searchControllerProvider).activeTab),
        hasLength(30),
      );

      await n.select(SearchType.playlist);
      expect(
        playlistItemsOf(c.read(searchControllerProvider).activeTab),
        hasLength(30),
      );

      await n.select(SearchType.album);
      expect(
        albumItemsOf(c.read(searchControllerProvider).activeTab),
        hasLength(30),
      );

      await n.select(SearchType.artist);
      expect(
        artistItemsOf(c.read(searchControllerProvider).activeTab),
        hasLength(30),
      );
    });

    test('the active tab only ever holds its own type', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.select(SearchType.album);

      final active = c.read(searchControllerProvider).activeTab;
      expect(albumItemsOf(active), hasLength(30));
      expect(songItemsOf(active), isEmpty);
    });
  });
}
