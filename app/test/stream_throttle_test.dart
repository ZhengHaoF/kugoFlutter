import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/utils/stream_throttle.dart';

void main() {
  test('leading edge is delivered immediately', () async {
    final input = StreamController<int>();
    final out = <int>[];
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 100),
    ).listen(out.add);

    input.add(1);
    await Future<void>.delayed(Duration.zero);
    // 首个样本立刻放行——否则 seek / 起播后的进度条会先卡住一个窗口。
    expect(out, [1]);

    input.add(2);
    input.add(3);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    // 窗口内的连续样本只保留最新值，且必须被 flush 出来（不能丢）。
    expect(out, [1, 3]);

    await sub.cancel();
    await input.close();
  });

  test('sustained high-frequency input is collapsed to the interval', () async {
    final input = StreamController<int>();
    final out = <int>[];
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 50),
    ).listen(out.add);

    // 模拟 libmpv：每 5ms 一个样本，持续 200ms（约 40 个样本）。
    for (var i = 0; i < 40; i++) {
      input.add(i);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(out.length, lessThan(10), reason: '应被折叠到 50ms 窗口量级');
    expect(out.length, greaterThan(1), reason: '不能退化成全程只发一次');
    // 顺序单调、无重复回退。
    for (var i = 1; i < out.length; i++) {
      expect(out[i], greaterThan(out[i - 1]));
    }

    await sub.cancel();
    await input.close();
  });

  test('newest value always reaches the listener across windows', () async {
    final input = StreamController<int>();
    final out = <int>[];
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 50),
    ).listen(out.add);

    input.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    input.add(2);
    // 等窗口 flush 出来。
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(out, [1, 2]);

    input.add(3);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 进度游标不能落后于真实播放位置。
    expect(out.last, 3);
    for (var i = 1; i < out.length; i++) {
      expect(out[i], greaterThan(out[i - 1]));
    }

    await sub.cancel();
    await input.close();
  });

  test('closing the source flushes and closes the output', () async {
    final input = StreamController<int>();
    final out = <int>[];
    var done = false;
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 100),
    ).listen(out.add, onDone: () => done = true);

    input.add(1);
    input.add(2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await input.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(out, [1, 2]);
    expect(done, isTrue);

    await sub.cancel();
  });

  test('cancelling does not leave the source paused or throwing', () async {
    final input = StreamController<int>();
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 50),
    ).listen((_) {});

    input.add(1);
    await sub.cancel();
    // 取消后再来的样本不应抛（controller 已无人监听）。
    expect(() => input.add(2), returnsNormally);
    await input.close();
  });

  test('errors from the source are forwarded', () async {
    final input = StreamController<int>();
    Object? seen;
    final sub = throttleStream(
      input.stream,
      const Duration(milliseconds: 50),
    ).listen((_) {}, onError: (Object e) => seen = e);

    input.addError(StateError('boom'));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isA<StateError>());

    await sub.cancel();
    await input.close();
  });
}
