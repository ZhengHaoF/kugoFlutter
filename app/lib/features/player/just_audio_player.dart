import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'audio_player_port.dart';

class JustAudioPlayerImpl implements AudioPlayerPort {
  JustAudioPlayerImpl({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    _completionSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _completion.add(PlayerIdleReason.completed);
      }
    });
    _player.playbackEventStream.listen((_) {}, onError: (_) {
      _completion.add(PlayerIdleReason.error);
    });
  }

  final AudioPlayer _player;
  final _completion = StreamController<PlayerIdleReason>.broadcast();
  StreamSubscription<ProcessingState>? _completionSub;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<PlayerIdleReason> get completionStream => _completion.stream;

  @override
  Future<void> playUrl(String url, {Map<String, String>? headers}) async {
    await _player.stop();
    if (headers != null && headers.isNotEmpty) {
      await _player.setUrl(url, headers: headers);
    } else {
      await _player.setUrl(url);
    }
    await _player.play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() async {
    await _completionSub?.cancel();
    await _completion.close();
    await _player.dispose();
  }
}
