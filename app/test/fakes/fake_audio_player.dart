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

  /// 引擎当前倍速（镜像真实引擎：playUrl 加载时应用，setSpeed 立即应用）。
  double speed = 1.0;

  /// 最近一次 setSpeed 入参（controller 直改倍速时断言）。
  double? lastSpeed;

  /// 最近一次 playUrl 收到的倍速（切歌/换流重放时断言）。
  double? lastPlaySpeed;

  /// 起播瞬间引擎已生效的倍速。真实引擎必须在出声前应用倍速
  /// （media_kit 在 open() 与 play() 之间 setRate），这是回归锚点。
  double? speedWhenPlaybackStarted;

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
  Future<void> playUrl(
    String url, {
    Map<String, String>? headers,
    bool play = true,
    double speed = 1.0,
  }) async {
    lastUrl = url;
    lastPlaySpeed = speed;
    // Real engines apply the rate during the load (media_kit: between open()
    // and its internal play()), so mirror that here.
    this.speed = speed;
    // Real engines reset the cursor when a new source is set.
    position = Duration.zero;
    playing = play;
    if (play) speedWhenPlaybackStarted = speed;
    _playing.add(play);
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
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
    lastSpeed = speed;
  }

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
