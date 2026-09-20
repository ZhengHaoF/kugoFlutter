import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/fm/fm_controller.dart';
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
  SharedPreferences.setMockInitialValues({});
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
    await tester.pumpAndSettle();

    // 两条轴的原生名字：档位用中文，歌池用上游代号。
    expect(find.text('档位'), findsOneWidget);
    expect(find.text('歌池'), findsOneWidget);
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
    await tester.pumpAndSettle();

    await tester.tap(find.text(FmSongPool.explore.label).last);
    await tester.pumpAndSettle();

    expect(rig.container.read(fmControllerProvider).pendingPool,
        FmSongPool.explore);
    // 当前这首不动：切池只在下一首生效。
    expect(rig.container.read(playerControllerProvider).current!.id, before);
    expect(find.text('立即生效'), findsOneWidget);
  });

  testWidgets('不喜欢 in the sheet drops the track from the live queue',
      (tester) async {
    final rig = await _rig();
    await _pumpPill(tester, rig.container);
    await _startFm(tester, rig.container);
    final before = rig.container.read(playerControllerProvider).current!.id;

    await tester.tap(find.byType(FmEntryPill));
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => rig.container.read(fmControllerProvider.notifier).dislike(),
    );
    await tester.pumpAndSettle();

    final player = rig.container.read(playerControllerProvider);
    expect(player.queue.any((t) => t.id == before), isFalse);
    expect(player.current!.id, isNot(before));
  });
}
