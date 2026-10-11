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
  ///
  /// [speed] is the playback rate to apply as part of the load. Engines must
  /// apply it *before* audio starts: media_kit's `open()` resets the mpv rate,
  /// and its `playUrl` starts playback internally, so a rate set by the caller
  /// after this returns would be audible for a moment at 1.0x.
  Future<void> playUrl(
    String url, {
    Map<String, String>? headers,
    bool play = true,
    double speed = 1.0,
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
