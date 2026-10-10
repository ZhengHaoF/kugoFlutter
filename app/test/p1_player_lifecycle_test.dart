import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/storage/playback_position_store.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _track(String id, {MusicPlatform platform = MusicPlatform.kugou}) =>
    Track(
      id: id,
      name: id,
      artist: 'fixture',
      album: '',
      coverUrl: 'https://example.invalid/$id.jpg',
      durationMs: 180000,
      hash: 'hash-$id',
      platform: platform,
      availableQualities: const {AppQuality.standard},
    );

class _CatalogSource extends FakeMusicSource {
  Completer<({List<RelateGood> goods, bool catalogComplete})?>? catalogGate;

  @override
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchQualityCatalog(
    Track track,
  ) async => catalogGate?.future ?? super.fetchQualityCatalog(track);
}

class _Engine extends FakeAudioPlayer {
  final autoplay = <bool>[];
  final seeks = <int>[];
  Completer<void>? seekGate;
  Completer<void>? seekEntered;
  bool failLoad = false;

  @override
  Future<void> playUrl(
    String url, {
    Map<String, String>? headers,
    bool play = true,
  }) async {
    autoplay.add(play);
    if (failLoad) throw StateError('fixture load failure');
    await super.playUrl(url, headers: headers, play: play);
  }

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value.inMilliseconds);
    final entered = seekEntered;
    if (entered != null && !entered.isCompleted) entered.complete();
    await seekGate?.future;
    await super.seek(value);
  }
}

(ProviderContainer, PlayerController) _boot(
  _Engine engine,
  FakeMusicSource source,
) {
  final c = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: engine, source: source),
      ),
    ],
  );
  addTearDown(c.dispose);
  return (c, c.read(playerControllerProvider.notifier));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final sameIdOtherPlatform in [false, true]) {
    test(
      'R03 stale catalog cannot replace new track (cross-source=$sameIdOtherPlatform)',
      () async {
        final source = _CatalogSource();
        final (c, player) = _boot(_Engine(), source);
        await player.playQueue([_track('42')]);
        source.catalogGate = Completer();
        final pending = player.ensureCurrentQualities(forceRefresh: true);
        await player.playQueue([
          _track(
            sameIdOtherPlatform ? '42' : 'B',
            platform: sameIdOtherPlatform
                ? MusicPlatform.netease
                : MusicPlatform.kugou,
          ),
        ]);
        source.catalogGate!.complete((
          goods: const [RelateGood(hash: 'obsolete', quality: 'flac')],
          catalogComplete: true,
        ));
        expect(await pending, isEmpty);
        expect(c.read(playerControllerProvider).current!.relateGoods, isEmpty);
        expect(
          c.read(playerControllerProvider).current!.platform,
          sameIdOtherPlatform ? MusicPlatform.netease : MusicPlatform.kugou,
        );
      },
    );
  }

  test('R03 catalog is stale after same-track reload generation', () async {
    final source = _CatalogSource();
    final (c, player) = _boot(_Engine(), source);
    await player.playQueue([_track('A')]);
    source.catalogGate = Completer();
    final pending = player.ensureCurrentQualities(forceRefresh: true);
    await player.reloadCurrent();
    source.catalogGate!.complete((
      goods: const [RelateGood(hash: 'old', quality: 'flac')],
      catalogComplete: true,
    ));
    expect(await pending, isEmpty);
    expect(c.read(playerControllerProvider).current!.relateGoods, isEmpty);
  });

  for (final paused in [false, true]) {
    for (final positionMs in [0, 45000]) {
      test('R04 quality preserves paused=$paused at $positionMs ms', () async {
        final engine = _Engine();
        final (c, player) = _boot(engine, FakeMusicSource());
        await player.playQueue([_track('A')]);
        player.seekTo(positionMs);
        await Future<void>.delayed(Duration.zero);
        if (paused) player.togglePlay();
        await player.applyQuality(AppQuality.sq);
        expect(engine.autoplay.last, isFalse);
        expect(engine.position.inMilliseconds, positionMs);
        expect(player.position.value, positionMs);
        expect(c.read(playerControllerProvider).positionMs, positionMs);
        expect(c.read(playerControllerProvider).isPlaying, !paused);
        expect(engine.playing, !paused);
      });
    }
  }

  test('R04 user pause during quality resolution wins', () async {
    final engine = _Engine();
    final source = FakeMusicSource();
    final (c, player) = _boot(engine, source);
    await player.playQueue([_track('A')]);
    player.seekTo(45000);
    final gate = Completer<void>();
    source.playGate = gate.future;
    final quality = player.applyQuality(AppQuality.hq);
    await Future<void>.delayed(Duration.zero);
    // Public play/pause while loading represents current user intent.
    player.togglePlay();
    gate.complete();
    await quality;
    expect(c.read(playerControllerProvider).display, PlayerDisplayState.paused);
    expect(engine.autoplay.last, isFalse);
    expect(engine.playing, isFalse);
  });

  test(
    'R04 old in-flight quality seek settles before new native source',
    () async {
      final engine = _Engine();
      final source = FakeMusicSource();
      final (c, player) = _boot(engine, source);
      await player.playQueue([_track('A')]);
      player.seekTo(45000);
      await Future<void>.delayed(Duration.zero);
      engine.seekEntered = Completer();
      engine.seekGate = Completer();
      final quality = player.applyQuality(AppQuality.sq);
      await engine.seekEntered!.future;
      source.nextPlayUrl = const PlayUrlResult(
        url: 'https://example.invalid/B',
      );
      final newSong = player.playQueue([_track('B')]);
      expect(engine.lastUrl, isNot(endsWith('/B')));
      engine.seekGate!.complete();
      await Future.wait([quality, newSong]);
      expect(c.read(playerControllerProvider).current!.id, 'B');
      expect(engine.lastUrl, endsWith('/B'));
      expect(engine.position, Duration.zero);
      expect(player.position.value, 0);
    },
  );

  test(
    'R03 current catalog patches metadata and keeps track duration',
    () async {
      final source = _CatalogSource()
        ..qualityCatalog = (
          goods: const [RelateGood(hash: 'new', quality: 'flac')],
          catalogComplete: true,
        );
      final (c, player) = _boot(_Engine(), source);
      await player.playQueue([_track('A')]);
      expect(
        await player.ensureCurrentQualities(forceRefresh: true),
        contains(AppQuality.sq),
      );
      expect(
        c.read(playerControllerProvider).current!.qualityCatalogComplete,
        isTrue,
      );
      expect(c.read(playerControllerProvider).current!.durationMs, 180000);
    },
  );

  test(
    'R12 first successful play saves periodically without pause/resume',
    () async {
      final engine = _Engine();
      final (c, player) = _boot(engine, FakeMusicSource());
      await player.playQueue([_track('A')]);
      engine.emitPosition(const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 4200));
      expect(await PlaybackPositionStore.load('kugou:A'), 12000);
      expect(c.read(playerControllerProvider).isPlaying, isTrue);
    },
  );

  test(
    'R04 failed paused quality reload does not auto-play the next song',
    () async {
      final engine = _Engine();
      final (c, player) = _boot(engine, FakeMusicSource());
      await player.playQueue([_track('A'), _track('B')]);
      player.togglePlay();
      engine.failLoad = true;
      await player.applyQuality(AppQuality.sq);
      expect(c.read(playerControllerProvider).current!.id, 'A');
      expect(
        c.read(playerControllerProvider).display,
        PlayerDisplayState.error,
      );
      expect(engine.playing, isFalse);
    },
  );

  test(
    'R12 stopped playback does not overwrite saved cursor periodically',
    () async {
      final engine = _Engine();
      final (c, player) = _boot(engine, FakeMusicSource());
      await player.playQueue([_track('A')]);
      engine.emitPosition(const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 4200));
      await player.stopPlayback();
      await Future<void>.delayed(const Duration(milliseconds: 4200));
      expect(await PlaybackPositionStore.load('kugou:A'), 12000);
    },
  );
}
