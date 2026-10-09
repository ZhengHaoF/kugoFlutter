import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';

/// 睡眠定时（`player_controller.setSleepTimer`，此前零测试）。
///
/// 行为契约：`minutes <= 0` 取消；到点只在**正在播放**时暂停；重新设定会
/// 取消上一个定时器（否则旧定时器仍会到点，把用户新设的时长作废）。
///
/// 注意：demo 曲会起一个 400ms 的周期 ticker，而 widget test 在**用例体结束
/// 时**就校验「没有 pending timer」（早于 addTearDown）。所以每个用例末尾
/// 必须显式 `container.dispose()`（`ref.onDispose` 里才会 cancel 它）。
Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 10000,
    );

Future<(ProviderContainer, PlayerController)> _playing() async {
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: FakeAudioPlayer()),
      ),
    ],
  );
  final ctrl = container.read(playerControllerProvider.notifier);
  // demo 曲（mock:// 封面 + 无 hash）不 resolve，直接起播。
  await ctrl.playQueue([_t('a')]);
  return (container, ctrl);
}

void main() {
  testWidgets('未设定时剩余分钟为 0', (tester) async {
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: FakeAudioPlayer()),
        ),
      ],
    );
    expect(
      container.read(playerControllerProvider.notifier).sleepRemainingMinutes,
      0,
    );
    container.dispose();
  });

  testWidgets('设定 30 分钟 → 剩余 30 分钟', (tester) async {
    final (container, ctrl) = await _playing();
    ctrl.setSleepTimer(30);
    expect(ctrl.sleepRemainingMinutes, 30);
    container.dispose();
  });

  testWidgets('minutes <= 0 取消定时，剩余回 0', (tester) async {
    final (container, ctrl) = await _playing();

    ctrl.setSleepTimer(30);
    expect(ctrl.sleepRemainingMinutes, 30);

    ctrl.setSleepTimer(0);
    expect(ctrl.sleepRemainingMinutes, 0);

    // 负数同样当取消处理。
    ctrl.setSleepTimer(30);
    ctrl.setSleepTimer(-5);
    expect(ctrl.sleepRemainingMinutes, 0);
    container.dispose();
  });

  testWidgets('取消后原定时器不再触发（不会误暂停）', (tester) async {
    final (container, ctrl) = await _playing();

    ctrl.setSleepTimer(30);
    ctrl.setSleepTimer(0);

    await tester.pump(const Duration(minutes: 31));
    await tester.pump();

    expect(container.read(playerControllerProvider).isPlaying, isTrue);
    container.dispose();
  });

  testWidgets('到点且正在播放 → 自动暂停，剩余清零', (tester) async {
    final (container, ctrl) = await _playing();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    ctrl.setSleepTimer(30);
    await tester.pump(const Duration(minutes: 30));
    await tester.pump();

    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    expect(ctrl.sleepRemainingMinutes, 0);
    container.dispose();
  });

  testWidgets('暂停中到点 → 不改变播放态', (tester) async {
    final (container, ctrl) = await _playing();
    ctrl.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);

    ctrl.setSleepTimer(30);
    await tester.pump(const Duration(minutes: 30));
    await tester.pump();

    // 已经是暂停态，不该被再切回播放。
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    expect(ctrl.sleepRemainingMinutes, 0);
    container.dispose();
  });

  testWidgets('重新设定会作废上一个定时器', (tester) async {
    final (container, ctrl) = await _playing();

    ctrl.setSleepTimer(30);
    // 改成 5 分钟：旧的 30 分钟定时器必须被取消。
    ctrl.setSleepTimer(5);

    // 走过 5 分钟 → 新定时器到点，暂停。
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    container.dispose();
  });

  testWidgets('剩余分钟向上取整', (tester) async {
    final (container, ctrl) = await _playing();
    ctrl.setSleepTimer(1);
    // 走过 30 秒：还剩 30 秒，ceil 后报 1 分钟。
    await tester.pump(const Duration(seconds: 30));
    expect(ctrl.sleepRemainingMinutes, 1);
    container.dispose();
  });
}
