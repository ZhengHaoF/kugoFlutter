import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/audio_service_handler.dart';
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

void main() {
  test('system media pause/stop actually pause the player', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // Regression: pause() used to be a copy of play() and did nothing here.
    await handler.pause();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);

    await handler.play();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    await handler.stop();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
  });

  test('handler broadcasts duration, buffered position and seek action',
      () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    final state = handler.playbackState.value;
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.systemActions, contains(MediaAction.seek));
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 10));
    expect(
      () => state.position,
      returnsNormally,
      reason: 'handler must expose a monotonic media position',
    );
  });

  test('media position never goes backwards between pushes', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t(_songId)]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // Android's AVRCP target permanently stops emitting
    // EVENT_PLAYBACK_POS_CHANGED once two consecutive reads are equal, so every
    // position handed to the platform has to move strictly forward.
    await _exercisePositionPushes(engine, handler);
  });
}

const _songId = 'a';

/// Drive engine samples and timer pushes for a while, then assert the sequence
/// of positions handed to the platform was strictly increasing.
///
/// Android's AVRCP target permanently stops emitting
/// EVENT_PLAYBACK_POS_CHANGED once two consecutive reads return the same value,
/// so a position that stalls or steps backwards kills the car progress bar for
/// good. Asserting on the recorded sequence (rather than inside the listener)
/// keeps the failure message readable instead of retrying per event.
Future<void> _exercisePositionPushes(
  FakeAudioPlayer engine,
  KugoAudioHandler handler,
) async {
  final pushed = <int>[];
  final sub = handler.playbackState.listen(
    (state) => pushed.add(state.updatePosition.inMilliseconds),
  );
  addTearDown(sub.cancel);

  // ~4s of wall clock: long enough to cross several timer/stream mismatches.
  for (var tick = 0; tick < 40; tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    engine.emitPosition(Duration(milliseconds: tick * 100));
  }

  expect(pushed.length, greaterThan(1), reason: 'no position pushes recorded');
  for (var i = 1; i < pushed.length; i++) {
    if (pushed[i] <= pushed[i - 1]) {
      fail(
        'position stalled or went backwards at push #$i: '
        '${pushed[i - 1]}ms -> ${pushed[i]}ms\n'
        'full sequence: $pushed',
      );
    }
  }
}
