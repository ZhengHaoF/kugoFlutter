import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

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

    controller.seekTo(3000);
    expect(container.read(playerControllerProvider).positionMs, 3000);

    await controller.next();
    final afterNext = container.read(playerControllerProvider);
    expect(afterNext.current?.id, 'b');
    expect(afterNext.positionMs, 0);

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

  test('user pause wins over late engine playing=true', () async {
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

    // Late engine event must not flip the icon against explicit pause.
    await engine.play();
    expect(container.read(playerControllerProvider).display,
        PlayerDisplayState.paused);
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
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

  test('hash track fails resolve cleanly without inventing play', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource()
      ..nextPlayUrl = null
      ..playError = const NotFound('offline');
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine, source: source),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    final hashed = Track(
      id: 'h1',
      name: 'h1',
      artist: 'a',
      album: 'b',
      coverUrl: 'https://example.com/h1.jpg',
      durationMs: 10000,
      hash: 'hash_h1',
    );
    await controller.playQueue([hashed]);
    final state = container.read(playerControllerProvider);
    // Offline / blocked network → error, must not fake-playing forever.
    expect(state.isPlaying, isFalse);
    expect(engine.lastUrl, isNull);
    expect(
      state.display == PlayerDisplayState.error ||
          state.display == PlayerDisplayState.loading,
      isTrue,
    );
  });
}
