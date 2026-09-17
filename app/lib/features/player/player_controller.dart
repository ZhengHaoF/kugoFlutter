import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../data/repositories/lyric_repository.dart';
import '../../data/repositories/play_repository.dart';
import '../../data/storage/queue_store.dart';
import 'audio_player_port.dart';
import 'just_audio_player.dart';

enum PlayerLoopMode { order, listLoop, shuffle, single }

enum PlayerDisplayState { idle, loading, playing, paused, error }

class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.currentIndex = 0,
    this.display = PlayerDisplayState.idle,
    this.mode = PlayerLoopMode.listLoop,
    this.positionMs = 0,
    this.volume = 1.0,
    this.lyrics = const [],
    this.errorCode = '',
    this.seq = 0,
  });

  final List<Track> queue;
  final int currentIndex;
  final PlayerDisplayState display;
  final PlayerLoopMode mode;
  final int positionMs;
  final double volume;
  final List<LyricLine> lyrics;
  final String errorCode;
  final int seq;

  Track? get current =>
      queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length
          ? null
          : queue[currentIndex];

  bool get isPlaying => display == PlayerDisplayState.playing;

  bool get isLoading => display == PlayerDisplayState.loading;

  int get durationMs => current?.durationMs ?? 0;

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    PlayerDisplayState? display,
    PlayerLoopMode? mode,
    int? positionMs,
    double? volume,
    List<LyricLine>? lyrics,
    String? errorCode,
    int? seq,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      display: display ?? this.display,
      mode: mode ?? this.mode,
      positionMs: positionMs ?? this.positionMs,
      volume: volume ?? this.volume,
      lyrics: lyrics ?? this.lyrics,
      errorCode: errorCode ?? this.errorCode,
      seq: seq ?? this.seq,
    );
  }
}

class PlayerController extends Notifier<PlayerState> {
  PlayerController({AudioPlayerPort? engine}) : _engineOverride = engine;

  final AudioPlayerPort? _engineOverride;
  late final AudioPlayerPort _engine;
  final _playRepo = playRepository;
  final _lyricRepo = lyricRepository;

  KugoMediaBridge? _bridge;
  StreamSubscription<void>? _posSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<PlayerIdleReason>? _completeSub;
  QueueStore? _store;
  int _seq = 0;
  int _failStreak = 0;
  Timer? _demoTimer;
  Timer? _sleepTimer;
  int _sleepDeadlineMs = 0;

  @override
  PlayerState build() {
    _engine = _engineOverride ?? JustAudioPlayerImpl();
    _posSub = _engine.positionStream.listen((pos) {
      state = state.copyWith(positionMs: pos.inMilliseconds);
      _bridge?.updatePosition(pos);
    });
    // Keep UI icon in sync with the real engine (just_audio) playing flag.
    _playingSub = _engine.playingStream.listen((playing) {
      if (state.display == PlayerDisplayState.loading ||
          state.display == PlayerDisplayState.error ||
          state.display == PlayerDisplayState.idle) {
        return;
      }
      if (playing && state.display != PlayerDisplayState.playing) {
        state = state.copyWith(display: PlayerDisplayState.playing);
        _syncBridge();
      } else if (!playing && state.display == PlayerDisplayState.playing) {
        state = state.copyWith(display: PlayerDisplayState.paused);
        _syncBridge();
      }
    });
    _completeSub = _engine.completionStream.listen((reason) {
      if (reason == PlayerIdleReason.completed) {
        _onCompleted();
      } else if (reason == PlayerIdleReason.error) {
        _onPlayError();
      }
    });

    ref.onDispose(() {
      _posSub?.cancel();
      _playingSub?.cancel();
      _completeSub?.cancel();
      _demoTimer?.cancel();
      _sleepTimer?.cancel();
      _engine.dispose();
    });

    return const PlayerState();
  }

  /// 清空队列（游客/无数据时）
  void clearQueue() {
    _stopDemoTick();
    _seq++;
    state = const PlayerState();
  }

  /// 仅从磁盘恢复上次队列；无记录则保持空队列（不塞 mock）。
  Future<void> restoreOrSeed() async {
    try {
      _store = await QueueStore.open();
      final saved = _store?.loadQueue();
      if (saved != null && saved.queue.isNotEmpty) {
        // Drop legacy mock:// tracks from earlier builds.
        final tracks = saved.queue
            .where((t) => t.coverUrl.startsWith('http') || t.hasHash)
            .toList();
        if (tracks.isEmpty) return;
        final mode = PlayerLoopMode.values.firstWhere(
          (m) => m.name == saved.mode,
          orElse: () => PlayerLoopMode.listLoop,
        );
        final index = saved.index.clamp(0, tracks.length - 1);
        final seq = ++_seq;
        state = state.copyWith(
          queue: List.unmodifiable(tracks),
          currentIndex: index,
          mode: mode,
          display: PlayerDisplayState.paused,
          positionMs: 0,
          lyrics: const [],
          seq: seq,
        );
        _syncBridge();
      }
    } catch (_) {}
  }

  void attachBridge(KugoMediaBridge bridge) {
    _bridge = bridge;
    _syncBridge();
  }

  /// Public snapshot for media handler / external callers.
  PlayerState get snapshot => state;

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final index = startIndex.clamp(0, tracks.length - 1);
    final seq = ++_seq;
    state = state.copyWith(
      queue: List.unmodifiable(tracks),
      currentIndex: index,
      display: PlayerDisplayState.loading,
      positionMs: 0,
      lyrics: const [],
      errorCode: '',
      seq: seq,
    );
    _syncBridge();
    unawaited(_persistQueue());
    await _loadCurrent(seq: seq);
  }

  Future<void> _persistQueue() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.saveQueue(
        state.queue,
        state.currentIndex,
        state.mode.name,
      );
      final track = state.current;
      if (track != null) {
        await store.appendHistory(track);
      }
    } catch (_) {}
  }

  Future<void> _loadCurrent({required int seq}) async {
    final track = state.current;
    if (track == null) return;
    if (seq != state.seq) return;

    state = state.copyWith(display: PlayerDisplayState.loading, errorCode: '');
    _syncBridge();
    unawaited(_loadLyrics(track, seq));

    if (!track.hasHash) {
      state = state.copyWith(display: PlayerDisplayState.playing);
      _startDemoTick();
      _syncBridge(track: track);
      return;
    }

    _stopDemoTick();
    final resolved = await _playRepo.resolveUrl(track);
    if (seq != state.seq) return;

    if (resolved == null) {
      final msg = _playRepo.lastError.isNotEmpty
          ? _playRepo.lastError
          : '无法获取播放地址';
      _onPlayError(message: msg);
      return;
    }

    var ok = false;
    Object? lastError;
    for (final url in resolved.allUrls) {
      try {
        await _engine.playUrl(
          url,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Referer': 'http://www.kugou.com/',
          },
        );
        ok = true;
        break;
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    if (seq != state.seq) return;
    if (!ok) {
      final engineMsg = lastError?.toString().split('\n').first ?? '';
      final msg = engineMsg.isEmpty
          ? '播放失败：源不可播（VIP/防盗链/网络）'
          : '播放失败：$engineMsg';
      _onPlayError(message: msg);
      return;
    }
    _failStreak = 0;
    state = state.copyWith(display: PlayerDisplayState.playing);
    _syncBridge(track: track);
  }

  Future<void> _loadLyrics(Track track, int seq) async {
    if (!track.hasHash) {
      if (seq != state.seq) return;
      state = state.copyWith(lyrics: const []);
      return;
    }
    final lines = await _lyricRepo.fetchLyrics(track);
    if (seq != state.seq) return;
    state = state.copyWith(lyrics: lines);
  }

  void togglePlay() {
    final track = state.current;
    if (track == null) return;
    if (state.isPlaying) {
      if (track.hasHash) {
        unawaited(_engine.pause());
      }
      _stopDemoTick();
      state = state.copyWith(display: PlayerDisplayState.paused);
    } else {
      if (track.hasHash) {
        unawaited(_engine.play());
      } else {
        _startDemoTick();
      }
      state = state.copyWith(display: PlayerDisplayState.playing);
    }
    _syncBridge();
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    var index = state.currentIndex + 1;
    if (index >= state.queue.length) {
      if (state.mode == PlayerLoopMode.order) {
        await _engine.pause();
        _stopDemoTick();
        state = state.copyWith(
          display: PlayerDisplayState.paused,
          positionMs: 0,
        );
        _syncBridge();
        return;
      }
      if (state.mode == PlayerLoopMode.shuffle) {
        index = _randomIndex(state.queue.length, exclude: state.currentIndex);
      } else {
        index = 0;
      }
    } else if (state.mode == PlayerLoopMode.shuffle && state.queue.length > 1) {
      index = _randomIndex(state.queue.length, exclude: state.currentIndex);
    }
    final seq = ++_seq;
    state = state.copyWith(
      currentIndex: index,
      positionMs: 0,
      display: PlayerDisplayState.loading,
      seq: seq,
    );
    unawaited(_persistQueue());
    await _loadCurrent(seq: seq);
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    var index = state.currentIndex - 1;
    if (index < 0) index = state.queue.length - 1;
    final seq = ++_seq;
    state = state.copyWith(
      currentIndex: index,
      positionMs: 0,
      display: PlayerDisplayState.loading,
      seq: seq,
    );
    unawaited(_persistQueue());
    await _loadCurrent(seq: seq);
  }

  void seekTo(int positionMs) {
    final duration = state.durationMs;
    final clamped = positionMs.clamp(0, duration);
    state = state.copyWith(positionMs: clamped);
    final track = state.current;
    if (track != null && track.hasHash) {
      unawaited(_engine.seek(Duration(milliseconds: clamped)));
    }
    _bridge?.updatePosition(Duration(milliseconds: clamped));
  }

  void cycleMode() {
    const order = PlayerLoopMode.values;
    final nextIndex = (order.indexOf(state.mode) + 1) % order.length;
    state = state.copyWith(mode: order[nextIndex]);
  }

  /// Sleep timer: [minutes] == 0 cancels.
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (minutes <= 0) {
      _sleepDeadlineMs = 0;
      return;
    }
    _sleepDeadlineMs =
        DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (state.isPlaying) {
        togglePlay();
      }
      _sleepDeadlineMs = 0;
    });
  }

  /// Remaining sleep minutes, 0 if off.
  int get sleepRemainingMinutes {
    if (_sleepDeadlineMs == 0) return 0;
    final left = _sleepDeadlineMs - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return 0;
    return (left / 60000).ceil();
  }

  void _onCompleted() {
    if (state.mode == PlayerLoopMode.single) {
      seekTo(0);
      unawaited(_engine.play());
      return;
    }
    unawaited(next());
  }

  void _onPlayError({String message = '播放出错'}) {
    _failStreak += 1;
    if (_failStreak < 3 && state.queue.length > 1) {
      unawaited(next());
      return;
    }
    state = state.copyWith(display: PlayerDisplayState.error, errorCode: message);
    _syncBridge();
  }

  void _startDemoTick() {
    _stopDemoTick();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!state.isPlaying) return;
      final nextPos = state.positionMs + 400;
      if (nextPos >= state.durationMs) {
        _onCompleted();
        return;
      }
      state = state.copyWith(positionMs: nextPos);
    });
  }

  void _stopDemoTick() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  int _randomIndex(int length, {required int exclude}) {
    if (length <= 1) return 0;
    var idx = exclude;
    var guard = 0;
    while (idx == exclude && guard++ < 8) {
      idx = DateTime.now().microsecondsSinceEpoch % length;
    }
    if (idx == exclude) idx = (exclude + 1) % length;
    return idx;
  }

  void _syncBridge({Track? track}) {
    _bridge?.sync(
      playing: state.isPlaying,
      processing: switch (state.display) {
        PlayerDisplayState.loading => AudioProcessingState.loading,
        PlayerDisplayState.playing => AudioProcessingState.ready,
        PlayerDisplayState.paused => AudioProcessingState.ready,
        PlayerDisplayState.error => AudioProcessingState.error,
        PlayerDisplayState.idle => AudioProcessingState.idle,
      },
      position: Duration(milliseconds: state.positionMs),
      track: track ?? state.current,
    );
  }
}

/// Bridge used by the platform media handler to push system UI updates.
abstract class KugoMediaBridge {
  void sync({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
    Track? track,
  });

  void updatePosition(Duration position);
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

/// Factory for tests: inject a fake engine.
PlayerController createPlayerController(AudioPlayerPort engine) =>
    PlayerController(engine: engine);

final currentTrackProvider = Provider<Track?>((ref) {
  return ref.watch(playerControllerProvider.select((s) => s.current));
});
