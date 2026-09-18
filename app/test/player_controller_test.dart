import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';

Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 10000,
    );

ProviderContainer _containerWithFake() {
  final engine = FakeAudioPlayer();
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(() => PlayerController(engine: engine)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('queue advance and wrap by listLoop', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a'), _t('b')], startIndex: 0);
    expect(container.read(playerControllerProvider).current?.id, 'a');

    await controller.next();
    expect(container.read(playerControllerProvider).current?.id, 'b');

    await controller.next();
    expect(container.read(playerControllerProvider).current?.id, 'a');
  });

  test('seek clamps to duration', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.seekTo(999999);
    expect(container.read(playerControllerProvider).positionMs, 10000);

    controller.seekTo(-100);
    expect(container.read(playerControllerProvider).positionMs, 0);
  });

  test('toggle play pauses timer state', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
  });

  test('engine playing=true updates display (no stuck loading)', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).display,
        PlayerDisplayState.paused);

    await engine.play();
    expect(container.read(playerControllerProvider).display,
        PlayerDisplayState.playing);
    expect(container.read(playerControllerProvider).isLoading, isFalse);
  });

  test('demo track toggle after pause resumes without resolve', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);
  });
}
