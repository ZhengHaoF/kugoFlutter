/// Platform-agnostic audio engine port.
abstract class AudioPlayerPort {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Stream<PlayerIdleReason> get completionStream;

  Future<void> playUrl(String url, {Map<String, String>? headers});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

enum PlayerIdleReason { completed, error, stopped }
