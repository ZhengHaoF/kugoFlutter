import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

class _Bridge implements KugoMediaBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('buffering engine cursor is independent of session prediction', (
    tester,
  ) async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine, source: FakeMusicSource()),
        ),
      ],
    );
    final player = container.read(playerControllerProvider.notifier);
    player.attachBridge(_Bridge());
    await player.playQueue([
      const Track(
        id: 'fixture',
        hash: 'fixture',
        name: 'fixture',
        artist: '',
        album: '',
        coverUrl: '',
        durationMs: 20000,
      ),
    ]);
    await tester.pump(const Duration(seconds: 3));
    engine.emitPosition(const Duration(milliseconds: 500));
    await tester.pump();
    expect(player.position.value, 500);
    engine.emitPosition(const Duration(milliseconds: 400));
    await tester.pump();
    expect(player.position.value, 500);
    player.seekTo(100);
    await tester.pump();
    engine.emitPosition(const Duration(milliseconds: 200));
    await tester.pump();
    expect(player.position.value, 200);
    container.dispose();
    await tester.pump();
  });
}
