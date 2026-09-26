import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/profile/profile_page.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:kugo/shared/widgets/mini_player_bar.dart';
import 'package:kugo/shared/widgets/player_icon_buttons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

Track _track(String id, {String name = '', String artist = 'artist'}) => Track(
      id: id,
      name: name.isEmpty ? id : name,
      artist: artist,
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 120000,
    );

/// 取迷你条上那个播放/暂停形态图标（同一时刻只会有一个）。
PlayPauseIcon _playPause(WidgetTester tester) =>
    tester.widget<PlayPauseIcon>(find.byType(PlayPauseIcon));

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
    expect(find.byType(PlayPauseIcon), findsNothing);

    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue([_track('a', name: '唯一')]);
    await tester.pump();

    expect(find.text('唯一'), findsOneWidget);
    // 播放/暂停现在是 AnimatedIcon 变形（PlayPauseIcon），不再是 IconData
    // 硬切换，所以按组件状态断言而不是按 byIcon 找图标。
    expect(_playPause(tester).playing, isTrue);

    controller.togglePlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_playPause(tester).playing, isFalse);
  });

  testWidgets('Profile shortcut tiles open their sheets', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    // The link tiles sit below the fold in the default 800x600 test viewport.
    Future<void> revealTile(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    // Every link tile that used to be a dead `onTap: () {}` entry must now
    // open a sheet — guards against silently un-wiring them again.
    await revealTile('音质设置');
    await tester.tap(find.text('音质设置'));
    await tester.pumpAndSettle();
    // Sheet lists every档 with the current one ticked.
    expect(find.text('无损'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // dismiss sheet
    await tester.pumpAndSettle();

    await revealTile('定时停止');
    await tester.tap(find.text('定时停止'));
    await tester.pumpAndSettle();
    expect(find.text('15 分钟'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await revealTile('关于');
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('0.1.0'), findsOneWidget);
  });

  testWidgets('Profile stats never show hardcoded numbers', (tester) async {
    SharedPreferences.setMockInitialValues({});
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
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.pumpAndSettle();

    // The two former fakes. If either reappears, the tile has regressed to a
    // placeholder masquerading as real data.
    expect(find.text('56'), findsNothing);
    expect(find.text('12'), findsNothing);

    // 我喜欢 resolves to a real 0 (empty likes list), while 最近播放 and 歌单
    // stay as placeholders — a genuine 0 and an unknown must not look alike.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('需登录'), findsOneWidget); // 歌单 hint while signed out
  });
}
