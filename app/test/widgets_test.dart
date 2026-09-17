import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:kugo/shared/widgets/mini_player_bar.dart';

import 'fakes/fake_audio_player.dart';

Track _track(String id, {String name = '', String artist = 'artist'}) => Track(
      id: id,
      name: name.isEmpty ? id : name,
      artist: artist,
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 120000,
    );

void main() {
  testWidgets('TrackTile shows name and artist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(track: _track('t1', name: '夜空中最亮的星')),
        ),
      ),
    );
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('artist'), findsOneWidget);
  });

  testWidgets('MiniBar play icon toggles with controller state', (tester) async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MiniPlayerBar())),
      ),
    );
    // Empty queue → hidden
    expect(find.byType(MiniPlayerBar), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue([_track('a', name: '唯一')]);
    await tester.pump();

    expect(find.text('唯一'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    controller.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });
}
