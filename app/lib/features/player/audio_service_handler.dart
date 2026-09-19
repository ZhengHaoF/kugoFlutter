import 'package:audio_service/audio_service.dart';

import '../../core/models/track.dart';
import 'player_controller.dart';

/// System media notification / lock screen / Bluetooth (AVRCP) handler.
///
/// How the pieces map onto a car head unit:
/// * total duration  -> [MediaItem.duration] (media metadata)
/// * elapsed / bar   -> [PlaybackState.updatePosition] (MediaSession snapshot)
///
/// The platform does **not** extrapolate that position for us, and Android's
/// AVRCP target permanently stops sending `EVENT_PLAYBACK_POS_CHANGED` once two
/// consecutive reads return the same value. [PlayerController] therefore pushes
/// a fresh, monotonically increasing position on a steady tick.
///
/// Seek-related [systemActions] must also be declared or many head units never
/// show / refresh the position bar even when duration is present.
class KugoAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements KugoMediaBridge {
  KugoAudioHandler(this._controller) {
    _broadcast(
      playing: false,
      processing: AudioProcessingState.idle,
      position: Duration.zero,
    );
  }

  /// Enables notification/lock-screen seek bar and MediaSession ACTION_SEEK_TO
  /// (required by audio_service; not auto-enabled on Android).
  static const _systemActions = {
    MediaAction.seek,
    MediaAction.seekForward,
    MediaAction.seekBackward,
  };

  final PlayerController _controller;

  /// Last buffered position reported by the engine. Some head units (and the
  /// Android notification progress bar) read this as a secondary bar.
  Duration _bufferedPosition = Duration.zero;

  @override
  Future<void> play() async {
    if (!_controller.snapshot.isPlaying) _controller.togglePlay();
  }

  @override
  Future<void> pause() async {
    if (_controller.snapshot.isPlaying) _controller.togglePlay();
  }

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.previous();

  @override
  Future<void> seek(Duration position) {
    _controller.seekTo(position.inMilliseconds);
    return Future.value();
  }

  @override
  Future<void> stop() async {
    if (_controller.snapshot.isPlaying) _controller.togglePlay();
    final prev = playbackState.value;
    _broadcast(
      playing: false,
      processing: AudioProcessingState.idle,
      position: prev.updatePosition,
    );
  }

  @override
  void sync({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
    Duration bufferedPosition = Duration.zero,
    Track? track,
    String? subtitle,
  }) {
    _bufferedPosition = bufferedPosition;
    if (track != null) {
      mediaItem.add(_mediaItemFor(track, subtitle));
    }
    _broadcast(playing: playing, processing: processing, position: position);
  }

  @override
  void updatePosition(Duration position, {Duration? bufferedPosition}) {
    if (bufferedPosition != null) _bufferedPosition = bufferedPosition;
    final prev = playbackState.value;
    _broadcast(
      playing: prev.playing,
      processing: prev.processingState,
      position: position,
    );
  }

  @override
  void syncQueue(List<Track> tracks, int currentIndex) {
    queue.add([for (final track in tracks) _mediaItemFor(track, null)]);
  }

  @override
  void updateMediaSubtitle(String subtitle) {
    final track = _controller.snapshot.current;
    if (track == null) return;
    mediaItem.add(_mediaItemFor(track, subtitle));
  }

  MediaItem _mediaItemFor(Track track, String? subtitle) {
    final secondary =
        (subtitle == null || subtitle.isEmpty) ? track.artist : subtitle;
    return MediaItem(
      id: track.hash.isEmpty ? track.id : track.hash,
      title: track.name,
      artist: secondary,
      displaySubtitle: secondary,
      album: track.album,
      duration: Duration(milliseconds: track.durationMs),
      artUri: Uri.tryParse(track.coverUrl),
    );
  }

  void _broadcast({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
  }) {
    final ready = processing == AudioProcessingState.ready;
    playbackState.add(
      PlaybackState(
        controls: _controls(playing: playing),
        systemActions: _systemActions,
        // Compact view (notification collapsed / some head units) shows
        // prev, play-pause, next.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: position,
        bufferedPosition: _bufferedPosition,
        // MediaSession / AVRCP project progress as
        // position + speed * (now - updateTime). Keep speed non-zero only
        // while actually playing so a paused track does not creep forward.
        speed: (playing && ready) ? 1.0 : 0.0,
        queueIndex: _controller.snapshot.queue.isEmpty
            ? null
            : _controller.snapshot.currentIndex,
      ),
    );
  }

  List<MediaControl> _controls({required bool playing}) => [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ];
}
