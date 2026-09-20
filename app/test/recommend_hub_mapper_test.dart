import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/mappers.dart';

void main() {
  group('extractStyleTagGroups', () {
    test('reads data.tag_info with child tags', () {
      final groups = extractStyleTagGroups({
        'status': 1,
        'data': {
          'tag_info': [
            {
              'name': '语种',
              'child': [
                {'id': '1', 'name': '华语', 'default': 1},
                {'id': '2', 'name': '欧美'},
              ],
            },
          ],
        },
      });
      expect(groups, hasLength(1));
      expect(groups.first.name, '语种');
      expect(groups.first.child, hasLength(2));
      expect(groups.first.child.first.isDefault, isTrue);
      expect(groups.first.child.last.isDefault, isFalse);
    });

    test('returns empty when tag_info missing', () {
      expect(extractStyleTagGroups({'data': {}}), isEmpty);
      expect(extractStyleTagGroups(null), isEmpty);
    });
  });

  group('mapRecommendPlaylist', () {
    test('prefers numeric specialid', () {
      final brief = mapRecommendPlaylist({
        'specialid': 888,
        'name': '精选歌单',
        'pic': 'abc',
        'songcount': 30,
        'playcount': 120000,
      });
      expect(brief.id, '888');
      expect(brief.name, '精选歌单');
      expect(brief.playCountLabel, '12.0万');
    });

    test('extracts special id from global_collection_id', () {
      final brief = mapRecommendPlaylist({
        'global_collection_id': 'collection_3_509005046_32_0',
        'name': 'IP 精选',
        'extra': {
          'global_collection_id': 'collection_3_509005046_32_0',
        },
      });
      expect(brief.id, '509005046');
      expect(brief.name, 'IP 精选');
    });

    test('parses ip_id from extra.inner_url', () {
      final brief = mapRecommendPlaylist({
        'name': '编辑精选',
        'type': 1,
        'extra': {
          'inner_url': 'https://example.com/?ip_id=4242&x=1',
        },
      });
      expect(brief.id, '4242');
    });
  });
}
