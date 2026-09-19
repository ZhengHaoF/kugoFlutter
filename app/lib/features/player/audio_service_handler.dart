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
  KugoAudioHandler(this._controller);

  /// Enables notification/lock-screen seek bar and MediaSession ACTION_SEEK_TO
  /// (required by audio_service; not auto-enabled on Android).
  ///
  /// Also keep the raw transport actions here: a head unit that has dropped its
  /// transport slot (the carousel bug below) falls back to the session action
  /// list to build *any* UI at all, so this must never be empty.
  static const _systemActions = {
    MediaAction.seek,
    MediaAction.seekForward,
    MediaAction.seekBackward,
    MediaAction.play,
    MediaAction.pause,
    MediaAction.playPause,
    MediaAction.skipToNext,
    MediaAction.skipToPrevious,
    MediaAction.stop,
  };

  /// AVRCP carousel-action ids that audio_service encodes as `2 * index + 1`.
  ///
  /// Duplicated here instead of imported because they are `@visibleForTesting`
  /// in the plugin and only the numeric value is contractual. The ids line up
  /// with `PlaybackStateCompat.toKeyCode()`: ACTION_PAUSE=127 -> 5,
  /// ACTION_PLAY=126 -> 1, ACTION_SKIP_TO_NEXT=87 -> 9,
  /// ACTION_SKIP_TO_PREVIOUS=88 -> 11.
  static const _avrcpPlay = 1;
  static const _avrcpPause = 5;
  static const _avrcpNext = 9;
  static const _avrcpPrevious = 11;

  /// Fixed capacity of the notification / AVRCP action carousel.
  ///
  /// audio_service supports at most 3 action slots and all head units index the
  /// carousel positionally, so the layout must never change shape at runtime.
  /// Emitting a different number of controls on every play/pause used to
  /// desynchronise the car's cached list — after which the head unit no longer
  /// matched `Play`/`Pause` to an index, and media commands (and with them the
  /// position notifications the progress bar needs) stopped arriving.
  static const _compactIndices = [0, 1, 2];

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
    // Full teardown: pause the engine *and* drop back to idle. Merely pausing
    // would leave audio running behind a stopped session.
    await _controller.stopPlayback();
    _broadcast(
      playing: false,
      processing: AudioProcessingState.idle,
      position: Duration.zero,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // The OS is tearing the app down; release audio rather than leaving a
    // foreground playback service that no UI can control any more.
    await _controller.stopPlayback();
  }

  /// Notification swiped away.
  ///
  /// Must NOT delegate to [stop]: `BaseAudioHandler.stop()` moves the session to
  /// idle, and audio_service then sends `stopService`, whose native side calls
  /// `deactivateMediaSession()` *and* `stopSelf()` — tearing the service down for
  /// good. The framework reuses the same service (and the same
  /// `KugoAudioHandler`) for the next `play()`, so a swipe would leave every
  /// later session dead: no notification, no AVRCP, no progress bar. Just pause
  /// and drop the notification instead.
  @override
  Future<void> onNotificationDeleted() async {
    await _controller.stopPlayback();
    _broadcast(
      playing: false,
      processing: AudioProcessingState.idle,
      position: Duration.zero,
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
    final wasPlaying = playbackState.value.playing;
    _broadcast(playing: playing, processing: processing, position: position);
    if (wasPlaying != playing) _reannounceCarousel();
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
    // Guard against a zero/overshoot buffered value: a position outside
    // (0, duration) makes the MediaSession seek bar unsupported on some
    // Android builds, which cancels the progress line entirely.
    final duration = mediaItem.value?.duration;
    var buffered = _bufferedPosition;
    if (buffered <= Duration.zero) {
      buffered = Duration.zero;
    } else if (duration != null && duration > Duration.zero) {
      buffered = buffered > duration ? duration : buffered;
    }
    playbackState.add(
      PlaybackState(
        controls: _controls(playing: playing),
        systemActions: _systemActions,
        androidCompactActionIndices: _compactIndices,
        processingState: processing,
        playing: playing,
        updatePosition: position,
        bufferedPosition: buffered,
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

  /// Fixed-shape carousel, always three slots.
  ///
  /// Slot 1 swaps between pause and play so the action *count* never changes;
  /// audio_service itself only requires the declared action support to match
  /// the icon it renders (see `AudioService.java`, which asserts exactly that).
  /// A varying length is what desynchronises a head unit's cached action list.
  List<MediaControl> _controls({required bool playing}) => [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ];

  /// Total number of carousel slots, as the AVRCP target computes it.
  int get _actionCount => _compactIndices.length.clamp(0, 3);

  /// Map a carousel *slot* to the AVRCP action id of the operation it performs.
  ///
  /// audio_service encodes each control as `1 << MediaAction.index`, so the
  /// action bits it hands the framework are, in slot order,
  /// `1<<16` (skipToPrevious), `1<<2` (play) or `1<<1` (pause), `1<<5`
  /// (skipToNext). `AUTO_ENABLED_ACTIONS` already covers ACTION_PAUSE and
  /// ACTION_PLAY, but deliberately excludes prev/next (enabling those "forces
  /// the previous/next buttons to always show on Android Auto"), so the first
  /// *newly* supported bit is SKIP_TO_PREVIOUS=16 — which is why the canonical
  /// carousel is `[previous, play/pause, next]`.
  int _avrcpActionForSlot(int slot) {
    final playing = playbackState.value.playing;
    return switch (slot) {
      0 => _avrcpPrevious,
      1 => playing ? _avrcpPause : _avrcpPlay,
      _ => _avrcpNext,
    };
  }

  /// Re-announce the AVRCP key event behind [slot].
  ///
  /// Android's AVRCP target only notifies a head unit once per *slot*, and the
  /// action id sitting behind that slot can change without any new event. A car
  /// that has cached "slot 1 = play" therefore keeps rendering a play triangle
  /// after we flip to pause — and, worse, keeps sending the matching command.
  /// Pushing a state that differs in [PlaybackState.androidCompactActionIndices]
  /// makes the plugin rebuild the notification action list
  /// (`setState()` compares `compactActionIndices` and `controls`), so the
  /// framework re-derives `getActions()` and the head unit re-reads it.
  ///
  /// [PlaybackState] exposes no field for the derived action mask and
  /// `BasicPlaybackState` does not exist in audio_service 0.18.x, so the
  /// supported-set trick is not available here. Layout and transport-support
  /// changes are driven by `controls` / `systemActions` in [_broadcast], which
  /// is the only thing the plugin actually reads.
  void _reannounceCarousel() {
    final prev = playbackState.value;
    final count = _actionCount;
    if (count == 0) return;
    for (var slot = 0; slot < count; slot++) {
      // Collapse to a single slot so the list really differs from what the
      // plugin last saw, then restore the full carousel afterwards.
      playbackState.add(
        prev.copyWith(androidCompactActionIndices: [_avrcpActionForSlot(slot)]),
      );
    }
    playbackState.add(prev.copyWith(androidCompactActionIndices: _compactIndices));
  }
}
