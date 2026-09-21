import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/fm/fm_radio_card.dart';
import 'package:kugo/features/player/fm_controls.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

class _FakeSearch implements SearchRepository {
  final List<String> calls = [];

  @override
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    calls.add(keyword);
    return List.generate(
      4,
      (i) => Track(
        id: '$keyword-$i',
        name: '$keyword-$i',
        artist: 'artist',
        album: 'album',
        coverUrl: 'http://cover/$keyword',
        durationMs: 10000,
      ),
    );
  }

  @override
  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      SearchPageResult(items: await searchSongs(keyword, pageSize: pageSize));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

typedef _Rig = ({ProviderContainer container, _FakeSearch search});

/// 只造容器；会话的启动放在 [tester.runAsync] 里跑 ——
/// `testWidgets` 的 FakeAsync 时钟不会自己推进，直接在测试体里 await
/// 真实异步（SharedPreferences / 播放器持久化）会永远挂住。
Future<_Rig> _rig() async {
  SharedPreferences.setMockInitialValues({
    'kugo_device_dfid_registered': true,
    'kugo_device_dfid': 'test-dfid',
    'kugo_device_guid': 'test-guid',
  });
  final search = _FakeSearch();
  final container = ProviderContainer(
    overrides: [
      fmControllerProvider.overrideWith(() => FmController(search: search)),
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: FakeAudioPlayer()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, search: search);
}

Future<void> _startFm(WidgetTester tester, ProviderContainer container) async {
  await tester.runAsync(
    () => container.read(fmControllerProvider.notifier).start(),
  );
  await tester.pump();
}

/// 面板里有常驻动画（黑胶旋转 / 频谱跳动），`pumpAndSettle` 永远等不到静止，
/// 所以只能用定时 pump 把转场推过去。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPill(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FmEntryPill())),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pill names the station and the pool, without a pending dot',
      (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);

    final fm = rig.container.read(fmControllerProvider);
    expect(find.text('${fm.mode.stationTitle} · ${fm.pool.label}'),
        findsOneWidget);
    // 没有待生效的轴 → 不画圆点（否则用户会以为切换没生效）。
    expect(find.byKey(const ValueKey('fm_pending_dot')), findsNothing);
  });

  testWidgets('switching an axis marks the pill as pending', (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);

    rig.container
        .read(fmControllerProvider.notifier)
        .setPendingPool(FmSongPool.explore);
    await tester.pump();

    // 药丸改读「待生效」的轴值，并亮出圆点。
    expect(find.textContaining(FmSongPool.explore.label), findsOneWidget);
    expect(find.byKey(const ValueKey('fm_pending_dot')), findsOneWidget);
  });

  testWidgets('tapping the pill opens the sheet with both axes',
      (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);

    await tester.tap(find.byType(FmEntryPill));
    await _settle(tester);

    // 原来 FM 页那张卡必须原样在：渐变电台卡 + 黑胶台，而不是几行普通设置项。
    expect(find.byType(FmRadioCard), findsOneWidget);
    expect(find.byType(FmVinylStage), findsOneWidget);
    expect(find.text('私人 FM'), findsWidgets);
    // 档位轴在卡里（红心/小众/速览），歌池轴在右上角胶囊（Alpha/Beta/Gamma）。
    for (final m in FmMode.values) {
      expect(find.text(m.label), findsWidgets);
    }
    for (final p in FmSongPool.values) {
      expect(find.text(p.label), findsWidgets);
    }
  });

  testWidgets('picking Gamma in the sheet is pending, not immediate',
      (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);
    final before = rig.container.read(playerControllerProvider).current!.id;

    await tester.tap(find.byType(FmEntryPill));
    await _settle(tester);

    await tester.tap(find.text(FmSongPool.explore.label).last);
    await _settle(tester);

    expect(rig.container.read(fmControllerProvider).pendingPool,
        FmSongPool.explore);
    // 当前这首不动：切池只在下一首生效。
    expect(rig.container.read(playerControllerProvider).current!.id, before);
    expect(find.textContaining('下一首生效'), findsWidgets);
    expect(find.text('立即生效'), findsOneWidget);
  });

  testWidgets('不喜欢 in the sheet drops the track from the live queue',
      (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);
    final before = rig.container.read(playerControllerProvider).current!.id;

    await tester.tap(find.byType(FmEntryPill));
    await _settle(tester);

    await tester.runAsync(
      () => rig.container.read(fmControllerProvider.notifier).dislike(),
    );
    await _settle(tester);

    final player = rig.container.read(playerControllerProvider);
    expect(player.queue.any((t) => t.id == before), isFalse);
    expect(player.current!.id, isNot(before));
  });
}
