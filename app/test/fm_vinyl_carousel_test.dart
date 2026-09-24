import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_music_source.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/theme/kugo_theme.dart';
import 'package:kugo/features/fm/fm_radio_card.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

/// 外部 currentIndex 测试用的可变槽（单测内复位）。
int _externalIndex = 0;

List<Track> _tracks(int n) => List.generate(
      n,
      (i) => Track(
        id: 't$i',
        name: 'Track $i',
        artist: 'Artist',
        album: 'Album',
        coverUrl: 'http://cover/$i',
        durationMs: 120000,
      ),
    );

const double _disc = 200;
const double _gap = 32;
const double _pitch = _disc + _gap;

Future<void> _pumpCarousel(
  WidgetTester tester, {
  required List<Track> tracks,
  required ValueChanged<int> onPlayIndex,
  int currentIndex = 0,
  AnimationController? spin,
  VoidCallback? onTapCurrent,
}) async {
  final controller = spin ??
      AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 18),
      );
  if (spin == null) addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildKugoTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 900,
            height: 240,
            child: Builder(
              builder: (context) => FmVinylCarousel(
                kugo: KugoTheme.of(context),
                accent: const Color(0xFF3B82F6),
                spin: controller,
                tracks: tracks,
                currentIndex: currentIndex,
                fallbackCoverUrl: 'fm',
                playing: false,
                onPlayIndex: onPlayIndex,
                onTapCurrent: onTapCurrent ?? () {},
                discSize: _disc,
                sideGap: _gap,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

ScrollPosition _position(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(FmVinylCarousel.carouselKey),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

/// 滚到某一页并走完吸附 settle（不依赖 drag 手感）。
///
/// FakeAsync 下不能 `await animateTo`（动画只在 pump 里推进，会死锁），
/// 必须先启动再 pump 推完。
Future<void> _settleAt(
  WidgetTester tester,
  double pixels, {
  Duration animation = const Duration(milliseconds: 200),
}) async {
  final position = _position(tester);
  if ((position.pixels - pixels).abs() >= 0.5) {
    // ignore: discarded_futures
    position.animateTo(pixels, duration: animation, curve: Curves.linear);
    await tester.pump();
    await tester.pump(animation);
    await tester.pump(const Duration(milliseconds: 30));
  }
  // ScrollEnd → post-frame _handleSettle → 可能再 snap 一档。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(bootstrapFakeMusicSources);

  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settling one pitch to the right plays that queue index',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    await _settleAt(tester, _pitch);
    expect(played, [1]);
  });

  testWidgets('settling back on the current index does not play',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    // 对齐停在 index 0：不应回调。
    await _settleAt(tester, 0);
    expect(played, isEmpty);
  });

  testWidgets(
      'settling on a different index after returning to current only plays once',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    await _settleAt(tester, _pitch);
    expect(played, [1]);

    // 再次 settle 同一位置（重复 ScrollEnd）不补播。
    await _settleAt(tester, _pitch);
    expect(played, [1]);
  });

  testWidgets('external currentIndex change scrolls without onPlayIndex',
      (tester) async {
    final played = <int>[];
    _externalIndex = 0;
    final spin = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 18),
    );
    addTearDown(spin.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKugoTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: FmVinylCarousel(
                        kugo: KugoTheme.of(context),
                        accent: const Color(0xFF3B82F6),
                        spin: spin,
                        tracks: _tracks(6),
                        currentIndex: _externalIndex,
                        fallbackCoverUrl: 'fm',
                        playing: false,
                        onPlayIndex: played.add,
                        onTapCurrent: () {},
                        discSize: _disc,
                        sideGap: _gap,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('advance'),
                      onPressed: () => setState(() => _externalIndex = 2),
                      child: const Text('next'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(played, isEmpty);
    _externalIndex = 0;
  });

  testWidgets('empty queue shows one placeholder and no ListView',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: const [],
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    expect(find.byKey(FmVinylCarousel.carouselKey), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(played, isEmpty);
  });

  testWidgets('tapping a non-current disc reports that index', (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    final vinyls = find.descendant(
      of: find.byKey(FmVinylCarousel.carouselKey),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Vinyl',
      ),
    );
    expect(vinyls, findsWidgets);
    await tester.tap(vinyls.at(1));
    await tester.pump();

    expect(played, [1]);
  });

  testWidgets('one hard fling advances exactly one disc', (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    // 以前的 ClampingScrollPhysics 在这种力度下会连滑 4 档以上。
    await tester.fling(
      find.byKey(FmVinylCarousel.carouselKey),
      const Offset(-600, 0),
      8000,
    );
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, closeTo(_pitch, 1.0));
    expect(played, [1]);
  });

  testWidgets('a long drag cannot pull more than one disc away', (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(FmVinylCarousel.carouselKey)),
    );
    // 分步拖 3 档（真实手指轨迹）：拖动途中就被夹在起点 ±1 档。
    for (var i = 1; i <= 6; i++) {
      await gesture.moveBy(
        Offset(-_pitch / 2, 0),
        timeStamp: Duration(milliseconds: 40 * i),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(_position(tester).pixels, closeTo(_pitch, 1.0));

    await gesture.up(timeStamp: const Duration(milliseconds: 340));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, closeTo(_pitch, 1.0));
    expect(played, [1]);
  });

  testWidgets('a slow drag under half a disc snaps back without playing',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(FmVinylCarousel.carouselKey)),
    );
    // 慢拖 0.3 档（~150px/s，低于甩动阈值）→ 回弹原位、不起播。
    await gesture.moveBy(
      Offset(-_pitch * 0.3, 0),
      timeStamp: const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(_position(tester).pixels, closeTo(0, 1.0));
    expect(played, isEmpty);
  });

  testWidgets('a quick flick under half a disc still advances one disc',
      (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    // 位移不足半档、但释放速度够快（≈1000px/s）→ 按甩的方向走一档。
    await tester.timedDrag(
      find.byKey(FmVinylCarousel.carouselKey),
      const Offset(-60, 0),
      const Duration(milliseconds: 60),
    );
    await tester.pump();
    final mid = _position(tester).pixels;
    expect(mid, greaterThan(0), reason: '应该已在弹簧吸附途中');
    expect(mid, lessThan(_pitch));

    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(_pitch, 1.0));
    expect(played, [1]);
  });

  testWidgets('grabbing mid-snap still lands on a grid line', (tester) async {
    final played = <int>[];
    await _pumpCarousel(
      tester,
      tracks: _tracks(6),
      onPlayIndex: played.add,
      currentIndex: 0,
    );

    await tester.timedDrag(
      find.byKey(FmVinylCarousel.carouselKey),
      const Offset(-60, 0),
      const Duration(milliseconds: 60),
    );
    await tester.pump();
    expect(_position(tester).pixels, greaterThan(0));

    // 弹簧吸附途中再抓一次：起点取「最近的整档」，落点必须仍是整档。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(FmVinylCarousel.carouselKey)),
    );
    await gesture.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up(timeStamp: const Duration(milliseconds: 32));
    await tester.pumpAndSettle();

    final px = _position(tester).pixels;
    expect(px % _pitch, closeTo(0, 1.0));
    expect(played.length, lessThanOrEqualTo(1));
  });

  testWidgets('playAtIndex from settle updates player currentIndex',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'kugo_device_dfid_registered': true,
      'kugo_device_dfid': 'test-dfid',
      'kugo_device_guid': 'test-guid',
    });
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: FakeAudioPlayer()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      final player = container.read(playerControllerProvider.notifier);
      await player.playQueue(_tracks(6), startIndex: 0);
    });
    await tester.pump();

    final before = container.read(playerControllerProvider).currentIndex;
    expect(before, 0);

    await _pumpCarousel(
      tester,
      tracks: List.unmodifiable(container.read(playerControllerProvider).queue),
      currentIndex: before,
      onPlayIndex: (i) {
        final player = container.read(playerControllerProvider.notifier);
        final state = container.read(playerControllerProvider);
        if (i == state.currentIndex) return;
        if (i < 0 || i >= state.queue.length) return;
        player.playAtIndex(i);
      },
    );

    await _settleAt(tester, _pitch);

    final after = container.read(playerControllerProvider).currentIndex;
    expect(after, 1);

    // 无 hash 曲目会起 demo tick 周期 Timer；测试结束前清掉，避免 pending timer。
    container.read(playerControllerProvider.notifier).clearQueue();
    await tester.pump();
  });
}
