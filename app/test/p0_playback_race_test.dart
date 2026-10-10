import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'fixture',
  album: 'fixture',
  coverUrl: 'https://example.invalid/$id.jpg',
  durationMs: 180000,
  hash: 'hash-$id',
  availableQualities: const {AppQuality.standard},
);

class _Source extends FakeMusicSource {
  @override
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  }) async => PlayUrlResult(
    url: '${track.id}-primary',
    backupUrls: track.id == 'A' ? ['A-backup'] : [],
  );
}

class _DelayedEngine extends FakeAudioPlayer {
  final entered = Completer<void>();
  final release = Completer<void>();
  final calls = <String>[];
  bool failA = false;
  int concurrent = 0;
  int maxConcurrent = 0;

  @override
  Future<void> playUrl(String url, {Map<String, String>? headers}) async {
    calls.add(url);
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      if (url == 'A-primary') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        if (failA) throw StateError('fixture load failure');
      }
      await super.playUrl(url, headers: headers);
    } finally {
      concurrent--;
    }
  }
}

ProviderContainer _container(_DelayedEngine engine, FakeMusicSource source) {
  final c = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: engine, source: source),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first load works when controller was created in FakeAsync', (
    tester,
  ) async {
    final e = _DelayedEngine();
    final c = _container(e, _Source());
    final p = c.read(playerControllerProvider.notifier);
    await tester.runAsync(() => p.playQueue([_track('B')]));
    await tester.pump();
    expect(e.lastUrl, 'B-primary');
    expect(
      c.read(playerControllerProvider).display,
      PlayerDisplayState.playing,
    );
  });

  for (final failOld in [false, true]) {
    test(
      'R02 obsolete A ${failOld ? 'failure' : 'success'} cannot replace B',
      () async {
        final e = _DelayedEngine()..failA = failOld;
        final c = _container(e, _Source());
        final p = c.read(playerControllerProvider.notifier);
        final a = p.playQueue([_track('A')]);
        await e.entered.future;
        final b = p.playQueue([_track('B')]);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(playerControllerProvider).current!.id, 'B');
        expect(
          c.read(playerControllerProvider).display,
          PlayerDisplayState.loading,
        );
        expect(e.calls, ['A-primary']);
        e.release.complete();
        await Future.wait([a, b]);
        expect(e.lastUrl, 'B-primary');
        expect(e.calls, ['A-primary', 'B-primary']);
        expect(e.maxConcurrent, 1);
        expect(
          c.read(playerControllerProvider).display,
          PlayerDisplayState.playing,
        );
      },
    );
  }

  test('R02 obsolete queued B is skipped when C arrives', () async {
    final e = _DelayedEngine();
    final c = _container(e, _Source());
    final p = c.read(playerControllerProvider.notifier);
    final a = p.playQueue([_track('A')]);
    await e.entered.future;
    final b = p.playQueue([_track('B')]);
    await Future<void>.delayed(Duration.zero);
    final third = p.playQueue([_track('C')]);
    await Future<void>.delayed(Duration.zero);
    e.release.complete();
    await Future.wait([a, b, third]);
    expect(e.calls, ['A-primary', 'C-primary']);
    expect(e.lastUrl, 'C-primary');
    expect(c.read(playerControllerProvider).current!.id, 'C');
  });

  test(
    'current A can still use backup and does not poison next load',
    () async {
      final e = _DelayedEngine()..failA = true;
      final c = _container(e, _Source());
      final p = c.read(playerControllerProvider.notifier);
      final a = p.playQueue([_track('A')]);
      await e.entered.future;
      e.release.complete();
      await a;
      expect(e.calls, ['A-primary', 'A-backup']);
      await p.playQueue([_track('B')]);
      expect(e.lastUrl, 'B-primary');
    },
  );

  test('stop invalidates in-flight source and leaves engine paused', () async {
    final e = _DelayedEngine();
    final c = _container(e, _Source());
    final p = c.read(playerControllerProvider.notifier);
    final load = p.playQueue([_track('A')]);
    await e.entered.future;
    await p.stopPlayback();
    e.release.complete();
    await load;
    expect(c.read(playerControllerProvider).display, PlayerDisplayState.idle);
    expect(e.playing, false);
    expect(e.calls, ['A-primary']);
  });

  test('stop invalidates resolver before native loading begins', () async {
    final gate = Completer<void>();
    final source = FakeMusicSource()..playGate = gate.future;
    final e = _DelayedEngine();
    final c = _container(e, source);
    final p = c.read(playerControllerProvider.notifier);
    final load = p.playQueue([_track('B')]);
    await Future<void>.delayed(Duration.zero);
    await p.stopPlayback();
    gate.complete();
    await load;
    expect(e.calls, isEmpty);
    expect(c.read(playerControllerProvider).display, PlayerDisplayState.idle);
  });

  test(
    'dispose drops late native failure without accessing provider state',
    () async {
      final e = _DelayedEngine()..failA = true;
      final c = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: e, source: _Source()),
          ),
        ],
      );
      final p = c.read(playerControllerProvider.notifier);
      final load = p.playQueue([_track('A')]);
      await e.entered.future;
      c.dispose();
      e.release.complete();
      await load;
      expect(e.calls, ['A-primary']);
    },
  );
}
