import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/api/bili/bili_mappers.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/source/music_platform.dart';

/// B 站 mapper 单测：固定 JSON fixture，不联外网（方案 §10）。
void main() {
  group('biliStripHtml / biliParseDurationSeconds', () {
    test('剥 <em class="keyword"> 高亮 + HTML 实体解码', () {
      expect(
        biliStripHtml('【<em class="keyword">周杰伦</em>】晴天 &amp; 花海'),
        '【周杰伦】晴天 & 花海',
      );
    });

    test('多段高亮 + 数字/十六进制实体', () {
      expect(
        biliStripHtml(
          '<em class="keyword">官方</em>MV <em class="keyword">周杰伦</em>'
          '&#39;demo&#39; &#x41;&#66;',
        ),
        "官方MV 周杰伦'demo' AB",
      );
    });

    test('无标签原样返回（trim）', () {
      expect(biliStripHtml('  普通标题  '), '普通标题');
    });

    test('时长 mm:ss / h:mm:ss / ss / 脏值', () {
      expect(biliParseDurationSeconds('04:35'), 275);
      expect(biliParseDurationSeconds('1:02:03'), 3723);
      expect(biliParseDurationSeconds('45'), 45);
      expect(biliParseDurationSeconds(''), 0);
      expect(biliParseDurationSeconds('ab:cd'), 0);
    });
  });

  group('BiliMappers.mapSearchPage', () {
    BiliVideoItem item({
      required String bvid,
      required String duration,
      String title = '测试标题',
      int mid = 42,
    }) =>
        BiliVideoItem.fromJson({
          'type': 'video',
          'bvid': bvid,
          'aid': 111,
          'title': title,
          'author': '测试UP主',
          'mid': mid,
          'pic': '//i0.hdslb.com/bfs/archive/aaa.jpg',
          'duration': duration,
          'play': 1234,
          'pubdate': 1700000000,
        });

    test('字段映射：裸 bvid 身份 / 剥壳标题 / UP 主 / 封面补 https', () {
      final page = BiliVideoPage(
        items: [
          item(
            bvid: 'BV1songA',
            duration: '04:35',
            title: '【<em class="keyword">周杰伦</em>】晴天 &amp; 花海',
          ),
        ],
        numResults: 1000,
        numPages: 50,
        page: 1,
      );

      final result = BiliMappers.mapSearchPage(page);
      expect(result.items, hasLength(1));
      expect(result.total, 1000);

      final t = result.items.first;
      expect(t.platform, MusicPlatform.bili);
      expect(t.id, 'BV1songA'); // 搜索态 = 裸 bvid（§5.3 #5）
      expect(t.name, '【周杰伦】晴天 & 花海');
      expect(t.artist, '测试UP主');
      expect(t.coverUrl, 'https://i0.hdslb.com/bfs/archive/aaa.jpg');
      expect(t.durationMs, 275000);
      expect(t.artistId, '42');
      expect(t.identityKey, 'bili:BV1songA');
    });

    test('> 15 min 长视频被过滤（§5.3 #8，阈值 B2 定案）', () {
      final page = BiliVideoPage(
        items: [
          item(bvid: 'BV1ok', duration: '14:59'),
          item(bvid: 'BV1edge', duration: '15:00'), // 边界：等于阈值保留
          item(bvid: 'BV1long', duration: '40:00'),
          item(bvid: 'BV1compilation', duration: '222:28'),
        ],
        numResults: 4,
        numPages: 1,
        page: 1,
      );

      final result = BiliMappers.mapSearchPage(page);
      expect(result.items.map((t) => t.id), ['BV1ok', 'BV1edge']);
    });

    test('mid=0 → artistId 空串（未知不跳转）', () {
      final page = BiliVideoPage(
        items: [item(bvid: 'BV1x', duration: '03:00', mid: 0)],
        numResults: 1,
        numPages: 1,
        page: 1,
      );
      expect(BiliMappers.mapSearchPage(page).items.first.artistId, '');
    });

    test('bvid 为空的条目丢弃', () {
      final page = BiliVideoPage(
        items: [
          BiliVideoItem.fromJson({
            'type': 'video',
            'title': '无 bvid',
            'duration': '03:00',
          }),
        ],
        numResults: 1,
        numPages: 1,
        page: 1,
      );
      expect(BiliMappers.mapSearchPage(page).items, isEmpty);
    });
  });

  group('BiliMappers 档位阈值', () {
    test('maxSongDurationSec = 900', () {
      expect(BiliMappers.maxSongDurationSec, 15 * 60);
      expect(AppQuality.values, hasLength(4)); // 契约未变的守卫
    });
  });
}
