import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/features/player/shuffle_order.dart';

List<String> _items([int n = 8]) => List.generate(n, (i) => 'e$i');

void main() {
  group('shuffledQueue', () {
    test('returns a permutation and never mutates the input', () {
      final items = _items(20);
      final out = shuffledQueue(items, rng: Random(7));
      // 入参不动（调用方持有的是 state.queue 的引用）。
      expect(items, _items(20));
      expect(out, hasLength(20));
      expect(out.toSet(), items.toSet());
      // 固定种子下确实洗掉了原顺序。
      expect(out, isNot(equals(items)));
    });

    test('same seed reproduces the same permutation', () {
      final items = _items();
      expect(
        shuffledQueue(items, rng: Random(42)),
        shuffledQueue(items, rng: Random(42)),
      );
    });

    test('pinIndex keeps the slot and its element', () {
      final items = _items(6);
      for (var pin = 0; pin < 6; pin++) {
        final out = shuffledQueue(items, pinIndex: pin, rng: Random(pin + 1));
        expect(out[pin], items[pin]);
        expect(out.toSet(), items.toSet());
      }
      // 越界游标 clamp 到末槽，不炸。
      final clamped = shuffledQueue([1, 2], pinIndex: 9, rng: Random(1));
      expect(clamped, hasLength(2));
      expect(clamped[1], 2);
    });

    test('pinned permutation is unbiased across slots', () {
      // 回归锚点：「洗完整队再对调钉位」会把分布压偏（n=3 时 4:2）。
      // 摘出钉位元素再洗才能保证每个剩余元素在每个槽位等概。
      const n = 5;
      const pin = 2;
      final items = List.generate(n, (i) => 'e$i');
      const samples = 6000;
      final slotCounts = List.filled(n, 0);
      for (var s = 0; s < samples; s++) {
        final out = shuffledQueue(items, pinIndex: pin, rng: Random(s));
        slotCounts[out.indexOf('e0')] += 1;
      }
      for (var slot = 0; slot < n; slot++) {
        if (slot == pin) {
          expect(slotCounts[slot], 0);
        } else {
          // 期望 1500；±25% 带宽足以抓住 4:2 这类偏置，又不会误抖。
          expect(slotCounts[slot], inInclusiveRange(1125, 1875));
        }
      }
    });

    test('avoidFirst never lands at slot 0', () {
      final items = _items(10);
      for (var s = 0; s < 500; s++) {
        final out = shuffledQueue(items, avoidFirst: items[3], rng: Random(s));
        expect(out.first, isNot(items[3]));
        expect(out.toSet(), items.toSet());
      }
    });

    test('degenerate sizes return a plain copy', () {
      expect(shuffledQueue(<String>[], rng: Random(1)), isEmpty);
      expect(shuffledQueue(['only'], rng: Random(1)), ['only']);
      expect(shuffledQueue(['only'], pinIndex: 0, rng: Random(1)), ['only']);
      expect(shuffledQueue(['only'], avoidFirst: 'only', rng: Random(1)),
          ['only']);
    });

    test('debugShuffleRandom is honored when rng is omitted', () {
      final items = _items();
      debugShuffleRandom = Random(99);
      final first = shuffledQueue(items);
      final second = shuffledQueue(items);
      debugShuffleRandom = null;
      addTearDown(() => debugShuffleRandom = null);

      // 同一个注入实例被推进了，两次结果不同。
      expect(first, isNot(equals(second)));
      // 与外部 Random(99) 的首帧一致：注入点真的生效了。
      expect(first, shuffledQueue(items, rng: Random(99)));
    });
  });
}
