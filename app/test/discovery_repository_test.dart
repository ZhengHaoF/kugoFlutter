import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/repositories/discovery_repository.dart';

/// 探索发现页的三个纯提取函数。
///
/// 它们都是 top-level（不是私有方法），就是为了能这样直接喂 JSON 覆盖——
/// 上游同一接口的字段位置在 `data.info` / `data.list` / 顶层 `info` 之间反复横跳，
/// 每种形状都得有人守。
void main() {
  group('extractPlaylistTagGroups', () {
    test('二级分组：tag_name + son[]', () {
      final groups = extractPlaylistTagGroups({
        'data': {
          'info': [
            {
              'tag_name': '主题',
              'son': [
                {'tag_id': '1', 'tag_name': '热门'},
                {'tag_id': '2', 'tag_name': '伤感'},
              ],
            },
          ],
        },
      });

      expect(groups.length, 1);
      expect(groups.single.name, '主题');
      expect(groups.single.child.length, 2);
      expect(groups.single.child.first.id, '1');
      expect(groups.single.child.first.name, '热门');
      // 子标签回填所属组名（UI 用它做分组标题）。
      expect(groups.single.child.first.group, '主题');
    });

    test('child / list 别名都能当子数组', () {
      for (final key in const ['child', 'list']) {
        final groups = extractPlaylistTagGroups({
          'info': [
            {
              'name': 'G',
              key: [
                {'id': '9', 'name': 'N'},
              ],
            },
          ],
        });
        expect(groups.single.child.single.id, '9', reason: key);
      }
    });

    test('顶层 info 也能识别', () {
      final groups = extractPlaylistTagGroups({
        'info': [
          {
            'tag_name': 'G',
            'son': [
              {'tag_id': '1', 'tag_name': 'A'},
            ],
          },
        ],
      });
      expect(groups.single.name, 'G');
    });

    test('id 或 name 缺失的子标签被丢弃', () {
      final groups = extractPlaylistTagGroups({
        'data': {
          'info': [
            {
              'tag_name': 'G',
              'son': [
                {'tag_id': '1'}, // 缺 name
                {'tag_name': 'B'}, // 缺 id
                {'tag_id': '3', 'tag_name': 'C'},
              ],
            },
          ],
        },
      });
      expect(groups.single.child.length, 1);
      expect(groups.single.child.single.name, 'C');
    });

    test('整组子标签全非法 → 该组被丢弃', () {
      final groups = extractPlaylistTagGroups({
        'data': {
          'info': [
            {
              'tag_name': 'G',
              'son': [
                {'tag_id': '1'},
              ],
            },
          ],
        },
      });
      expect(groups, isEmpty);
    });

    test('非 Map / 无 list → 空列表，不抛', () {
      expect(extractPlaylistTagGroups(null), isEmpty);
      expect(extractPlaylistTagGroups('string'), isEmpty);
      expect(extractPlaylistTagGroups({'data': 'nope'}), isEmpty);
      expect(extractPlaylistTagGroups({'data': {'info': 'nope'}}), isEmpty);
    });
  });

  group('extractAlbumsByType', () {
    Map<String, dynamic> album(String id) => {
          'album_id': id,
          'albumname': '专辑$id',
        };

    test('type=all 把四个地区桶拼起来', () {
      final body = {
        'data': {
          'chn': [album('c1')],
          'eur': [album('e1')],
          'jpn': [album('j1')],
          'kor': [album('k1')],
        },
      };
      final albums = extractAlbumsByType(body);
      expect(albums.map((a) => a.id), ['c1', 'e1', 'j1', 'k1']);
    });

    test('指定 type 只取该地区桶', () {
      final body = {
        'data': {
          'chn': [album('c1'), album('c2')],
          'eur': [album('e1')],
        },
      };
      expect(
        extractAlbumsByType(body, type: 'chn').map((a) => a.id),
        ['c1', 'c2'],
      );
      expect(
        extractAlbumsByType(body, type: 'eur').map((a) => a.id),
        ['e1'],
      );
    });

    test('指定 type 为空串时按 all 处理', () {
      final body = {
        'data': {'chn': [album('c1')], 'kor': [album('k1')]},
      };
      expect(extractAlbumsByType(body, type: '').length, 2);
    });

    test('跨桶重复的专辑按 id 去重', () {
      final body = {
        'data': {
          'chn': [album('dup'), album('c1')],
          'eur': [album('dup')],
        },
      };
      expect(extractAlbumsByType(body).map((a) => a.id), ['dup', 'c1']);
    });

    test('缺 id 的条目被丢弃', () {
      final body = {
        'data': {
          'chn': [
            {'albumname': '没有 id'},
            album('ok'),
          ],
        },
      };
      expect(extractAlbumsByType(body).map((a) => a.id), ['ok']);
    });

    test('非 Map / 无数据 → 空列表', () {
      expect(extractAlbumsByType(null), isEmpty);
      expect(extractAlbumsByType({'data': 1}), isEmpty);
    });
  });

  group('extractDiscoveryArtists', () {
    test('扁平 info[] 直接映射', () {
      final artists = extractDiscoveryArtists({
        'data': {
          'info': [
            {'singerid': '1', 'singername': '周杰伦', 'song_count': 300},
          ],
        },
      });
      expect(artists.length, 1);
      expect(artists.single.id, '1');
      expect(artists.single.name, '周杰伦');
      expect(artists.single.songCount, 300);
    });

    test('分组形状：info[].singer[]，组名作 letter', () {
      final artists = extractDiscoveryArtists({
        'data': {
          'info': [
            {
              'title': 'Z',
              'singer': [
                {'singerid': '1', 'singername': '张三'},
                {'singerid': '2', 'singername': '李四'},
              ],
            },
          ],
        },
      });
      expect(artists.map((a) => a.name), ['张三', '李四']);
      expect(artists.every((a) => a.letter == 'Z'), isTrue);
    });

    test('跨组重复歌手按 id 去重', () {
      final artists = extractDiscoveryArtists({
        'data': {
          'info': [
            {
              'title': 'A',
              'singer': [
                {'singerid': '1', 'singername': '同名'},
              ],
            },
            {
              'title': 'B',
              'singer': [
                {'singerid': '1', 'singername': '同名'},
                {'singerid': '2', 'singername': '别的'},
              ],
            },
          ],
        },
      });
      expect(artists.map((a) => a.id), ['1', '2']);
    });

    test('singer_id / name 等别名也能取到', () {
      final artists = extractDiscoveryArtists({
        'info': [
          {'singer_id': '7', 'name': '别名歌手'},
        ],
      });
      expect(artists.single.id, '7');
      expect(artists.single.name, '别名歌手');
    });

    test('缺 id 的条目被丢弃', () {
      final artists = extractDiscoveryArtists({
        'info': [
          {'singername': '没有 id'},
          {'singerid': '1', 'singername': '有 id'},
        ],
      });
      expect(artists.map((a) => a.name), ['有 id']);
    });

    test('头像缺失时用 id 兜底，不返回空串', () {
      final artists = extractDiscoveryArtists({
        'info': [
          {'singerid': '55', 'singername': '无头像'},
        ],
      });
      expect(artists.single.avatarUrl, isNotEmpty);
    });

    test('非 Map / 无数据 → 空列表', () {
      expect(extractDiscoveryArtists(null), isEmpty);
      expect(extractDiscoveryArtists(42), isEmpty);
    });
  });

  group('extractListTotal', () {
    test('顶层 total 优先', () {
      expect(extractListTotal({'total': 100, 'data': {'total': 5}}), 100);
    });

    test('退回 data.total', () {
      expect(extractListTotal({'data': {'total': 42}}), 42);
    });

    test('再退回 data.count', () {
      expect(extractListTotal({'data': {'count': 7}}), 7);
    });

    test('都没有 → 0', () {
      expect(extractListTotal({}), 0);
      expect(extractListTotal(null), 0);
      expect(extractListTotal({'data': 'x'}), 0);
    });
  });
}
