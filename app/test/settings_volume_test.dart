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

  double volume(ProviderContainer c) => c.read(settingsControllerProvider).volume;

  SettingsController ctrl(ProviderContainer c) =>
      c.read(settingsControllerProvider.notifier);

  test('默认音量 100%', () async {
    final c = await restored({});
    expect(volume(c), 1.0);
  });

  test('读取已保存音量（非 bool 值按字符串落盘）', () async {
    final c = await restored({'settings.volume': '0.35'});
    expect(volume(c), 0.35);
  });

  test('脏数据回落默认 1.0', () async {
    final c = await restored({'settings.volume': 'not-a-number'});
    expect(volume(c), 1.0);
  });

  test('setVolume 夹到 0..1 并落盘为字符串', () async {
    final c = await restored({});
    await ctrl(c).setVolume(0.42);
    expect(volume(c), 0.42);
    await ctrl(c).setVolume(9);
    expect(volume(c), 1.0);
    await ctrl(c).setVolume(-1);
    expect(volume(c), 0.0);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.volume'), '0.0');
  });
}
