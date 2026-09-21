import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/play_repository.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_lyric_play_repos.dart';

Track _hashed(String id, String hash) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'https://example.com/$id.jpg',
      durationMs: 10000,
      hash: hash,
    );

Track _demo(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 10000,
    );

ProviderContainer _container({
  required FakeAudioPlayer engine,
  required FakeLyricRepository lyrics,
  required PlayRepository play,
}) {
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(
          engine: engine,
          lyricRepo: lyrics,
          playRepo: play,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('playQueue loads lyrics for hashed track even if play resolve fails',
      () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository()
      ..byKey['a|hash_a'] = [const LyricLine(timeMs: 0, text: 'hello')];
    final play = FakePlayRepository()..nextResolved = null;
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    final track = _hashed('a', 'hash_a');
    await controller.playQueue([track], startIndex: 0);

    final state = container.read(playerControllerProvider);
    expect(lyrics.requestedKeys, contains('a|hash_a'));
    expect(state.lyricsStatus, LyricsStatus.ready);
    expect(state.lyrics.single.text, 'hello');
    // Play failed offline — must not invent playback, but lyrics still arrived.
    expect(state.isPlaying, isFalse);
  });

  test('next() requests lyrics for the new track', () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository()
      ..byKey['a|hash_a'] = [const LyricLine(timeMs: 0, text: 'lyric-a')]
      ..byKey['b|hash_b'] = [const LyricLine(timeMs: 0, text: 'lyric-b')];
    final play = FakePlayRepository();
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue(
      [_hashed('a', 'hash_a'), _hashed('b', 'hash_b')],
      startIndex: 0,
    );
    expect(
      container.read(playerControllerProvider).lyrics.single.text,
      'lyric-a',
    );

    await controller.next();
    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'b');
    expect(lyrics.requestedKeys, contains('b|hash_b'));
    expect(state.lyrics.single.text, 'lyric-b');
    expect(state.lyricsStatus, LyricsStatus.ready);
  });

  test('demo track without hash marks lyrics empty without fetching', () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository();
    final play = FakePlayRepository();
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_demo('d1')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(lyrics.requestedKeys, isEmpty);
    expect(state.lyricsStatus, LyricsStatus.empty);
    expect(state.lyrics, isEmpty);
  });

  test('empty lyric payload becomes empty status, not stuck loading', () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository(); // no mapping → empty list
    final play = FakePlayRepository();
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('z', 'hash_z')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(state.lyricsStatus, LyricsStatus.empty);
    expect(state.lyrics, isEmpty);
  });

  test('ensureLyricsForCurrent dedupes after a definitive answer', () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository()
      ..byKey['a|hash_a'] = [const LyricLine(timeMs: 0, text: 'once')];
    final play = FakePlayRepository();
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('a', 'hash_a')], startIndex: 0);
    expect(lyrics.requestedKeys.length, 1);

    controller.ensureLyricsForCurrent();
    controller.ensureLyricsForCurrent();
    await Future<void>.delayed(Duration.zero);
    expect(lyrics.requestedKeys.length, 1);
  });

  test('stale lyric result is dropped when track already advanced', () async {
    final engine = FakeAudioPlayer();
    final gate = Completer<void>();
    final lyrics = FakeLyricRepository()
      ..byKey['a|hash_a'] = [const LyricLine(timeMs: 0, text: 'slow-a')]
      ..byKey['b|hash_b'] = [const LyricLine(timeMs: 0, text: 'fast-b')]
      ..gate = gate.future;
    final play = FakePlayRepository();
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    final first = controller.playQueue(
      [_hashed('a', 'hash_a'), _hashed('b', 'hash_b')],
      startIndex: 0,
    );
    // Switch away while A's lyric fetch is still gated.
    final second = controller.next();
    // Allow B's ensure to start; both fetches await the same gate.
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([first, second]);

    final state = container.read(playerControllerProvider);
    expect(state.current?.id, 'b');
    expect(state.lyrics.single.text, 'fast-b');
  });

  test('play-resolve failure path still surfaces lyrics for current track',
      () async {
    final engine = FakeAudioPlayer();
    final lyrics = FakeLyricRepository()
      ..byKey['h|hash_h'] = [const LyricLine(timeMs: 100, text: 'still here')];
    final play = FakePlayRepository()
      ..nextResolved = null
      ..errorText = 'VIP/防盗链';
    final container = _container(engine: engine, lyrics: lyrics, play: play);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('h', 'hash_h')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(state.lyrics.single.text, 'still here');
    expect(state.lyricsStatus, LyricsStatus.ready);
    expect(state.display, PlayerDisplayState.error);
  });
}
