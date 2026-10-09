import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/bili/bili_sign.dart';

/// WBI 签名单测。黄金向量由 PowerShell 独立实现同算法算得（互不依赖的
/// 两个实现互证）；imgKey/subKey 取 bilibili-API-collect 公示样例键，
/// 其 mixinKey `ea1db124…` 与官方文档一致。
void main() {
  group('MIXIN_INDEX', () {
    test('是 0..63 的一个排列（64 位）', () {
      expect(BiliSign.mixinIndex.length, 64);
      final sorted = [...BiliSign.mixinIndex]..sort();
      expect(sorted, List.generate(64, (i) => i));
    });
  });

  group('mixinKey', () {
    const imgKey = '7cd084941338484aae1ad9425b84077c';
    const subKey = '4932caff0ff746eab6f01bf08b70ac45';
    const expected = 'ea1db124af3c7062474693fa704f4ff8';

    test('已知向量：imgKey+subKey → mixinKey（32 位）', () {
      expect(BiliSign.mixinKeyFromKeys(imgKey, subKey), expected);
    });

    test('从 nav 的 img_url/sub_url 取文件名主体', () {
      expect(
        BiliSign.mixinKeyFromUrls(
          'https://i0.hdslb.com/bfs/wbi/$imgKey.png',
          'https://i0.hdslb.com/bfs/wbi/$subKey.png',
        ),
        expected,
      );
    });

    test('空 URL 抛 ArgumentError', () {
      expect(() => BiliSign.mixinKeyFromUrls('', subKey), throwsArgumentError);
      expect(() => BiliSign.mixinKeyFromUrls(imgUrl(), ''), throwsArgumentError);
    });
  });

  group('wrid', () {
    const mixinKey = 'ea1db124af3c7062474693fa704f4ff8';

    test('已知向量：固定 wts + 中文关键词', () {
      // PowerShell 独立实现算得：
      //   query=duration=0&keyword=%E5%91%A8%E6%9D%B0%E4%BC%A6&order=totalrank
      //         &page=1&search_type=video&wts=1700000000
      //   w_rid=md5(query+mixinKey)
      expect(
        BiliSign.wrid(
          const {
            'keyword': '周杰伦',
            'search_type': 'video',
            'order': 'totalrank',
            'duration': '0',
            'page': '1',
          },
          mixinKey,
          wts: 1700000000,
        ),
        '5da14eea85560aee2cc98518ab029718',
      );
    });

    test('值里的 !\'()* 先过滤再签（与已过滤值等价）', () {
      final withJunk = BiliSign.wrid(const {'a': "x!'()*y"}, 'k', wts: 1);
      final clean = BiliSign.wrid(const {'a': 'xy'}, 'k', wts: 1);
      expect(withJunk, clean);
    });

    test('key 不过滤（只过滤值）', () {
      // key 含 * 时不被删掉：{'a*': 'v'} 与 {'a': 'v'} 签名结果不同，
      // 说明 'a*' 这个 key 原样进入了预映像。
      final withStar = BiliSign.wrid(const {'a*': 'v'}, 'k', wts: 1);
      final withoutStar = BiliSign.wrid(const {'a': 'v'}, 'k', wts: 1);
      expect(withStar, isNot(withoutStar));
      expect(withStar, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('同 wts 稳定；参数 / mixinKey 变则变', () {
      final a = BiliSign.wrid(const {'a': '1'}, 'k', wts: 100);
      final b = BiliSign.wrid(const {'a': '1'}, 'k', wts: 100);
      final c = BiliSign.wrid(const {'a': '2'}, 'k', wts: 100);
      final d = BiliSign.wrid(const {'a': '1'}, 'k2', wts: 100);
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('输出 32 位小写 hex', () {
      expect(
        BiliSign.wrid(const {'keyword': 'test'}, mixinKey, wts: 1),
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
    });
  });

  group('encodeUriComponent', () {
    test('unreserved 不编码；空格是 %20 不是 +', () {
      expect(BiliSign.encodeUriComponent("a b!*'()~-._"), "a%20b!*'()~-._");
    });

    test('中文按 UTF-8 百分号编码（大写 hex）', () {
      expect(BiliSign.encodeUriComponent('周'), '%E5%91%A8');
    });

    test('& = # ? / 均编码', () {
      expect(BiliSign.encodeUriComponent('a&b=c#d?e/f'), 'a%26b%3Dc%23d%3Fe%2Ff');
    });
  });

  group('hmacSha256Hex', () {
    test('WebTicket 已知向量', () {
      // PowerShell: HMAC-SHA256("ts1700000000", key="XgwSnGZ1p")
      expect(
        BiliSign.hmacSha256Hex('ts1700000000'),
        'bb79f0d980ffbb51597aa1a3e8b55603025cc1322ac766f4c1a98852e6182514',
      );
    });
  });
}

String imgUrl() => 'https://i0.hdslb.com/bfs/wbi/x.png';
