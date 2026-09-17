import 'package:audio_service/audio_service.dart';

import '../../core/models/track.dart';
import 'player_controller.dart';

/// System media notification / lock screen handler.
class KugoAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler
    implements KugoMediaBridge {
  KugoAudioHandler(this._controller) {
    playbackState.add(
      PlaybackState(
        controls: _controls(playing: false),
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  final PlayerController _controller;

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
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        controls: _controls(playing: false),
      ),
    );
  }

  @override
  void sync({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
    Track? track,
  }) {
    if (track != null) {
      mediaItem.add(
        MediaItem(
          id: track.hash.isEmpty ? track.id : track.hash,
          title: track.name,
          artist: track.artist,
          album: track.album,
          duration: Duration(milliseconds: track.durationMs),
          artUri: Uri.tryParse(track.coverUrl),
        ),
      );
    }
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        processingState: processing,
        updatePosition: position,
        controls: _controls(playing: playing),
      ),
    );
  }

  @override
  void updatePosition(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(updatePosition: position),
    );
  }

  List<MediaControl> _controls({required bool playing}) => [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ];
}
