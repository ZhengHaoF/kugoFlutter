import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> restored(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  CloseBehavior read(ProviderContainer c) =>
      c.read(settingsControllerProvider).closeBehavior;

  test('全新安装默认「每次询问」', () async {
    final container = await restored({});
    expect(read(container), CloseBehavior.ask);
  });

  test('迁移旧 closeToTray=true → 最小化到托盘', () async {
    final container = await restored({'settings.closeToTray': true});
    expect(read(container), CloseBehavior.tray);
  });

  test('迁移旧 closeToTray=false → 退出应用', () async {
    final container = await restored({'settings.closeToTray': false});
    expect(read(container), CloseBehavior.quit);
  });

  test('新 key 优先于旧 key', () async {
    final container = await restored({
      'settings.closeToTray': true,
      'settings.closeBehavior': 'quit',
    });
    expect(read(container), CloseBehavior.quit);
  });

  test('未知取值回退到「每次询问」', () async {
    final container = await restored({'settings.closeBehavior': 'nope'});
    expect(read(container), CloseBehavior.ask);
  });

  test('setCloseBehavior 落盘并清理旧 key', () async {
    final container = await restored({'settings.closeToTray': true});
    await container
        .read(settingsControllerProvider.notifier)
        .setCloseBehavior(CloseBehavior.quit);

    expect(read(container), CloseBehavior.quit);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.closeBehavior'), 'quit');
    // 迁移读完即删，避免旧布尔之后回写覆盖新值。
    expect(prefs.getBool('settings.closeToTray'), isNull);
  });
}