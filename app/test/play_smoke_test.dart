import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

/// Mock smoke: play queue → advance → toggle → seek clamp.
/// Uses hash tracks (real play path) with SharedPreferences mock so
/// DeviceIdentity can load; network resolve fails → engine never needed
/// for URL, but demo/hash branch still exercises queue UI state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Track t(String id, {bool withHash = false}) => Track(
        id: id,
        name: id,
        artist: 'a',
        album: 'b',
        coverUrl: 'mock://$id',
        durationMs: 10000,
        hash: withHash ? 'hash_$id' : '',
      );

  test('smoke: play queue, next, toggle, seek', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    // No-hash tracks → local demo engine path (deterministic offline smoke).
    await controller.playQueue([t('s1'), t('s2'), t('s3')], startIndex: 0);
    var state = container.read(playerControllerProvider);
    expect(state.current?.id, 's1');
    expect(state.isPlaying, isTrue);

    controller.seekTo(3000);
    state = container.read(playerControllerProvider);
    expect(state.positionMs, 3000);

    await controller.next();
    state = container.read(playerControllerProvider);
    expect(state.current?.id, 's2');
    expect(state.positionMs, 0);

    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    controller.seekTo(999999);
    expect(container.read(playerControllerProvider).positionMs, 10000);
  });

  test('smoke: hash track fails resolve cleanly without inventing play', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([t('h1', withHash: true)]);
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
