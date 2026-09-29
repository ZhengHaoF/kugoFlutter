import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/mv_models.dart';
import 'package:kugo/features/mv/mv_player_host.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';

MvBrief _brief({String id = '1001', String hash = 'hasha'}) => MvBrief(
      id: id,
      hash: hash,
      name: '测试 MV',
      coverUrl: '',
    );

void main() {
  // 宿主 build 里 ref.listen(playerControllerProvider)：测试环境同样要
  // override 成假引擎，避免拉起真实 media_kit。
  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: FakeAudioPlayer()),
          ),
        ],
      );

  group('MvPlayerHost — 会话状态机（无引擎路径）', () {
    test('初始状态：引擎未活、小窗隐藏、无会话', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final s = container.read(mvPlayerHostProvider);
      expect(s.engineActive, isFalse);
      expect(s.mini, isFalse);
      expect(s.brief, isNull);
      expect(s.rate, 1.0);
      expect(s.volume, 100.0);
      expect(s.muted, isFalse);
    });

    test('引擎未活时 enterMini 是无操作：小窗不可能先于引擎出现', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      host.enterMini();
      expect(container.read(mvPlayerHostProvider).mini, isFalse);
    });

    test('引擎未活时 takeover 返回 false：页面走正常 load', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      expect(host.takeover(_brief()), isFalse);
      // 顺带：无会话时 sessionMatches 恒 false。
      expect(host.sessionMatches(_brief()), isFalse);
    });

    test('exitMini 无小窗时是无操作（幂等）', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      host.exitMini();
      expect(container.read(mvPlayerHostProvider).mini, isFalse);
    });

    test('倍速 / 音量 / 静音：无引擎也只改 state、不崩', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      host.setRate(1.5);
      host.setVolume(30);
      host.toggleMute();
      final s = container.read(mvPlayerHostProvider);
      expect(s.rate, 1.5);
      expect(s.muted, isTrue);
      // 取消静音：恢复到上次音量。
      host.toggleMute();
      expect(container.read(mvPlayerHostProvider).muted, isFalse);
      expect(container.read(mvPlayerHostProvider).volume, 30.0);
    });

    test('setVolume 越界收敛到 0–100，0 视为静音', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      host.setVolume(-20);
      expect(container.read(mvPlayerHostProvider).volume, 0.0);
      expect(container.read(mvPlayerHostProvider).muted, isTrue);
      host.setVolume(300);
      expect(container.read(mvPlayerHostProvider).volume, 100.0);
      expect(container.read(mvPlayerHostProvider).muted, isFalse);
    });

    test('shutdown 幂等：无引擎时安全、状态复位', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final host = container.read(mvPlayerHostProvider.notifier);
      host.setRate(2.0);
      host.shutdown();
      host.shutdown();
      final s = container.read(mvPlayerHostProvider);
      expect(s.engineActive, isFalse);
      expect(s.rate, 1.0);
      expect(s.mini, isFalse);
      expect(s.brief, isNull);
    });
  });

  group('MvHostState — copyWith 与默认值', () {
    test('copyWith 只覆盖给定字段', () {
      const s = MvHostState();
      final next = s.copyWith(mini: true, volume: 40);
      expect(next.engineActive, s.engineActive);
      expect(next.mini, isTrue);
      expect(next.volume, 40.0);
      expect(next.rate, 1.0);
      expect(next.videoAspect, s.videoAspect);
      expect(next.controllerEpoch, 0);
    });
  });
}
