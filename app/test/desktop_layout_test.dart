import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/app.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/shell/desktop_sidebar.dart';
import 'package:kugo/shared/widgets/desktop_player_bar.dart';
import 'package:kugo/shared/widgets/mini_player_bar.dart';

import 'fakes/fake_audio_player.dart';

Track _mockTrack(String id, {String name = '测试歌曲', String artist = '测试歌手'}) =>
    Track(
      id: id,
      name: name,
      artist: artist,
      album: '测试专辑',
      coverUrl: 'mock://$id',
      durationMs: 210000,
    );

void main() {
  testWidgets('desktop wide screen (1280x720) displays DesktopSidebar and DesktopPlayerBar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = FakeAudioPlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider
              .overrideWith(() => PlayerController(engine: engine)),
        ],
        child: const KugoApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(DesktopPlayerBar), findsOneWidget);
    expect(find.byType(MiniPlayerBar), findsNothing);
    expect(find.text('每日推荐'), findsWidgets);
    expect(find.text('排行榜'), findsWidgets);
  });

  testWidgets('mobile narrow screen (400x800) displays mobile dock and mini bar',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final engine = FakeAudioPlayer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider
              .overrideWith(() => PlayerController(engine: engine)),
        ],
        child: const KugoApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DesktopSidebar), findsNothing);
    expect(find.byType(DesktopPlayerBar), findsNothing);
    expect(find.byType(MiniPlayerBar), findsOneWidget);
  });

  testWidgets('DesktopPlayerBar controls play/pause and displays track details',
      (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: DesktopPlayerBar(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Initially empty
    expect(find.text('暂无播放音乐'), findsOneWidget);

    // Feed a track
    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue([_mockTrack('t1', name: '晴天', artist: '周杰伦')]);
    await tester.pump();

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);

    // Toggle play/pause
    controller.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Volume adjustment
    controller.setVolume(0.65);
    await tester.pump();
    expect(container.read(playerControllerProvider).volume, 0.65);
  });
}
