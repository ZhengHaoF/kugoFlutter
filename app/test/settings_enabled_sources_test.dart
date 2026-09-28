import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/app.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/data/sources/sources.dart';
import 'package:kugo/features/auth/netease_login_controller.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/shell/desktop_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_device_login_source.dart';

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

  group('网易云需登录才生效（setNeteaseAccess）', () {
    test('未登录：移出启用集、回落默认源并落盘', () async {
      final container = await restored({
        'settings.enabledSources': ['kugou', 'netease'],
        'settings.defaultSource': 'netease',
      });
      await container
          .read(settingsControllerProvider.notifier)
          .setNeteaseAccess(false);

      final s = container.read(settingsControllerProvider);
      expect(s.enabledSources, {MusicPlatform.kugou});
      expect(s.defaultSource, MusicPlatform.kugou);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('settings.enabledSources'), ['kugou']);
      expect(prefs.getString('settings.defaultSource'), 'kugou');
    });

    test('未登录且只启用了网易云：回落酷狗，不落到空集', () async {
      final container = await restored({
        'settings.enabledSources': ['netease'],
      });
      await container
          .read(settingsControllerProvider.notifier)
          .setNeteaseAccess(false);

      expect(
        container.read(settingsControllerProvider).enabledSources,
        {MusicPlatform.kugou},
      );
    });

    test('登录：并入启用集', () async {
      final container = await restored({
        'settings.enabledSources': ['kugou'],
      });
      await container
          .read(settingsControllerProvider.notifier)
          .setNeteaseAccess(true);

      expect(
        container.read(settingsControllerProvider).enabledSources,
        {MusicPlatform.kugou, MusicPlatform.netease},
      );
    });

    test('幂等：状态一致时不改动', () async {
      final container = await restored({
        'settings.enabledSources': ['kugou'],
      });
      await container
          .read(settingsControllerProvider.notifier)
          .setNeteaseAccess(false);

      expect(
        container.read(settingsControllerProvider).enabledSources,
        {MusicPlatform.kugou},
      );
    });
  });

  /// 挂一个设置页（KugoApp 不经 main()，registry 需手动注册；登录源用假源
  /// 以模拟网易云的登录/未登录两态，避免碰网络）。
  Future<ProviderContainer> pumpSettingsApp(
    WidgetTester tester, {
    required LoginAccount? neteaseAccount,
  }) async {
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
    registerDefaultMusicSources();

    final login = FakeDeviceLoginSource()..account = neteaseAccount;
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: FakeAudioPlayer()),
        ),
        neteaseLoginSourceProvider.overrideWithValue(login),
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
    return container;
  }

  testWidgets('UI：网易云已登录可关闭再启用（回归：再点开关无反应）', (tester) async {
    await pumpSettingsApp(
      tester,
      neteaseAccount: const LoginAccount(userId: '7', nickname: '已登录'),
    );

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

    expect(neteaseOn(), isTrue, reason: '登录态下默认两源全开');

    // 关闭网易云。
    await tapNetease();
    expect(neteaseOn(), isFalse, reason: '关闭后开关应变为关');

    // 再点启用：应恢复为开（回归点：级联曾把启用分支的 add 抵消）。
    await tapNetease();
    expect(neteaseOn(), isTrue, reason: '再次点击应恢复启用');
  });

  testWidgets('UI：网易云未登录时开关置灰、显示为关并提示先登录', (tester) async {
    await pumpSettingsApp(tester, neteaseAccount: null);

    final tile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('启用网易云音源'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.value, isFalse, reason: '未登录时显示为关（即便启用集残留）');
    expect(tile.onChanged, isNull, reason: '未登录时不可点');
    expect((tile.subtitle as Text).data, '登录网易云后可启用');
    // 子开关同样提示先登录，而不是误读成「用户自己关掉了」。
    expect(find.text('登录网易云后可启用'), findsWidgets);
  });
}
