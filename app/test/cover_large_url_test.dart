/// `coverLargeUrl`：各源封面大图变体的 URL 变换。
///
/// 口径来自 `tool/probe_cover_size.dart` 实测（2026-10-10）：酷狗
/// `stdmusic/{size}/` 路径段就是尺寸旋钮、网易云 `param=` 可替换（原图
/// 不够大时服务端自行截断）、B 站封面本身已是 800×450~2560×1440。
/// 大图拉不到时查看器回退原图，所以这里的变换全部是「尽力而为」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/api/mappers.dart';

void main() {
  group('酷狗：stdmusic 尺寸段', () {
    test('400 → 1080，其余路径不动', () {
      expect(
        coverLargeUrl(
          'https://imge.kugou.com/stdmusic/400/20230920/20230920142503632013.jpg',
        ),
        'https://imge.kugou.com/stdmusic/1080/20230920/20230920142503632013.jpg',
      );
    });

    test('已是 1080 不再放大', () {
      const url = 'https://imge.kugou.com/stdmusic/1080/x/y.jpg';
      expect(coverLargeUrl(url), url);
    });

    test('soft/collection 等其他路径不碰（未实测，不回退猜测）', () {
      const url = 'https://imge.kugou.com/soft/collection/400/abc';
      expect(coverLargeUrl(url), url);
    });
  });

  group('网易云：param 替换', () {
    test('param=300y300 → w2000y2000', () {
      expect(
        coverLargeUrl(
          'https://p3.music.126.net/yD9vbpuILH-tqNRIaP640g==/109951163038292176.jpg?param=300y300',
        ),
        'https://p3.music.126.net/yD9vbpuILH-tqNRIaP640g==/109951163038292176.jpg?param=w2000y2000',
      );
    });

    test('无 param 时追加', () {
      expect(
        coverLargeUrl('https://p3.music.126.net/x/y.jpg'),
        'https://p3.music.126.net/x/y.jpg?param=w2000y2000',
      );
    });

    test('已有其他 query 时用 & 拼', () {
      expect(
        coverLargeUrl('https://p3.music.126.net/x/y.jpg?foo=1'),
        'https://p3.music.126.net/x/y.jpg?foo=1&param=w2000y2000',
      );
    });
  });

  group('其余原样返回', () {
    test('B 站视频封面本身就是大图', () {
      const url = 'https://i0.hdslb.com/bfs/archive/3acdced5.jpg';
      expect(coverLargeUrl(url), url);
    });

    test('空串 / 非 http 不动', () {
      expect(coverLargeUrl(''), '');
      expect(coverLargeUrl('   '), '');
      expect(coverLargeUrl('mock://a'), 'mock://a');
      expect(coverLargeUrl('barehash'), 'barehash');
    });
  });
}
