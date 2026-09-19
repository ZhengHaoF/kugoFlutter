import 'dart:async';

import 'package:kugo/features/player/audio_player_port.dart';

class FakeAudioPlayer implements AudioPlayerPort {
  final _pos = StreamController<Duration>.broadcast();
  final _buffered = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _complete = StreamController<PlayerIdleReason>.broadcast();
  Duration position = Duration.zero;
  String? lastUrl;
  bool playing = false;

  @override
  Stream<Duration> get positionStream => _pos.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _buffered.stream;

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<PlayerIdleReason> get completionStream => _complete.stream;

  @override
  Future<void> playUrl(String url, {Map<String, String>? headers}) async {
    lastUrl = url;
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> play() async {
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
    _pos.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _pos.close();
    await _buffered.close();
    await _playing.close();
    await _complete.close();
  }

  void emitCompleted() => _complete.add(PlayerIdleReason.completed);

  /// Simulate the engine's position stream ticking (just_audio emits ~5/s).
  void emitPosition(Duration position) {
    this.position = position;
    _pos.add(position);
  }
}
