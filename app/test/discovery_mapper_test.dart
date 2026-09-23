import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/discovery_repository.dart';

void main() {
  test('extractPlaylistTagGroups maps tag_name + son[].tag_id', () {
    final groups = extractPlaylistTagGroups({
      'status': 1,
      'data': [
        {
          'tag_name': '流派',
          'son': [
            {'tag_id': 12, 'tag_name': '流行'},
            {'tag_id': 13, 'tag_name': '摇滚'},
          ],
        },
      ],
    });
    expect(groups, hasLength(1));
    expect(groups.first.name, '流派');
    expect(groups.first.child, hasLength(2));
    expect(groups.first.child.first.id, '12');
    expect(groups.first.child.first.name, '流行');
  });

  test('extractAlbumsByType flattens region buckets for all', () {
    final albums = extractAlbumsByType({
      'status': 1,
      'data': {
        'chn': [
          {'albumid': 1, 'albumname': '华语碟', 'singername': 'A', 'imgurl': 'a'},
        ],
        'eur': [
          {'albumid': 2, 'albumname': '欧美碟', 'singername': 'B', 'imgurl': 'b'},
        ],
      },
    }, type: 'all');
    expect(albums, hasLength(2));
    expect(albums.first.id, '1');
    expect(albums.last.name, '欧美碟');
  });

  test('extractAlbumsByType filters a single region', () {
    final albums = extractAlbumsByType({
      'status': 1,
      'data': {
        'chn': [
          {'albumid': 1, 'albumname': '华语碟', 'singername': 'A', 'imgurl': 'a'},
        ],
        'eur': [
          {'albumid': 2, 'albumname': '欧美碟', 'singername': 'B', 'imgurl': 'b'},
        ],
      },
    }, type: 'eur');
    expect(albums, hasLength(1));
    expect(albums.single.id, '2');
  });

  test('extractDiscoveryArtists keeps letter groups and drops duplicates', () {
    final artists = extractDiscoveryArtists({
      'status': 1,
      'data': {
        'info': [
          {
            'title': '热门',
            'singer': [
              {'singerid': 1, 'singername': '周杰伦', 'sizable_avatar': 'j'},
              {'singerid': 1, 'singername': '周杰伦'},
            ],
          },
          {
            'title': 'A',
            'singer': [
              {'singerid': 2, 'singername': '阿杜'},
            ],
          },
        ],
      },
    });
    expect(artists, hasLength(2));
    expect(artists.first.letter, '热门');
    expect(artists.first.name, '周杰伦');
    expect(artists.last.letter, 'A');
  });
}
