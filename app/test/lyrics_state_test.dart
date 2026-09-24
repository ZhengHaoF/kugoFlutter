import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

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

String _key(String id) => musicIdentity(MusicPlatform.kugou, id);

ProviderContainer _container({
  required FakeAudioPlayer engine,
  required FakeMusicSource source,
}) {
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: engine, source: source),
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
    final source = FakeMusicSource()
      ..lyricsByKey[_key('a')] = [const LyricLine(timeMs: 0, text: 'hello')]
      ..nextPlayUrl = null
      ..playError = Exception('offline');
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    final track = _hashed('a', 'hash_a');
    await controller.playQueue([track], startIndex: 0);

    final state = container.read(playerControllerProvider);
    expect(source.requestedLyricKeys, contains(_key('a')));
    expect(state.lyricsStatus, LyricsStatus.ready);
    expect(state.lyrics.single.text, 'hello');
    expect(state.isPlaying, isFalse);
  });

  test('next() requests lyrics for the new track', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource()
      ..lyricsByKey[_key('a')] = [const LyricLine(timeMs: 0, text: 'lyric-a')]
      ..lyricsByKey[_key('b')] = [const LyricLine(timeMs: 0, text: 'lyric-b')];
    final container = _container(engine: engine, source: source);
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
    expect(source.requestedLyricKeys, contains(_key('b')));
    expect(state.lyrics.single.text, 'lyric-b');
    expect(state.lyricsStatus, LyricsStatus.ready);
  });

  test('demo track without hash marks lyrics empty without fetching', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource();
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_demo('d1')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(source.requestedLyricKeys, isEmpty);
    expect(state.lyricsStatus, LyricsStatus.empty);
    expect(state.lyrics, isEmpty);
  });

  test('empty lyric payload becomes empty status, not stuck loading', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource();
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('z', 'hash_z')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(state.lyricsStatus, LyricsStatus.empty);
    expect(state.lyrics, isEmpty);
  });

  test('ensureLyricsForCurrent dedupes after a definitive answer', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource()
      ..lyricsByKey[_key('a')] = [const LyricLine(timeMs: 0, text: 'once')];
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('a', 'hash_a')], startIndex: 0);
    expect(source.requestedLyricKeys.length, 1);

    controller.ensureLyricsForCurrent();
    controller.ensureLyricsForCurrent();
    await Future<void>.delayed(Duration.zero);
    expect(source.requestedLyricKeys.length, 1);
  });

  test('stale lyric result is dropped when track already advanced', () async {
    final engine = FakeAudioPlayer();
    final gate = Completer<void>();
    final source = FakeMusicSource()
      ..lyricsByKey[_key('a')] = [const LyricLine(timeMs: 0, text: 'slow-a')]
      ..lyricsByKey[_key('b')] = [const LyricLine(timeMs: 0, text: 'fast-b')]
      ..lyricGate = gate.future;
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    final first = controller.playQueue(
      [_hashed('a', 'hash_a'), _hashed('b', 'hash_b')],
      startIndex: 0,
    );
    final second = controller.next();
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
    final source = FakeMusicSource()
      ..lyricsByKey[_key('h')] = [const LyricLine(timeMs: 100, text: 'still here')]
      ..nextPlayUrl = null
      ..playError = Exception('VIP/防盗链');
    final container = _container(engine: engine, source: source);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_hashed('h', 'hash_h')], startIndex: 0);
    final state = container.read(playerControllerProvider);
    expect(state.lyrics.single.text, 'still here');
    expect(state.lyricsStatus, LyricsStatus.ready);
    expect(state.display, PlayerDisplayState.error);
  });
}
