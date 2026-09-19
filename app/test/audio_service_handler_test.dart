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

  test('swiping the notification away keeps the session usable', () async {
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

    await controller.playQueue([_t('a'), _t('b')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // BaseAudioHandler.onNotificationDeleted() delegates to stop(), which drops
    // the service and deactivates the MediaSession for good. The next play()
    // would then have a dead session: no notification, no head-unit progress.
    await handler.onNotificationDeleted();
    final afterSwipe = handler.playbackState.value;
    expect(afterSwipe.playing, isFalse);
    expect(afterSwipe.processingState, AudioProcessingState.idle);
    expect(handler.mediaItem.value?.title, 'a',
        reason: 'metadata must survive a notification swipe');

    // The session has to come back for the next track.
    await handler.play();
    final resumed = handler.playbackState.value;
    expect(resumed.processingState, AudioProcessingState.ready);
    expect(resumed.playing, isTrue);
    expect(resumed.androidCompactActionIndices, [0, 1, 2],
        reason: 'carousel layout must stay fixed across a stop/start cycle');
  });

  test('carousel keeps a fixed 3-slot shape across play/pause', () async {
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

    final shapes = <List<int>?>[];
    final controls = <List<MediaAction>>[];
    final sub = handler.playbackState.listen((state) {
      shapes.add(state.androidCompactActionIndices);
      controls.add([for (final c in state.controls) c.action]);
    });
    addTearDown(sub.cancel);

    await controller.playQueue([_t('a')]);
    await handler.pause();
    await handler.play();

    // A head unit caches the action list positionally; if the declared count
    // changes on pause the car's slots desynchronise and transport commands
    // (and the progress notifications they piggyback on) stop arriving.
    final declared = shapes.whereType<List<int>>().toSet();
    expect(declared, {
      const [0, 1, 2]
    }, reason: 'compact slot layout changed at runtime: $shapes');
    final last = controls.last;
    expect(last, [
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
    ]);
  });

  test('stop() pauses the engine and holds the queue', () async {
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

    await handler.stop();

    // stop() used to only broadcast idle, leaving the engine playing behind a
    // session the system had already torn down.
    expect(controller.snapshot.isPlaying, isFalse);
    expect(controller.snapshot.display, PlayerDisplayState.idle);
    expect(container.read(playerControllerProvider).queue.length, 1,
        reason: 'queue is kept so the user can resume');
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
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
