import 'dart:convert';

import 'package:kugo/core/api/kugo_client.dart';
import 'package:kugo/core/api/mappers.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves canned JSON keyed by the endpoint path in the request URL.
class _FakeClient extends KugoClient {
  _FakeClient(this.responses);

  /// path fragment → raw JSON body (String or Map).
  final Map<String, Object?> responses;
  final List<String> requestedPaths = [];

  @override
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query}) async {
    final uri = Uri.parse(url);
    requestedPaths.add(uri.path);
    for (final entry in responses.entries) {
      if (uri.path.contains(entry.key)) {
        final body = entry.value;
        return body is String ? jsonDecode(body) : body;
      }
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

void main() {
  group('SearchRepository — endpoint routing', () {
    test('song tab hits search/song and parses songs', () async {
      final client = _FakeClient({
        '/search/song': {
          'status': 1,
          'data': {
            'total': 480,
            'info': [
              {
                'hash': 'ABC',
                'songname': '晴天',
                'singername': '周杰伦',
                'singers': [
                  {'id': 3520, 'name': '周杰伦'},
                ],
                'duration': 269,
              },
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchSongsPage('晴天');

      expect(page.items, hasLength(1));
      expect(page.items.first.name, '晴天');
      expect(page.items.first.artistId, '3520');
      expect(page.total, 480);
      expect(client.requestedPaths.single, contains('/search/song'));
    });

    test('searchSongs returns the item list without pagination metadata', () async {
      final client = _FakeClient({
        '/search/song': {
          'data': {
            'total': 480,
            'info': [
              {'hash': 'ABC', 'songname': '晴天', 'singername': '周杰伦'},
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final list = await repo.searchSongs('晴天');
      expect(list, hasLength(1));
      expect(list.first.name, '晴天');
    });

    test('playlist tab hits search/special', () async {
      final client = _FakeClient({
        '/search/special': {
          'status': 1,
          'data': {
            'total': 480,
            'info': [
              {
                'specialid': 7845129,
                'specialname': '短视频BGM精选',
                'nickname': '我在天上飞',
                'songcount': 216,
                'playcount': 772700746,
              },
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchPlaylists('晴天');

      expect(page.items, hasLength(1));
      final p = page.items.first;
      // Must be the numeric specialid — /playlist/:id strips non-digits.
      expect(p.id, '7845129');
      expect(p.name, '短视频BGM精选');
      expect(p.creator, '我在天上飞');
      expect(p.trackCount, 216);
      expect(client.requestedPaths.single, contains('/search/special'));
    });

    test('album tab hits search/album and keeps numeric albumid', () async {
      final client = _FakeClient({
        '/search/album': {
          'status': 1,
          'data': {
            'total': 500,
            'info': [
              {
                'albumid': 966846,
                'albumname': '叶惠美',
                'singername': '周杰伦',
                'songcount': 11,
                'publishtime': '2003-07-31 00:00:00',
              },
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchAlbums('晴天');

      expect(page.items, hasLength(1));
      final a = page.items.first;
      expect(a.id, '966846');
      expect(a.name, '叶惠美');
      expect(a.artist, '周杰伦');
      expect(a.trackCount, 11);
      expect(a.publishDate, '2003-07-31');
      expect(client.requestedPaths.single, contains('/search/album'));
    });
  });

  group('SearchRepository — singer shape', () {
    test('parses a bare array under `data` (no `info` wrapper)', () async {
      // Real `search/singer` shape: data is the array itself.
      final client = _FakeClient({
        '/search/singer': {
          'status': 1,
          'data': [
            {'singername': '周杰伦', 'singerid': 3520},
            {'singername': '十分想见周杰伦', 'singerid': 7351282},
          ],
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchArtists('周杰伦');

      expect(page.items, hasLength(2));
      expect(page.items.first.id, '3520');
      expect(page.items.first.name, '周杰伦');
      // Endpoint reports no total — must stay null, not a fabricated 0.
      expect(page.total, isNull);
    });

    test('drops entries with no usable id', () async {
      final client = _FakeClient({
        '/search/singer': {
          'data': [
            {'singername': '周杰伦', 'singerid': 3520},
            {'singername': '无 id 的歌手'},
            {'singerid': 999},
          ],
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchArtists('x');

      expect(page.items, hasLength(1));
      expect(page.items.first.id, '3520');
    });

    test('total is null when the payload omits it', () async {
      final client = _FakeClient({
        '/search/special': {
          'data': {
            'info': [
              {'specialid': 1, 'specialname': 'x'},
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchPlaylists('x');
      expect(page.total, isNull);
    });

    test('total tolerates a numeric string', () async {
      final client = _FakeClient({
        '/search/album': {
          'data': {
            'total': '500',
            'info': [
              {'albumid': 1, 'albumname': 'x'},
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final page = await repo.searchAlbums('x');
      expect(page.total, 500);
    });
  });

  group('mapPlaylistInfo id selection', () {
    test('prefers numeric specialid over global_collection_id', () {
      final brief = mapPlaylistInfo({
        'specialid': 7845129,
        'global_collection_id': 'collection_3_509005046_32_0',
        'specialname': 'x',
      });
      // "collection_3_509005046_32_0" → stripped digits give a bogus id.
      expect(brief.id, '7845129');
    });

    test('falls back to global_collection_id when no numeric id exists', () {
      final brief = mapPlaylistInfo({
        'global_collection_id': 'collection_3_509005046_32_0',
        'specialname': 'x',
      });
      expect(brief.id, 'collection_3_509005046_32_0');
    });
  });

  group('mapAlbumBrief / mapArtistBrief', () {
    test('album prefers albumid and normalizes the {size} cover', () {
      final a = mapAlbumBrief({
        'albumid': 966846,
        'albumname': '叶惠美',
        'singername': '周杰伦',
        'imgurl': 'http://imge.kugou.com/stdmusic/{size}/20230920/x.jpg',
        'songcount': 11,
      });
      expect(a.id, '966846');
      expect(a.coverUrl, contains('https://'));
      expect(a.coverUrl, contains('400'));
      expect(a.coverUrl.contains('{size}'), isFalse);
    });

    test('artist maps singerid/singername', () {
      final artist = mapArtistBrief({'singername': '周杰伦', 'singerid': 3520});
      expect(artist.id, '3520');
      expect(artist.name, '周杰伦');
    });
  });

  group('SearchType', () {
    test('exposes the four Chinese tab labels', () {
      expect(SearchType.values.map((e) => e.label).toList(),
          ['歌曲', '歌单', '专辑', '歌手']);
    });
  });

  group('hotKeywords', () {
    test('parses the data.info keyword list', () async {
      final client = _FakeClient({
        '/search/hot': {
          'data': {
            'info': [
              {'keyword': '周杰伦'},
              {'keyword': '林俊杰'},
            ],
          },
        },
      });
      final repo = SearchRepository(client: client);
      final hot = await repo.hotKeywords();
      expect(hot, ['周杰伦', '林俊杰']);
    });
  });
}
