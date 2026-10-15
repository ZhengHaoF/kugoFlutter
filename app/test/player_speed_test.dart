import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/source/music_source.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/settings/settings_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'https://example.com/$id.jpg',
      durationMs: 10000,
      hash: 'hash_$id',
    );

(ProviderContainer, FakeAudioPlayer) _boot({MusicSource? source}) {
  final engine = FakeAudioPlayer();
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: engine, source: source),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container, engine);
}

/// 预置倍速的 settings（绕过 SharedPreferences，直接验启动恢复）。
class _PresetSpeedSettings extends SettingsController {
  _PresetSpeedSettings(this.preset);
  final double preset;

  @override
  AppSettings build() => AppSettings(speed: preset);
}

void main() {
  test('setSpeed updates state, engine and persisted setting', () async {
    final (container, engine) = _boot(source: FakeMusicSource());
    final controller = container.read(playerControllerProvider.notifier);
    await controller.playQueue([_t('a')]);

    controller.setSpeed(1.5);

    final state = container.read(playerControllerProvider);
    expect(state.speed, 1.5);
    expect(engine.lastSpeed, 1.5);
    // 唯一写入口把值带进了 settings（落盘记忆）。
    expect(container.read(settingsControllerProvider).speed, 1.5);

    controller.setSpeed(1.0);
    expect(container.read(playerControllerProvider).speed, 1.0);
    expect(container.read(settingsControllerProvider).speed, 1.0);
  });

  test('setSpeed clamps to preset table bounds', () {
    final (container, _) = _boot();
    final controller = container.read(playerControllerProvider.notifier);

    controller.setSpeed(0.1);
    expect(container.read(playerControllerProvider).speed, 0.5);

    controller.setSpeed(9);
    expect(container.read(playerControllerProvider).speed, 2.0);
  });

  test('speed rides the load and lands before playback starts', () async {
    final (container, engine) = _boot(source: FakeMusicSource());
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a'), _t('b')]);
    controller.setSpeed(1.5);
    expect(engine.speedWhenPlaybackStarted, 1.0); // 起播在前，仍 1.0x

    // 切歌：media_kit 的 open() 会重置 rate，倍速必须随加载重放，
    // 且必须在出声前生效（fake 在 playUrl 内镜像真实引擎的顺序）。
    await controller.next();
    expect(engine.lastPlaySpeed, 1.5);
    expect(engine.speed, 1.5);
    expect(engine.speedWhenPlaybackStarted, 1.5);
    expect(container.read(playerControllerProvider).speed, 1.5);
  });

  test('same-track reload carries the current speed', () async {
    final (container, engine) = _boot(source: FakeMusicSource());
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.setSpeed(0.75);
    await controller.reloadCurrent();

    expect(engine.lastPlaySpeed, 0.75);
    expect(engine.speed, 0.75);
    expect(engine.speedWhenPlaybackStarted, 0.75);
  });

  test('cold start restores persisted speed into state and engine', () {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine),
        ),
        settingsControllerProvider.overrideWith(
          () => _PresetSpeedSettings(1.5),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(playerControllerProvider);
    expect(state.speed, 1.5);
    // build() 先灌一次引擎，兜住不经 playUrl 的边角路径。
    expect(engine.lastSpeed, 1.5);
  });
}
