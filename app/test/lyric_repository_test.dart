import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/lyric_repository.dart';

import 'fakes/fake_kugo_client.dart';

Track _track({String hash = 'ABCDEF1234567890'}) => Track(
      id: 't1',
      name: '稻香',
      artist: '周杰伦',
      album: '魔杰座',
      coverUrl: '',
      durationMs: 223000,
      hash: hash,
    );

/// 歌词仓库：先搜候选 → 逐条试 KRC → 全失败再逐条试 LRC。
///
/// 两个坑都有回归价值：
///  - 上游把 JSON 用 `Content-Type: text/html` 下发，`getText` 拿到的是
///    String，`_extractKrcText` / `_extractLrcText` 得能从 JSON 包裹里掏出
///    base64 content；
///  - 候选列表最多取 3 条，且 KRC 全部失败才整体退回 LRC（不是每条各自回退）。
void main() {
  /// 搜索响应：三个候选。
  String searchHit() =>
      'id:"111",accesskey:"AABB" id:"222",accesskey:"CCDD" '
      'id:"333",accesskey:"EEFF"';

  group('候选解析', () {
    test('宽松正则从非 JSON 文本抓 id + accesskey，最多 3 条', () async {
      final fmts = <String>[];
      final client = FakeKugoClient(onText: (url) {
        if (url.contains('/download')) {
          fmts.add(Uri.decodeComponent(url).contains('fmt=krc') ? 'krc' : 'lrc');
          return null; // 下载全失败
        }
        return searchHit();
      });

      expect(await LyricRepository(client: client).fetchLyrics(_track()), isEmpty);
      // 4 个候选被截到 3 个；先 3 次 KRC，再 3 次 LRC。
      expect(fmts, ['krc', 'krc', 'krc', 'lrc', 'lrc', 'lrc']);
    });

    test('宽松正则抓不到 accesskey 时退回只取 id', () async {
      final client = FakeKugoClient(onText: (url) {
        if (url.contains('/download')) return null;
        return 'id:"12345678" id:"87654321"';
      });

      await LyricRepository(client: client).fetchLyrics(_track());
      expect(client.textCalls.any((u) => u.contains('id=12345678')), isTrue);
      expect(client.textCalls.any((u) => u.contains('id=87654321')), isTrue);
    });

    test('搜索本身抛错 → 一次下载都不发起', () async {
      final client = FakeKugoClient(onText: null);
      expect(await LyricRepository(client: client).fetchLyrics(_track()), isEmpty);
      expect(client.textCalls.length, 1);
    });

    test('候选为空 → 只有搜索那一次请求', () async {
      final client = FakeKugoClient(onText: (_) => 'no candidates here');
      expect(await LyricRepository(client: client).fetchLyrics(_track()), isEmpty);
      expect(client.textCalls.length, 1);
    });

    test('下载 URL 带上 id / accesskey / charset', () async {
      final client = FakeKugoClient(onText: (url) {
        if (url.contains('/download')) return null;
        return 'id:"111",accesskey:"AABB"';
      });
      await LyricRepository(client: client).fetchLyrics(_track());

      final dl = client.textCalls.firstWhere((u) => u.contains('/download'));
      final decoded = Uri.decodeComponent(dl);
      expect(decoded, contains('id=111'));
      expect(decoded, contains('accesskey=AABB'));
      expect(decoded, contains('charset=utf8'));
    });
  });

  group('搜索关键词与 hash', () {
    test('关键词是「歌手 歌名」，hash 转小写，timelength 带时长', () async {
      String? searched;
      final client = FakeKugoClient(onText: (url) {
        searched ??= url;
        return 'nothing';
      });

      await LyricRepository(client: client)
          .fetchLyrics(_track(hash: 'AABBCCDD'));

      final decoded = Uri.decodeComponent(searched!);
      expect(decoded, contains('keyword'));
      expect(decoded, contains('周杰伦'));
      expect(decoded, contains('稻香'));
      expect(decoded, contains('aabbccdd'));
      expect(decoded, contains('223000'));
    });
  });

  group('LRC 正文提取', () {
    // _extractLrcText 私有，这里通过「候选 + LRC 内容」走完整下载路径触发它。
    Future<List<LyricLine>> lrcFrom(String body) async {
      final client = FakeKugoClient(onText: (url) {
        if (url.contains('/download')) return body;
        return 'id:"111",accesskey:"AABB"';
      });
      return LyricRepository(client: client).fetchLyrics(_track());
    }

    test('JSON 包裹的 base64 content 被解出来', () async {
      final lrc = '[00:01.00]第一行\n[00:02.00]第二行';
      final lines = await lrcFrom(
        jsonEncode({'content': base64.encode(utf8.encode(lrc))}),
      );
      expect(lines.length, 2);
      expect(lines.first.text, '第一行');
      expect(lines.last.text, '第二行');
    });

    test('base64 content 不是合法 base64 时退回原文', () async {
      // content 直接当歌词文本用；但它没有时间戳，解析不出行。
      final lines = await lrcFrom(jsonEncode({'content': '没有时间戳的纯文本'}));
      expect(lines, isEmpty);
    });

    test('裸 LRC 文本原样使用', () async {
      final lines = await lrcFrom('[ti:稻香]\n[00:01.00]第一行');
      expect(lines.length, 1);
      expect(lines.first.text, '第一行');
    });

    test('无 JSON 包裹的 base64 串也能解', () async {
      final lrc = '[00:01.00]第一行';
      final lines = await lrcFrom(base64.encode(utf8.encode(lrc)));
      expect(lines.length, 1);
      expect(lines.first.text, '第一行');
    });

    test('既不是 LRC 也不是 base64 → 解析不出行', () async {
      final lines = await lrcFrom('随便一段没有时间戳的文字');
      expect(lines, isEmpty);
    });
  });
}
