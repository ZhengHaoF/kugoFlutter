/// Platform-agnostic audio engine port.
abstract class AudioPlayerPort {
  Stream<Duration> get positionStream;

  /// Buffered (downloaded) position — the system seek bar / car head unit can
  /// render this as a secondary bar.
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Stream<PlayerIdleReason> get completionStream;

  /// Load a source without audible playback when [play] is false.
  Future<void> playUrl(
    String url, {
    Map<String, String>? headers,
    bool play = true,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

enum PlayerIdleReason { completed, error, stopped }
