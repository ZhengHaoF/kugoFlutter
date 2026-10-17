import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/source/music_platform.dart';
import 'package:overtone/core/source/music_source.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/player/stall_watchdog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'fixture',
  album: 'fixture',
  coverUrl: 'https://example.invalid/$id.jpg',
  durationMs: 180000,
  hash: 'hash-$id',
  mixSongId: '123456',
  platform: MusicPlatform.kugou,
);

/// 10ms 采样 / 30ms 阈值：真实时间几十毫秒即可判定，测试不必等 8 秒。
StallWatchdog _fastWatchdog() => StallWatchdog(
  tick: const Duration(milliseconds: 10),
  stallTimeout: const Duration(milliseconds: 30),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StallWatchdog', () {
    test('active=false 永不判定（暂停/加载中/曲末）', () {
      final w = _fastWatchdog();
      for (var i = 0; i < 10; i++) {
        expect(w.onTick(1000, active: false), isFalse);
      }
    });

    test('游标推进就不算停滞', () {
      final w = _fastWatchdog();
      for (var i = 0; i < 10; i++) {
        expect(w.onTick(1000 + i, active: true), isFalse);
      }
    });

    test('游标不动累计到阈值触发一次，随后重新累计', () {
      final w = _fastWatchdog();
      expect(w.onTick(0, active: true), isFalse); // 首拍只记录
      expect(w.onTick(0, active: true), isFalse); // +10ms
      expect(w.onTick(0, active: true), isFalse); // +20ms
      expect(w.onTick(0, active: true), isTrue); // +30ms → 触发
      // 触发不清除游标，只把「无进展」计时归零。
      expect(w.onTick(0, active: true), isFalse); // +10ms
      expect(w.onTick(0, active: true), isFalse); // +20ms
      expect(w.onTick(0, active: true), isTrue); // +30ms → 再触发
    });

    test('中途 active=false 会重置无进展计时', () {
      final w = _fastWatchdog();
      w.onTick(0, active: true);
      w.onTick(0, active: true); // +10ms
      w.onTick(0, active: false); // 重置
      expect(w.onTick(0, active: true), isFalse);
      expect(w.onTick(0, active: true), isFalse); // +10ms
      expect(w.onTick(0, active: true), isTrue); // +30ms
    });

    test('reset 之后从头计时', () {
      final w = _fastWatchdog();
      w.onTick(0, active: true);
      w.onTick(0, active: true);
      w.reset();
      // reset 同时清掉游标，所以要多一拍「记录」。
      expect(w.onTick(0, active: true), isFalse);
      expect(w.onTick(0, active: true), isFalse); // +10ms
      expect(w.onTick(0, active: true), isFalse); // +20ms
      expect(w.onTick(0, active: true), isTrue); // +30ms
    });
  });

  group('播放停滞自愈', () {
    late FakeMusicSource source;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      source = FakeMusicSource()
        ..nextPlayUrl = const PlayUrlResult(url: 'https://example.com/a.mp3');
    });

    ProviderContainer container(
      FakeAudioPlayer engine, {
      StallWatchdog? watchdog,
    }) {
      final c = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(
              engine: engine,
              source: source,
              stallWatchdog: watchdog ?? _fastWatchdog(),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> play(WidgetTester tester, ProviderContainer c) async {
      final p = c.read(playerControllerProvider.notifier);
      await tester.runAsync(() => p.playQueue([_track('A')]));
      await tester.pump();
    }

    /// 让真实时间流过 [ms]（看门狗用的是真实定时器）。
    Future<void> waitMs(WidgetTester tester, int ms) async {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)),
      );
      await tester.pump();
    }

    testWidgets('游标不推进 → 重新取流续播，且不跳曲', (tester) async {
      final engine = FakeAudioPlayer();
      final c = container(engine);

      await play(tester, c);
      expect(engine.playUrlCalls, 1);

      // 引擎一直不吐新位置（模拟卡死）：只有首拍记录，之后持续无进展。
      await waitMs(tester, 200);

      expect(engine.playUrlCalls, greaterThan(1));
      final state = c.read(playerControllerProvider);
      expect(state.current?.id, 'A');
    });

    testWidgets('反复停滞超过上限后交回失败链路', (tester) async {
      final engine = FakeAudioPlayer();
      final c = container(engine);

      await play(tester, c);
      await waitMs(tester, 3000);

      final state = c.read(playerControllerProvider);
      expect(state.display, PlayerDisplayState.error);
      expect(state.errorCode, contains('停滞'));
      // 首次加载 + 最多 3 次自愈，不能无限重试。
      expect(engine.playUrlCalls, lessThanOrEqualTo(4));
    });

    testWidgets('用户暂停时不触发自愈', (tester) async {
      final engine = FakeAudioPlayer();
      final c = container(engine);

      await play(tester, c);
      expect(engine.playUrlCalls, 1);

      c.read(playerControllerProvider.notifier).togglePlay();
      await tester.pump();
      await waitMs(tester, 200);

      expect(engine.playUrlCalls, 1);
      expect(c.read(playerControllerProvider).playingMvAudio, isFalse);
    });

    testWidgets('游标正常推进时不会自愈', (tester) async {
      final engine = FakeAudioPlayer();
      // 阈值放宽到 60ms，把「采样抖动」与「真停滞」拉开，避免用例本身不稳。
      final c = container(
        engine,
        watchdog: StallWatchdog(
          tick: const Duration(milliseconds: 10),
          stallTimeout: const Duration(milliseconds: 60),
        ),
      );

      await play(tester, c);

      // 每 15ms 推进一次游标，跑 180ms——一直在走，就不该被判为停滞。
      await tester.runAsync(() async {
        for (var i = 1; i <= 12; i++) {
          engine.emitPosition(Duration(milliseconds: i * 500));
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      });
      await tester.pump();

      expect(engine.playUrlCalls, 1);
      expect(
        c.read(playerControllerProvider).display,
        PlayerDisplayState.playing,
      );
    });
  });
}
