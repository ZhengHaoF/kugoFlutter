/// 播放页封面的「点击看大图」接线：桌面 hover 提示 + 点击打开查看器。
///
/// 口径同底栏展开图标 / TrackTile 的 MV 图标：桌面 hover 才浮现提示，
/// 静息时封面全彩；移动端无 hover，直接点。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/player/full_player_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/widgets/cover_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _mockTrack(String id) => Track(
      id: id,
      name: '测试歌曲',
      artist: '测试歌手',
      album: '测试专辑',
      coverUrl: 'mock://$id',
      durationMs: 210000,
    );

void main() {
  Future<ProviderContainer> rig() async {
    SharedPreferences.setMockInitialValues({
      'kugo_device_dfid_registered': true,
      'kugo_device_dfid': 'test-dfid',
      'kugo_device_guid': 'test-guid',
    });
    musicSourceRegistry = MusicSourceRegistry([ScriptedFmSource()]);
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: FakeAudioPlayer()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(playerControllerProvider.notifier)
        .playQueue([_mockTrack('t1')]);
    // demo 曲目会起 400ms / 4s 两个周期定时器，pause 一并停掉
    // （同 desktop_layout_test 的处理），否则收尾报 pending timer。
    container.read(playerControllerProvider.notifier).togglePlay();
    return container;
  }

  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: FullPlayerPage())),
      ),
    );
    await tester.pump();
  }

  /// 封面上的「查看大图」提示层（罩层 + 图标外面那层 AnimatedOpacity）。
  AnimatedOpacity zoomHint(WidgetTester tester) => tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byIcon(Icons.zoom_in_rounded),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );

  testWidgets('hover 封面：浮出「查看大图」提示', (tester) async {
    await pumpPage(tester, await rig());

    expect(zoomHint(tester).opacity, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.zoom_in_rounded)));
    await tester.pump();

    expect(zoomHint(tester).opacity, 1);
  });

  testWidgets('点击封面：打开大图查看器', (tester) async {
    await pumpPage(tester, await rig());

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CoverViewer), findsOneWidget);
  });
}
