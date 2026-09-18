import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'audio_player_port.dart';

class JustAudioPlayerImpl implements AudioPlayerPort {
  JustAudioPlayerImpl({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    _completionSub = _player.processingStateStream.listen((state) {
      // Source swap (stop/setUrl) parks in idle — not a load failure.
      if (_loadingSource) return;
      if (state == ProcessingState.completed) {
        _completion.add(PlayerIdleReason.completed);
      } else if (state == ProcessingState.idle) {
        // load failed often parks in idle — only signal if we expected audio
        if (_expectingAudio) {
          _completion.add(PlayerIdleReason.error);
        }
      }
    });
    _player.playbackEventStream.listen((_) {}, onError: (Object e) {
      if (_loadingSource) return;
      _completion.add(PlayerIdleReason.error);
    });
  }

  final AudioPlayer _player;
  final _completion = StreamController<PlayerIdleReason>.broadcast();
  StreamSubscription<ProcessingState>? _completionSub;
  bool _expectingAudio = false;
  bool _loadingSource = false;

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
    _loadingSource = true;
    // Intentional stop must not surface as a load error / auto-next.
    _expectingAudio = false;
    await _player.stop();
    _expectingAudio = true;
    try {
      if (headers != null && headers.isNotEmpty) {
        await _player.setUrl(url, headers: headers);
      } else {
        await _player.setUrl(url);
      }
    } catch (e) {
      _expectingAudio = false;
      _loadingSource = false;
      rethrow;
    }

    // Some hosts report duration only after buffering starts.
    var duration = _player.duration;
    if (duration == null || duration <= Duration.zero) {
      try {
        duration = await _player.durationStream
            .firstWhere((d) => d != null && d > Duration.zero)
            .timeout(const Duration(seconds: 6));
      } on TimeoutException {
        // Proceed anyway — progressive stream may still produce audio.
        // Only fail if processing state is clearly idle/error.
        final st = _player.processingState;
        if (st == ProcessingState.idle || st == ProcessingState.completed) {
          _expectingAudio = false;
          _loadingSource = false;
          throw StateError('音频源无法加载: ${_host(url)}');
        }
      } on Exception {
        _expectingAudio = false;
        _loadingSource = false;
        rethrow;
      }
    }

    await _player.play();
    _expectingAudio = false;
    _loadingSource = false;
  }

  String _host(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() {
    _expectingAudio = false;
    _loadingSource = false;
    return _player.stop();
  }

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
