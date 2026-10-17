import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/source/music_platform.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

const _kGlobalKey = 'settings.desktopLyricOffsetMs';
const _kOverridesKey = 'settings.lyricOffsetOverrides';

Track _hashed(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'https://example.com/$id.jpg',
      durationMs: 10000,
      hash: 'hash_$id',
    );

String _key(String id) => musicIdentity(MusicPlatform.kugou, id);

Future<ProviderContainer> _restored(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(settingsControllerProvider.notifier).ensureRestored();
  return container;
}

AppSettings _settings(ProviderContainer c) =>
    c.read(settingsControllerProvider);

SettingsController _ctrl(ProviderContainer c) =>
    c.read(settingsControllerProvider.notifier);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings.lyricOffsetFor', () {
    test('无微调时等于全局值', () {
      const s = AppSettings(lyricOffsetMs: 500);
      expect(s.lyricOffsetFor(null), 500);
      expect(s.lyricOffsetFor('kugou:a'), 500);
      expect(s.hasLyricOffsetOverride('kugou:a'), isFalse);
    });

    test('逐曲微调叠加在全局值之上', () {
      const s = AppSettings(
        lyricOffsetMs: 500,
        lyricOffsetOverrides: {'kugou:a': -200},
      );
      expect(s.lyricOffsetFor('kugou:a'), 300);
      expect(s.lyricOffsetFor('kugou:b'), 500);
      expect(s.hasLyricOffsetOverride('kugou:a'), isTrue);
      expect(s.hasLyricOffsetOverride('kugou:b'), isFalse);
    });
  });

  group('逐曲微调持久化', () {
    test('调整后落盘为 JSON，reset 后清空该曲', () async {
      final c = await _restored({});
      await _ctrl(c).adjustTrackLyricOffsetMs(_key('a'), deltaMs: 300);
      await _ctrl(c).adjustTrackLyricOffsetMs(_key('a'), deltaMs: -100);
      expect(_settings(c).lyricOffsetOverrides[_key('a')], 200);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kOverridesKey), contains(_key('a')));

      await _ctrl(c).adjustTrackLyricOffsetMs(_key('a'), reset: true);
      expect(_settings(c).lyricOffsetOverrides, isEmpty);
      expect(prefs.getString(_kOverridesKey), '{}');
    });

    test('微调夹到 ±10s', () async {
      final c = await _restored({});
      await _ctrl(c).adjustTrackLyricOffsetMs(_key('a'), deltaMs: 99000);
      expect(_settings(c).lyricOffsetOverrides[_key('a')], 10000);
    });

    test('从落盘 JSON 还原（脏条目逐项丢弃）', () async {
      final c = await _restored({
        _kOverridesKey: '{"kugou:a":-200,"":5,"kugou:b":"not-a-number",'
            '"kugou:c":88888}',
      });
      final overrides = _settings(c).lyricOffsetOverrides;
      expect(overrides[_key('a')], -200);
      expect(overrides.containsKey(''), isFalse);
      expect(overrides.containsKey(_key('b')), isFalse);
      expect(overrides[_key('c')], 10000);
    });

    test('全局偏移按字符串落盘也能读回（历史 getInt 读法会归零）', () async {
      final c = await _restored({_kGlobalKey: '500'});
      expect(_settings(c).lyricOffsetMs, 500);
    });

    test('setLyricOffsetMs 落盘且夹到 ±10s', () async {
      final c = await _restored({});
      await _ctrl(c).setLyricOffsetMs(750);
      expect(_settings(c).lyricOffsetMs, 750);
      await _ctrl(c).setLyricOffsetMs(-99999);
      expect(_settings(c).lyricOffsetMs, -10000);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_kGlobalKey), '-10000');
    });
  });

  test('lyricTimeOffsetMsProvider 跟随当前曲：全局 + 逐曲微调', () async {
    SharedPreferences.setMockInitialValues({
      _kGlobalKey: '300',
      _kOverridesKey: '{"${_key('a')}":-100}',
    });
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource()
      ..lyricsByKey[_key('a')] = [const LyricLine(timeMs: 0, text: 'a')]
      ..lyricsByKey[_key('b')] = [const LyricLine(timeMs: 0, text: 'b')];
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine, source: source),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();

    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue(
      [_hashed('a'), _hashed('b')],
      startIndex: 0,
    );

    // a 有 -100 的逐曲微调。
    expect(container.read(lyricTimeOffsetMsProvider), 200);

    await controller.next();
    // b 没被微调过，只吃全局值。
    expect(container.read(lyricTimeOffsetMsProvider), 300);
  });
}
