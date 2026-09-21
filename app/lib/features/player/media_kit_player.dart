import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_player_port.dart';

/// Windows / Linux / macOS 桌面端的音频后端，基于 `package:media_kit`（libmpv）。
///
/// 为什么不用 `just_audio_windows`：
/// * 它不支持自定义请求头，而播放地址需要带 Referer/UA；
/// * 0.2.3 的 C++/WinRT 依赖已被 MSVC 14.4x+ 判为硬错误，要额外打 CMake 补丁；
/// * 进程内**第一次**播放会静默失败（playing=true 但进度恒为 0）。
///
/// 与 [JustAudioPlayerImpl] 的差异：
/// * `setVolume` 量纲不同 —— media_kit 是 0–100，端口是 0.0–1.0；
/// * media_kit 的 `open()` 默认自动起播，这里统一用 `play: false` 再手动 play，
///   以便复刻端口「先确认音源可加载、再起播」的顺序。
class MediaKitPlayerImpl implements AudioPlayerPort {
  MediaKitPlayerImpl({Player? player}) : _player = player ?? Player() {
    _errorSub = _player.stream.error.listen((message) {
      if (_loadingSource) return;
      _lastError = message;
      _completion.add(PlayerIdleReason.error);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (_loadingSource || !done) return;
      _completion.add(PlayerIdleReason.completed);
    });
  }

  final Player _player;
  final _completion = StreamController<PlayerIdleReason>.broadcast();
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  bool _loadingSource = false;
  bool _expectingAudio = false;

  /// 最近一次来自 libmpv 的错误信息，供上层拼提示。
  String get lastError => _lastError;
  String _lastError = '';

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get bufferedPositionStream => _player.stream.buffer;

  @override
  Stream<Duration?> get durationStream =>
      _player.stream.duration.map((d) => d > Duration.zero ? d : null);

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<PlayerIdleReason> get completionStream => _completion.stream;

  @override
  Future<void> playUrl(String url, {Map<String, String>? headers}) async {
    _loadingSource = true;
    _expectingAudio = false;
    _lastError = '';
    // 换源必须先停：libmpv 直接 open 会沿用上一首的播放状态。
    await _player.stop();
    _expectingAudio = true;

    try {
      await _player.open(
        Media(url, httpHeaders: headers),
        play: false,
      );

      // 时长要等 demuxer 读完头才有；等不到也不算致命（渐进流可能只是慢）。
      var duration = _player.state.duration;
      if (duration <= Duration.zero) {
        try {
          duration = await _player.stream.duration
              .firstWhere((d) => d > Duration.zero)
              .timeout(const Duration(seconds: 6));
        } on TimeoutException {
          // 放行，交给下面的 playing 判定。
        }
      }
    } catch (e) {
      _expectingAudio = false;
      _loadingSource = false;
      rethrow;
    }

    _loadingSource = false;
    unawaited(
      _player.play().catchError((Object e) {
        if (_expectingAudio) {
          _lastError = '$e';
          _completion.add(PlayerIdleReason.error);
        }
      }),
    );
    try {
      await _player.stream.playing
          .firstWhere((playing) => playing)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _expectingAudio = false;
      throw StateError('音频源无法起播: ${_host(url)}');
    }
    _expectingAudio = false;
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
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  /// 端口量纲是 0.0–1.0，media_kit 是 0–100。
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume.clamp(0.0, 1.0)) * 100);

  @override
  Future<void> dispose() async {
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    await _completion.close();
    await _player.dispose();
  }
}
