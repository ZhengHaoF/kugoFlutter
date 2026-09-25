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
}
