import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_music_source.dart';
import 'package:go_router/go_router.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/fm/fm_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

Future<ProviderContainer> _rig() async {
  // 已注册设备身份：避免 AuthController 恢复时去打 /risk 注册接口把测试挂住。
  SharedPreferences.setMockInitialValues({
    'kugo_device_dfid_registered': true,
    'kugo_device_dfid': 'test-dfid',
    'kugo_device_guid': 'test-guid',
  });
  // 未登录 → 控制器走关键词兜底池，起播一定有歌。
  musicSourceRegistry = MusicSourceRegistry([ScriptedFmSource()]);
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: FakeAudioPlayer()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpPage(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/fm',
          routes: [
            GoRoute(path: '/fm', builder: (_, _) => const FmPage()),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('idle FM page shows start CTA and starts the session', (tester) async {
    final container = await _rig();
    await _pumpPage(tester, container);

    expect(find.byKey(const ValueKey('fm_start_cta')), findsOneWidget);
    expect(find.text('开始电台'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fm_start_cta')));
    await tester.runAsync(
      () => container.read(fmControllerProvider.notifier).start(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final fm = container.read(fmControllerProvider);
    expect(fm.active, isTrue);
    expect(container.read(playerControllerProvider).queueSource.name, 'fm');
  });

  testWidgets('active FM page surfaces the current track name', (tester) async {
    final container = await _rig();
    await tester.runAsync(
      () => container.read(fmControllerProvider.notifier).start(),
    );
    await _pumpPage(tester, container);
    await tester.pump(const Duration(milliseconds: 200));

    final track = container.read(playerControllerProvider).current;
    expect(track, isNotNull);
    expect(find.text(track!.name), findsWidgets);
  });
}
