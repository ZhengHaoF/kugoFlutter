import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/app.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/data/sources/sources.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/shell/desktop_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> restored(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  Set<MusicPlatform> enabled(ProviderContainer c) =>
      c.read(settingsControllerProvider).enabledSources;

  test('全新安装默认全部启用', () async {
    final container = await restored({});
    expect(enabled(container), {MusicPlatform.kugou, MusicPlatform.netease});
  });

  test('落盘还原（只启用网易云）', () async {
    final container = await restored({
      'settings.enabledSources': ['netease'],
    });
    expect(enabled(container), {MusicPlatform.netease});
  });

  test('空列表（非法态）回退全集', () async {
    final container = await restored({'settings.enabledSources': <String>[]});
    expect(enabled(container), {MusicPlatform.kugou, MusicPlatform.netease});
  });

  test('未知取值被丢弃，不误读成酷狗', () async {
    final container = await restored({
      'settings.enabledSources': ['netease', 'qqmusic'],
    });
    expect(enabled(container), {MusicPlatform.netease});
  });

  test('setEnabledSources 落盘并生效', () async {
    final container = await restored({});
    await container
        .read(settingsControllerProvider.notifier)
        .setEnabledSources({MusicPlatform.kugou});

    expect(enabled(container), {MusicPlatform.kugou});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('settings.enabledSources'), ['kugou']);
  });

  test('关闭网易云后可重新启用（关→开往返）', () async {
    final container = await restored({});
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setEnabledSources({MusicPlatform.kugou});
    expect(enabled(container), {MusicPlatform.kugou});

    // 再点启用：应恢复全集并落盘（回归：关闭后再次打开无反应）。
    await controller.setEnabledSources({
      MusicPlatform.kugou,
      MusicPlatform.netease,
    });
    expect(enabled(container), {MusicPlatform.kugou, MusicPlatform.netease});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('settings.enabledSources'),
        ['kugou', 'netease']);
  });

  test('空集合被拒绝（至少保留一个源）', () async {
    final container = await restored({});
    await container
        .read(settingsControllerProvider.notifier)
        .setEnabledSources({});

    expect(enabled(container), {MusicPlatform.kugou, MusicPlatform.netease});
  });

  test('停用当前默认源时默认源联动回退', () async {
    final container = await restored({
      'settings.defaultSource': 'kugou',
    });
    await container
        .read(settingsControllerProvider.notifier)
        .setEnabledSources({MusicPlatform.netease});

    final s = container.read(settingsControllerProvider);
    expect(s.enabledSources, {MusicPlatform.netease});
    expect(s.defaultSource, MusicPlatform.netease);
    // 回退值同时落盘，冷启动不再指向已停用的源。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.defaultSource'), 'netease');
  });

  test('effectiveDefaultSource：默认源可用时原样返回', () async {
    final container = await restored({'settings.defaultSource': 'netease'});
    expect(
      container.read(settingsControllerProvider).effectiveDefaultSource,
      MusicPlatform.netease,
    );
  });

  testWidgets('UI：关闭网易云后可重新启用（回归：再点开关无反应）', (tester) async {
    // 高视口：设置页 SmoothListView 懒构建，视口够高才能让「账号管理」
    // Section（整源开关）进树；桌面端 SilkyScroll 不是标准 Scrollable，
    // scrollUntilVisible 滚不了，直接拉高视口最稳。
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({});
    // KugoApp 不经 main()，registry 需手动注册，否则开关只兜底出酷狗行。
    registerDefaultMusicSources();

    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const KugoApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 进设置页。
    await tester.tap(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.text('系统设置'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Finder neteaseTile() => find.ancestor(
          of: find.text('启用网易云音源'),
          matching: find.byType(SwitchListTile),
        );
    bool neteaseOn() =>
        tester.widget<SwitchListTile>(neteaseTile()).value;

    Future<void> tapNetease() async {
      await tester.tap(neteaseTile());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(neteaseOn(), isTrue, reason: '默认两源全开');

    // 关闭网易云。
    await tapNetease();
    expect(neteaseOn(), isFalse, reason: '关闭后开关应变为关');

    // 再点启用：应恢复为开（回归点：级联曾把启用分支的 add 抵消）。
    await tapNetease();
    expect(neteaseOn(), isTrue, reason: '再次点击应恢复启用');
  });
}
