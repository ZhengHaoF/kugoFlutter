import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/catalog_repository.dart';

import 'fakes/fake_kugo_client.dart';

/// 专辑 / 歌手详情映射。
///
/// 上游同一个接口会把歌曲数组挂在 `data.list` / `data.info` / 顶层 `list`
/// 三种位置之一，`fetchAlbum` 因此有一条「拿不到歌就换 `album/song` 再要一次」
/// 的兜底路径——这条分支值得单独守住。
void main() {
  group('fetchAlbum', () {
    test('空 id 直接返回 null，不发请求', () async {
      final client = FakeKugoClient(onJson: (_) => {});
      expect(await CatalogRepository(client: client).fetchAlbum('  '), isNull);
      expect(client.jsonCalls, isEmpty);
    });

    test('data.list 里的歌曲被映射，字段回填', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/album/info')) {
          return {
            'data': {
              'albumname': '魔杰座',
              'singername': '周杰伦',
              'publish_time': '2008-10-15',
              'intro': '专辑简介',
              'cover': 'http://img/cover.jpg',
              'list': [
                {
                  'audio_id': '1001',
                  'songname': '稻香',
                  'singername': '周杰伦',
                  'hash': 'AABBCC',
                },
                {
                  'audio_id': '1002',
                  'songname': '给我一首歌的时间',
                  'singername': '周杰伦',
                  'hash': 'DDEEFF',
                },
              ],
            },
          };
        }
        return {};
      });

      final album = await CatalogRepository(client: client).fetchAlbum('9001');
      expect(album, isNotNull);
      expect(album!.id, '9001');
      expect(album.name, '魔杰座');
      expect(album.artist, '周杰伦');
      expect(album.publishTime, '2008-10-15');
      expect(album.intro, '专辑简介');
      expect(album.songs.length, 2);
      expect(album.songs.first.name, '稻香');
      expect(album.songs.first.artist, '周杰伦');
      expect(album.songs.first.hash, 'aabbcc'); // hash 统一小写
      // 一次就够，不该触发兜底接口。
      expect(client.jsonCalls.length, 1);
    });

    test('顶层 list 也能识别（部分上游把歌曲放最外层）', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/album/info')) {
          return {
            'list': [
              {'audio_id': '1', 'songname': '第一首', 'hash': 'AA'},
            ],
          };
        }
        return {};
      });
      final album = await CatalogRepository(client: client).fetchAlbum('1');
      expect(album!.songs.length, 1);
      expect(client.jsonCalls.length, 1);
    });

    test('info 里没歌 → 回退到 album/song 接口再要一次', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/album/info')) {
          return {
            'data': {'albumname': '空专辑', 'list': <dynamic>[]},
          };
        }
        if (url.contains('/album/song')) {
          return {
            'data': {
              'info': [
                {'audio_id': '7', 'songname': '兜底来的歌', 'hash': 'BB'},
              ],
            },
          };
        }
        return {};
      });

      final album = await CatalogRepository(client: client).fetchAlbum('42');
      expect(album!.name, '空专辑');
      expect(album.songs.length, 1);
      expect(album.songs.first.name, '兜底来的歌');
      // info 一次 + 兜底一次。
      expect(client.jsonCalls.length, 2);
      expect(client.jsonCalls[1], contains('/album/song'));
    });

    test('两个接口都拿不到歌 → 仍返回专辑头信息（歌曲为空）', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/album/info')) {
          return {
            'data': {'albumname': '只有头', 'list': <dynamic>[]},
          };
        }
        return {'data': {'info': <dynamic>[]}};
      });
      final album = await CatalogRepository(client: client).fetchAlbum('42');
      expect(album!.name, '只有头');
      expect(album.songs, isEmpty);
    });

    test('接口抛错 → 返回 null 而不是往上抛', () async {
      final client = FakeKugoClient(onJson: null);
      expect(await CatalogRepository(client: client).fetchAlbum('1'), isNull);
    });

    test('封面缺失时用专辑 id 兜底，不让 UI 拿到空串', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/album/info')) {
          return {
            'data': {'albumname': '无封面', 'list': <dynamic>[]},
          };
        }
        return {};
      });
      final album = await CatalogRepository(client: client).fetchAlbum('555');
      expect(album!.coverUrl, isNotEmpty);
    });
  });

  group('fetchArtist', () {
    test('空 id 直接返回 null', () async {
      final client = FakeKugoClient(onJson: (_) => {});
      expect(await CatalogRepository(client: client).fetchArtist(''), isNull);
      expect(client.jsonCalls, isEmpty);
    });

    test('歌手头信息映射（含粉丝数格式化与计数别名）', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/info')) {
          return {
            'data': {
              'singername': '周杰伦',
              'avatar': 'http://img/avatar.jpg',
              'intro': '歌手简介',
              'fans_count': 1234567,
              'birthday': '1979-01-18',
              'songcount': 328,
              'albumcount': 15,
              'mvcount': 42,
            },
          };
        }
        return {};
      });

      final artist = await CatalogRepository(client: client).fetchArtist('1234');
      expect(artist!.id, '1234');
      expect(artist.name, '周杰伦');
      expect(artist.intro, '歌手简介');
      expect(artist.fansLabel, isNotEmpty); // formatCount 输出
      expect(artist.birthday, '1979-01-18');
      expect(artist.songCount, 328);
      expect(artist.albumCount, 15);
      expect(artist.mvCount, 42);
      // 歌曲单独分页拉，这里必须是空的。
      expect(artist.songs, isEmpty);
    });

    test('计数字段用下划线别名（song_count 等）也能取到', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/info')) {
          return {
            'data': {
              'singername': 'someone',
              'song_count': 10,
              'album_count': 2,
              'mv_count': 3,
            },
          };
        }
        return {};
      });
      final artist = await CatalogRepository(client: client).fetchArtist('1');
      expect(artist!.songCount, 10);
      expect(artist.albumCount, 2);
      expect(artist.mvCount, 3);
    });

    test('粉丝数为 0 时 fansLabel 留空（不显示 "0 粉丝"）', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/info')) {
          return {'data': {'singername': 'x', 'fans_count': 0}};
        }
        return {};
      });
      final artist = await CatalogRepository(client: client).fetchArtist('1');
      expect(artist!.fansLabel, isEmpty);
    });

    test('接口抛错 → 返回 null', () async {
      final client = FakeKugoClient(onJson: null);
      expect(await CatalogRepository(client: client).fetchArtist('1'), isNull);
    });
  });

  group('fetchArtistSongs', () {
    test('空 id 返回空页', () async {
      final client = FakeKugoClient(onJson: (_) => {});
      final page = await CatalogRepository(client: client).fetchArtistSongs('');
      expect(page.songs, isEmpty);
      expect(page.total, 0);
      expect(page.hasMore, isFalse);
      expect(client.jsonCalls, isEmpty);
    });

    test('分页参数与 sort 透传到 URL', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/song')) {
          return {
            'data': {
              'total': 100,
              'info': [
                {'audio_id': '1', 'songname': 'a', 'hash': 'AA'},
              ],
            },
          };
        }
        return {};
      });

      await CatalogRepository(client: client).fetchArtistSongs(
        '77',
        page: 2,
        pageSize: 30,
        sort: ArtistSongSort.newest,
      );

      final url = Uri.decodeComponent(client.jsonCalls.single);
      expect(url, contains('singerid=77'));
      expect(url, contains('page=2'));
      expect(url, contains('pagesize=30'));
      expect(url, contains('sort=new'));
    });

    test('total 已知时按 total 判 hasMore', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/song')) {
          return {
            'data': {
              'total': 35,
              'info': List.generate(
                30,
                (i) => {'audio_id': '$i', 'songname': 's$i', 'hash': 'AA$i'},
              ),
            },
          };
        }
        return {};
      });

      final page = await CatalogRepository(client: client)
          .fetchArtistSongs('1', page: 1, pageSize: 30);
      expect(page.songs.length, 30);
      expect(page.total, 35);
      // 30 * 1 < 35 → 还有下一页。
      expect(page.hasMore, isTrue);
    });

    test('total 已知且已到末尾 → hasMore false', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/song')) {
          return {
            'data': {
              'total': 60,
              'info': List.generate(
                30,
                (i) => {'audio_id': '$i', 'songname': 's$i', 'hash': 'AA$i'},
              ),
            },
          };
        }
        return {};
      });

      final page = await CatalogRepository(client: client)
          .fetchArtistSongs('1', page: 2, pageSize: 30);
      // 30 * 2 >= 60 → 没有更多。
      expect(page.hasMore, isFalse);
    });

    test('total 缺失时退回用本页条数填 total', () async {
      final client = FakeKugoClient(onJson: (url) {
        if (url.contains('/singer/song')) {
          return {
            'data': {
              'info': [
                {'audio_id': '1', 'songname': 'a', 'hash': 'AA'},
                {'audio_id': '2', 'songname': 'b', 'hash': 'BB'},
              ],
            },
          };
        }
        return {};
      });

      final page = await CatalogRepository(client: client)
          .fetchArtistSongs('1', pageSize: 30);
      expect(page.total, 2);
      // 本页不足一页 → 没有更多。
      expect(page.hasMore, isFalse);
    });

    test('接口抛错 → 空页', () async {
      final client = FakeKugoClient(onJson: null);
      final page = await CatalogRepository(client: client).fetchArtistSongs('1');
      expect(page.songs, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });
}
