import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/source/music_platform.dart';
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

  MusicPlatform read(ProviderContainer c) =>
      c.read(settingsControllerProvider).defaultSource;

  test('全新安装默认酷狗', () async {
    expect(read(await restored({})), MusicPlatform.kugou);
  });

  test('落盘的网易云被还原', () async {
    expect(
      read(await restored({'settings.defaultSource': 'netease'})),
      MusicPlatform.netease,
    );
  });

  test('未知取值回退到酷狗', () async {
    expect(
      read(await restored({'settings.defaultSource': 'nope'})),
      MusicPlatform.kugou,
    );
  });

  test('setDefaultSource 落盘', () async {
    final container = await restored({});
    await container
        .read(settingsControllerProvider.notifier)
        .setDefaultSource(MusicPlatform.netease);

    expect(read(container), MusicPlatform.netease);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings.defaultSource'), 'netease');
  });
}
