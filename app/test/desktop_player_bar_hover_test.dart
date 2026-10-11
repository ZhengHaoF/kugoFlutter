/// 桌面底栏封面「展开播放器」提示的 hover 显隐。
///
/// 钉住交互口径：静息态罩层 + 图标不可见（封面全彩），鼠标移入封面才
/// 淡入，移出淡出 —— 与 `mv_entry_test.dart` 里 TrackTile 的行级 hover
/// 显隐同一套语言（140ms AnimatedOpacity）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/widgets/desktop_player_bar.dart';

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
  /// 挂上底栏并喂一首歌（封面 hint 只在有曲目时渲染）。
  Future<void> pumpBar(WidgetTester tester) async {
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
        child: const MaterialApp(home: Scaffold(body: DesktopPlayerBar())),
      ),
    );
    await tester.pump();

    await container
        .read(playerControllerProvider.notifier)
        .playQueue([_mockTrack('t1', name: '晴天', artist: '周杰伦')]);
    // 与 desktop_layout_test 同一手：demo 曲目会起 400ms / 4s 两个周期
    // 定时器，pause 一并停掉，否则收尾报 pending timer。
    container.read(playerControllerProvider.notifier).togglePlay();
    await tester.pump();
  }

  /// 罩层 + 图标外面那层 AnimatedOpacity（展开提示的整体开关）。
  AnimatedOpacity expandHint(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.byIcon(Icons.open_in_full_rounded),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );

  testWidgets('静息态：展开提示不可见，封面无罩层', (tester) async {
    await pumpBar(tester);

    expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
    expect(expandHint(tester).opacity, 0);
  });

  testWidgets('hover 封面：展开提示淡入', (tester) async {
    await pumpBar(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byIcon(Icons.open_in_full_rounded)),
    );
    await tester.pump();

    expect(expandHint(tester).opacity, 1);
  });

  testWidgets('移出封面：展开提示淡出', (tester) async {
    await pumpBar(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byIcon(Icons.open_in_full_rounded)),
    );
    await tester.pump();
    expect(expandHint(tester).opacity, 1);

    // 挪到底栏中段（封面在左端之外）——只退出封面的 MouseRegion。
    await mouse.moveTo(const Offset(600, 10));
    await tester.pump();

    expect(expandHint(tester).opacity, 0);
  });
}
