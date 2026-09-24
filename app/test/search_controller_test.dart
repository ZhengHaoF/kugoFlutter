import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugo_client.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/data/sources/kugou/kugou_source.dart';
import 'package:kugo/features/search/search_controller.dart';

/// Records every call and serves scripted pages so we can assert on
/// laziness / per-tab pagination without touching the network.
class _RecordingRepo implements SearchRepository {
  _RecordingRepo({this.total = 90, this.tag = '', this.idPrefix = ''});

  /// Server-reported total for the endpoints that report one.
  final int total;

  /// Prefixed to every recorded call label, so a two-source test can tell
  /// which source was hit.
  final String tag;

  /// Prefixed to generated ids, so interleaving order is assertable.
  final String idPrefix;

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
            id: '${idPrefix}song-$page-$i',
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
    calls.add('$tag$label');
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

/// 第二个音源的测试替身：只做「平台标识 + 委托录制仓库」，用于混排测试。
class _RecordingSource implements MusicSource {
  _RecordingSource(this.platform, this.repo);

  @override
  final MusicPlatform platform;
  final _RecordingRepo repo;

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) =>
      repo.searchSongsPage(keyword, page: page, pageSize: pageSize);

  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) =>
      repo.searchPlaylists(keyword, page: page, pageSize: pageSize);

  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) =>
      repo.searchAlbums(keyword, page: page, pageSize: pageSize);

  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) =>
      repo.searchArtists(keyword, page: page, pageSize: pageSize);

  @override
  Future<PlayUrlResult> resolvePlayUrl(Track track, {AppQuality? preferred}) =>
      throw UnimplementedError();

  @override
  Future<LyricPayload> fetchLyric(Track track) => throw UnimplementedError();
}

ProviderContainer _container(_RecordingRepo repo) =>
    _containerFor([KugouSource(searchRepository: repo)]);

ProviderContainer _containerFor(List<MusicSource> sources) {
  final c = ProviderContainer(
    overrides: [
      searchControllerProvider.overrideWith(
        () => SearchController(registry: MusicSourceRegistry(sources)),
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
      expect(repo.calls, [
        'song:jay:1',
        'playlist:jay:1',
        'album:jay:1',
        'artist:jay:1',
      ]);
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
      expect(
        c.read(searchControllerProvider).tab(SearchType.album).hasLoaded,
        isTrue,
      );

      await n.submit('b');
      final s = c.read(searchControllerProvider);
      expect(s.tab(SearchType.album).hasLoaded, isTrue);
      expect(s.tab(SearchType.song).items, hasLength(30));
      // First keyword loads all four tabs, second keyword reloads all four.
      expect(
        repo.calls,
        [
          'song:a:1',
          'playlist:a:1',
          'album:a:1',
          'artist:a:1',
          'song:b:1',
          'playlist:b:1',
          'album:b:1',
          'artist:b:1',
        ],
      );
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

  group('select — no refetch of loaded tabs', () {
    test('submit loads every tab up front', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      expect(repo.calls, [
        'song:jay:1',
        'playlist:jay:1',
        'album:jay:1',
        'artist:jay:1',
      ]);
      final s = c.read(searchControllerProvider);
      expect(s.tab(SearchType.playlist).hasLoaded, isTrue);
      expect(s.tab(SearchType.album).hasLoaded, isTrue);
      expect(s.tab(SearchType.artist).hasLoaded, isTrue);
    });

    test('switching back to an already-loaded tab does not refetch', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      await n.select(SearchType.album);
      await n.select(SearchType.song);
      await n.select(SearchType.album);

      expect(repo.calls, [
        'song:jay:1',
        'playlist:jay:1',
        'album:jay:1',
        'artist:jay:1',
      ]);
    });

    test('selecting the already-active tab is a no-op', () async {
      final repo = _RecordingRepo();
      final c = _container(repo);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('jay');
      await n.select(SearchType.song);
      expect(repo.calls, [
        'song:jay:1',
        'playlist:jay:1',
        'album:jay:1',
        'artist:jay:1',
      ]);
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

      await n.submit('x'); // all tabs page 1
      await n.loadMore(SearchType.song); // song page 2

      final s = c.read(searchControllerProvider);
      // Song tab accumulated both pages.
      expect(s.tab(SearchType.song).page, 2);
      expect(s.tab(SearchType.song).items, hasLength(60));
      expect(s.tab(SearchType.album).page, 1);
      expect(s.tab(SearchType.album).items, hasLength(30));
      expect(repo.calls, [
        'song:x:1',
        'playlist:x:1',
        'album:x:1',
        'artist:x:1',
        'song:x:2',
      ]);
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
      // All four first pages, but no page 2 for song.
      expect(repo.calls, [
        'song:x:1',
        'playlist:x:1',
        'album:x:1',
        'artist:x:1',
      ]);
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
      final c = _container(repo);

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

  group('multi-source mixing', () {
    ProviderContainer twoSources(_RecordingRepo kg, _RecordingRepo ne) =>
        _containerFor([
          KugouSource(searchRepository: kg),
          _RecordingSource(MusicPlatform.netease, ne),
        ]);

    test('interleaves both sources round-robin', () async {
      final kg = _RecordingRepo(tag: 'kg:', idPrefix: 'kg-');
      final ne = _RecordingRepo(tag: 'ne:', idPrefix: 'ne-');
      final c = twoSources(kg, ne);

      await c.read(searchControllerProvider.notifier).submit('x');
      final tab = c.read(searchControllerProvider).activeTab;
      final songs = songItemsOf(tab);

      // 两源各 30 条 → 交错后 60 条：kg0 ne0 kg1 ne1 …
      expect(songs, hasLength(60));
      expect(
        songs.take(4).map((t) => t.id),
        ['kg-song-1-0', 'ne-song-1-0', 'kg-song-1-1', 'ne-song-1-1'],
      );
      // 混排没有「总数」这回事，但「还有下一页」由任一源决定。
      expect(tab.total, isNull);
      expect(tab.hasMore, isTrue);
    });

    test('loadMore appends the next interleaved page', () async {
      final kg = _RecordingRepo(tag: 'kg:', idPrefix: 'kg-');
      final ne = _RecordingRepo(tag: 'ne:', idPrefix: 'ne-');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.loadMore(SearchType.song);

      final songs = songItemsOf(c.read(searchControllerProvider).activeTab);
      expect(songs, hasLength(120));
      // 第二页也是交错序，不是「一整页酷狗 + 一整页网易」。
      expect(songs[60].id, 'kg-song-2-0');
      expect(songs[61].id, 'ne-song-2-0');
    });

    test('a failing source is ignored while the other still answers', () async {
      final kg = _RecordingRepo(tag: 'kg:', idPrefix: 'kg-');
      final ne = _RecordingRepo(tag: 'ne:')..failing.add(SearchType.song);
      final c = twoSources(kg, ne);

      await c.read(searchControllerProvider.notifier).submit('x');
      final tab = c.read(searchControllerProvider).activeTab;

      expect(songItemsOf(tab), hasLength(30));
      expect(tab.error, isEmpty);
    });

    test('the tab errors only when every source fails', () async {
      final kg = _RecordingRepo()..failing.add(SearchType.song);
      final ne = _RecordingRepo()..failing.add(SearchType.song);
      final c = twoSources(kg, ne);

      await c.read(searchControllerProvider.notifier).submit('x');
      final tab = c.read(searchControllerProvider).activeTab;

      expect(tab.error, '搜索失败，请重试');
      expect(tab.isEmpty, isTrue);
    });
  });

  group('source filter', () {
    ProviderContainer twoSources(_RecordingRepo kg, _RecordingRepo ne) =>
        _containerFor([
          KugouSource(searchRepository: kg),
          _RecordingSource(MusicPlatform.netease, ne),
        ]);

    test('setSourceFilter re-searches against that source only', () async {
      final kg = _RecordingRepo(tag: 'kg:', idPrefix: 'kg-');
      final ne = _RecordingRepo(tag: 'ne:', idPrefix: 'ne-');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      expect(
        songItemsOf(c.read(searchControllerProvider).activeTab),
        hasLength(60),
      );

      await n.setSourceFilter(MusicPlatform.netease);
      final s = c.read(searchControllerProvider);

      expect(s.sourceFilter, MusicPlatform.netease);
      expect(songItemsOf(s.activeTab), hasLength(30));
      expect(songItemsOf(s.activeTab).first.id, 'ne-song-1-0');
      // 换筛选后只打网易云：首轮 4 次 + 重搜 4 次。
      expect(kg.calls, hasLength(4));
      expect(ne.calls, hasLength(8));
    });

    test('the filter survives a new keyword', () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:', idPrefix: 'ne-');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.setSourceFilter(MusicPlatform.netease);
      await n.submit('y');

      final s = c.read(searchControllerProvider);
      expect(s.sourceFilter, MusicPlatform.netease);
      expect(songItemsOf(s.activeTab).first.id, 'ne-song-1-0');
      // 筛选后酷狗一次都没被打。
      expect(kg.calls, isEmpty);
    });

    test('setSourceFilter(null) goes back to mixing', () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      await n.setSourceFilter(MusicPlatform.kugou);
      await n.setSourceFilter(null);

      final s = c.read(searchControllerProvider);
      expect(s.sourceFilter, isNull);
      expect(songItemsOf(s.activeTab), hasLength(60));
    });

    test('picking the current filter is a no-op', () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.submit('x');
      final before = [...kg.calls];
      await n.setSourceFilter(null);

      expect(kg.calls, before);
    });

    test('changing the filter before any search does not hit the network',
        () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:');
      final c = twoSources(kg, ne);

      await c
          .read(searchControllerProvider.notifier)
          .setSourceFilter(MusicPlatform.kugou);

      expect(kg.calls, isEmpty);
      expect(ne.calls, isEmpty);
      expect(c.read(searchControllerProvider).sourceFilter, MusicPlatform.kugou);
    });

    test('applyDefaultSourceFilter seeds the filter before the first search',
        () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:', idPrefix: 'ne-');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      n.applyDefaultSourceFilter(MusicPlatform.netease);
      expect(kg.calls, isEmpty);

      await n.submit('x');
      final s = c.read(searchControllerProvider);
      expect(s.sourceFilter, MusicPlatform.netease);
      expect(songItemsOf(s.activeTab).first.id, 'ne-song-1-0');
      expect(kg.calls, isEmpty, reason: '默认源已筛选，不应再打酷狗');
    });

    test('applyDefaultSourceFilter does not override a manual choice', () async {
      final kg = _RecordingRepo(tag: 'kg:');
      final ne = _RecordingRepo(tag: 'ne:');
      final c = twoSources(kg, ne);
      final n = c.read(searchControllerProvider.notifier);

      await n.setSourceFilter(null);
      n.applyDefaultSourceFilter(MusicPlatform.netease);

      expect(c.read(searchControllerProvider).sourceFilter, isNull);
    });
  });
}
