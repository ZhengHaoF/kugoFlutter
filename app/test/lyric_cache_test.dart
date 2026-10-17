import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/features/player/lyric_cache.dart';

List<LyricLine> _lines(String text) => [LyricLine(timeMs: 0, text: text)];

void main() {
  test('命中缓存后不再调用 loader', () async {
    final cache = LyricCache();
    var calls = 0;
    Future<List<LyricLine>> loader() async {
      calls++;
      return _lines('a');
    }

    final first = await cache.load('k', loader);
    final second = await cache.load('k', loader);

    expect(calls, 1);
    expect(first.single.text, 'a');
    expect(second.single.text, 'a');
    expect(cache.length, 1);
  });

  test('同一 key 的并发请求合并成一次', () async {
    final cache = LyricCache();
    var calls = 0;
    final gate = Completer<void>();
    Future<List<LyricLine>> loader() async {
      calls++;
      await gate.future;
      return _lines('a');
    }

    final first = cache.load('k', loader);
    final second = cache.load('k', loader);
    expect(cache.hasInflight, isTrue);

    gate.complete();
    final results = await Future.wait([first, second]);

    expect(calls, 1);
    expect(results.first.single.text, 'a');
    expect(results.last.single.text, 'a');
    expect(cache.hasInflight, isFalse);
  });

  test('超出容量淘汰最久未使用的条目', () async {
    final cache = LyricCache(capacity: 2);
    cache.put('a', _lines('a'));
    cache.put('b', _lines('b'));
    // 触碰 a：a 变成最近使用，b 成了最久未用。
    expect(cache.get('a'), isNotNull);

    cache.put('c', _lines('c'));

    expect(cache.get('b'), isNull);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('c'), isNotNull);
    expect(cache.length, 2);
  });

  test('空结果不入缓存（保留「每曲补试一次」的机会）', () async {
    final cache = LyricCache();
    var calls = 0;
    Future<List<LyricLine>> loader() async {
      calls++;
      return const [];
    }

    expect(await cache.load('k', loader), isEmpty);
    expect(await cache.load('k', loader), isEmpty);

    expect(calls, 2);
    expect(cache.length, 0);
  });

  test('失败不上抛后仍可重试，且不缓存错误', () async {
    final cache = LyricCache();
    var calls = 0;
    Future<List<LyricLine>> loader() async {
      calls++;
      if (calls == 1) throw StateError('boom');
      return _lines('a');
    }

    await expectLater(cache.load('k', loader), throwsStateError);
    expect(cache.hasInflight, isFalse);

    final lines = await cache.load('k', loader);
    expect(calls, 2);
    expect(lines.single.text, 'a');
  });
}
