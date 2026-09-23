import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/audio_quality.dart';
import '../../core/models/playback_source.dart';
import '../../core/models/track.dart';
import '../../data/repositories/lyric_repository.dart';
import '../../data/repositories/play_repository.dart';
import '../../data/storage/queue_store.dart';
import '../settings/settings_controller.dart';
import 'audio_engine.dart';
import 'audio_player_port.dart';

enum PlayerLoopMode { order, listLoop, shuffle, single }

extension PlayerLoopModeLabel on PlayerLoopMode {
  String get label => switch (this) {
        PlayerLoopMode.order => '顺序播放',
        PlayerLoopMode.listLoop => '列表循环',
        PlayerLoopMode.shuffle => '随机播放',
        PlayerLoopMode.single => '单曲循环',
      };
}

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
    this.lyricsStatus = LyricsStatus.idle,
    this.errorCode = '',
    this.seq = 0,
    this.resolvedQuality,
    this.queueSource = PlaybackQueueSource.none,
    this.engineDurationMs = 0,
  });

  final List<Track> queue;
  final int currentIndex;
  final PlayerDisplayState display;
  final PlayerLoopMode mode;
  final int positionMs;
  final double volume;
  final List<LyricLine> lyrics;
  final LyricsStatus lyricsStatus;
  final String errorCode;
  final int seq;

  /// 实际解析出的音质（EchoMusic resolved quality）；null = 尚未解析成功。
  final AppQuality? resolvedQuality;

  /// 队列来源。决定传输键的边界语义（见 [PlaybackQueueSource]）。
  final PlaybackQueueSource queueSource;

  /// Duration reported by the audio engine (media_kit / just_audio).
  /// Preferred over [Track.durationMs] when > 0 — API metadata is often wrong
  /// or unit-mismatched on desktop play paths.
  final int engineDurationMs;

  /// Last *discrete* cursor (seek / track load / stop). Live engine ticks do
  /// **not** land here — those go to [PlayerController.position] so progress
  /// UI can listen without rebuilding every full-state consumer.
  ///
  /// Prefer `ref.watch(playerPositionProvider)` (or `controller.position`)
  /// for anything that must track playback in real time.

  /// 「上一首」当前是否可点。
  ///
  /// FM 会话只能池内回退：退到会话第一首就必须禁用，否则用户会一路退到
  /// 队列尾部（普通队列的环绕行为），把「未播的后续」当成历史播回去。
  bool get canStepBack {
    if (queue.length < 2) return false;
    if (queueSource == PlaybackQueueSource.fm) return currentIndex > 0;
    return true;
  }

  Track? get current =>
      queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length
          ? null
          : queue[currentIndex];

  bool get isPlaying => display == PlayerDisplayState.playing;

  bool get isLoading => display == PlayerDisplayState.loading;

  bool get lyricsLoading => lyricsStatus == LyricsStatus.loading;

  int get durationMs {
    if (engineDurationMs > 0) return engineDurationMs;
    return current?.durationMs ?? 0;
  }

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    PlayerDisplayState? display,
    PlayerLoopMode? mode,
    int? positionMs,
    double? volume,
    List<LyricLine>? lyrics,
    LyricsStatus? lyricsStatus,
    String? errorCode,
    int? seq,
    AppQuality? Function()? resolvedQuality,
    PlaybackQueueSource? queueSource,
    int? engineDurationMs,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      display: display ?? this.display,
      mode: mode ?? this.mode,
      positionMs: positionMs ?? this.positionMs,
      volume: volume ?? this.volume,
      lyrics: lyrics ?? this.lyrics,
      lyricsStatus: lyricsStatus ?? this.lyricsStatus,
      errorCode: errorCode ?? this.errorCode,
      seq: seq ?? this.seq,
      resolvedQuality: resolvedQuality != null
          ? resolvedQuality()
          : this.resolvedQuality,
      queueSource: queueSource ?? this.queueSource,
      engineDurationMs: engineDurationMs ?? this.engineDurationMs,
    );
  }
}

class PlayerController extends Notifier<PlayerState> {
  PlayerController({
    AudioPlayerPort? engine,
    LyricRepository? lyricRepo,
    PlayRepository? playRepo,
  })  : _engineOverride = engine,
        _lyricRepoOverride = lyricRepo,
        _playRepoOverride = playRepo;

  final AudioPlayerPort? _engineOverride;
  final LyricRepository? _lyricRepoOverride;
  final PlayRepository? _playRepoOverride;
  late final AudioPlayerPort _engine;
  late final PlayRepository _playRepo;
  late final LyricRepository _lyricRepo;

  /// High-frequency playback cursor (ms). Engine `positionStream` only writes
  /// here — never into Riverpod [PlayerState] — so listening widgets rebuild
  /// in isolation instead of dragging the whole UI tree along every tick.
  final ValueNotifier<int> position = ValueNotifier(0);

  KugoMediaBridge? _bridge;
  StreamSubscription<void>? _posSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<PlayerIdleReason>? _completeSub;
  QueueStore? _store;
  int _seq = 0;
  int _failStreak = 0;
  /// 歌词请求身份：`id|hash`。用于去重与「曲目已变则丢弃过期结果」。
  String? _lyricsInFlightKey;
  String? _lyricsLoadedKey;
  /// True once this session has a playable engine source for the current track.
  /// Cold-start restore fills the queue but not the engine — play must resolve URL first.
  bool _sourceReady = false;
  /// Engine `positionStream` belongs to the *currently loaded* source. During a
  /// track switch the previous source keeps emitting until `playUrl` swaps it,
  /// and those leftovers (e.g. 10s into song A) must not re-anchor the media
  /// tick — that is exactly how a car head unit ends up showing song B starting
  /// at 10s. Cleared on load/stop; re-armed only after the new source is live.
  bool _acceptEnginePosition = false;
  /// User/system intent: should audio be playing? Engine events must not flip
  /// the pause/play icon against this (late `playing=true` after user pause).
  bool _wantPlaying = false;
  DateTime? _ignoreEnginePlayUntil;
  Timer? _demoTimer;
  Timer? _sleepTimer;
  Timer? _mediaTick;
  int _sleepDeadlineMs = 0;
  String? _lastMediaSubtitle;
  int _bufferedMs = 0;
  /// Base used to extrapolate the position between engine events. Only ever
  /// moves forward — see [_publishMediaPosition].
  int _tickBaseMs = 0;
  DateTime _tickBaseAt = DateTime.now();
  /// Highest position already pushed to the platform — keeps it monotonic.
  /// `-1` until the first push so a legitimate `0` (track start) is not forced
  /// up to `1`.
  int _lastPushedMs = -1;
  String _lastQueueSig = '';

  @override
  PlayerState build() {
    _engine = _engineOverride ?? createAudioEngine();
    _playRepo = _playRepoOverride ?? playRepository;
    _lyricRepo = _lyricRepoOverride ?? lyricRepository;
    ref.listen(settingsControllerProvider, (prev, next) {
      if (prev?.mediaLyricSubtitle != next.mediaLyricSubtitle) {
        _lastMediaSubtitle = null;
        _maybeUpdateMediaSubtitle();
      }
    });
    _posSub = _engine.positionStream.listen((pos) {
      final ms = pos.inMilliseconds;
      // Drop samples from the *previous* source (track switch / stop). They
      // arrive while the next URL is still resolving and would otherwise drag
      // `_tickBaseMs` back to the old track's cursor.
      if (!_acceptEnginePosition) return;
      // Only let the engine advance the extrapolation base. just_audio emits on
      // a fixed 200ms cadence that beats against the 1s media tick, so an
      // unconditional assignment would occasionally anchor the base to a
      // sample *older* than the position already handed to the platform — the
      // next tick would then look like a backwards jump to AVRCP.
      if (ms > _tickBaseMs) {
        _tickBaseMs = ms;
        _tickBaseAt = DateTime.now();
      }
      // NB: engine samples must NOT assign Riverpod state. media_kit / mpv
      // emits position very often; copyWith(positionMs:) would rebuild every
      // full-state watcher (player bar, explore, lists…) on each tick. Live
      // UI listens to [position] instead. Discrete jumps (seek / track load)
      // still mirror into [PlayerState.positionMs] for logic and tests.
      if (position.value != ms) position.value = ms;
      // The engine sample is deliberately NOT forwarded to the media
      // session here. The MediaSession holds a snapshot, not a live value, and
      // positions must never be published out of order (AVRCP only refreshes
      // when the value changes, and a sample arriving out of order looks like a
      // backwards jump). `_mediaTick` is the single writer for the platform.
      _maybeUpdateMediaSubtitle();
    });
    _bufferedSub = _engine.bufferedPositionStream.listen((pos) {
      _bufferedMs = pos.inMilliseconds;
    });
    // Engine duration wins over API metadata when available (metadata is often
    // wrong / unit-mismatched; media_kit demuxes the real file length).
    _durationSub = _engine.durationStream.listen((duration) {
      _applyEngineDuration(duration?.inMilliseconds ?? 0);
    });
    // Sync play/pause UI from engine, but never override an explicit pause.
    _playingSub = _engine.playingStream.listen((playing) {
      if (state.display == PlayerDisplayState.error ||
          state.display == PlayerDisplayState.idle) {
        return;
      }
      if (!_wantPlaying) {
        // User paused (or restored idle) — keep icon on play.
        if (state.display == PlayerDisplayState.playing) {
          state = state.copyWith(display: PlayerDisplayState.paused);
          _syncBridge();
        }
        return;
      }
      final ignoreUntil = _ignoreEnginePlayUntil;
      if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
        return;
      }
      if (playing && state.display != PlayerDisplayState.playing) {
        state = state.copyWith(display: PlayerDisplayState.playing);
        _syncBridge();
      } else if (!playing && state.display == PlayerDisplayState.playing) {
        // Engine stopped while we still want audio (e.g. completed handled elsewhere).
        state = state.copyWith(display: PlayerDisplayState.paused);
        _wantPlaying = false;
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
      _bufferedSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _completeSub?.cancel();
      _demoTimer?.cancel();
      _sleepTimer?.cancel();
      _mediaTick?.cancel();
      position.dispose();
      _engine.dispose();
    });

    return const PlayerState();
  }

  /// 清空队列（游客/无数据时）
  void clearQueue() {
    _stopDemoTick();
    _seq++;
    _sourceReady = false;
    _acceptEnginePosition = false;
    _wantPlaying = false;
    _ignoreEnginePlayUntil = null;
    _lyricsInFlightKey = null;
    _lyricsLoadedKey = null;
    _zeroCursor();
    state = const PlayerState();
  }

  /// 仅从磁盘恢复上次队列；无记录则保持空队列（不塞 mock）。
  Future<void> restoreOrSeed() async {
    try {
      _store = await QueueStore.open();
      final saved = await _store?.loadQueueAsync();
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
        _sourceReady = false;
        _wantPlaying = false;
        _ignoreEnginePlayUntil = null;
        _lyricsInFlightKey = null;
        _lyricsLoadedKey = null;
        _zeroCursor();
        state = state.copyWith(
          queue: List.unmodifiable(tracks),
          currentIndex: index,
          mode: mode,
          display: PlayerDisplayState.paused,
          positionMs: 0,
          lyrics: const [],
          lyricsStatus: LyricsStatus.idle,
          seq: seq,
          engineDurationMs: 0,
        );
        _syncBridge();
        // 冷启动只恢复队列、不起播；歌词与播放解耦，这里也要预取。
        unawaited(_ensureLyrics());
      }
    } catch (_) {}
  }

  void attachBridge(KugoMediaBridge bridge) {
    _bridge = bridge;
    _syncBridge();
  }

  /// Release playback on behalf of the system media handler (`stop()` /
  /// `onTaskRemoved()`), not on behalf of the UI.
  ///
  /// The engine is paused and the queue is kept so the user can resume from the
  /// notification or the app, but [_wantPlaying] is cleared first so the late
  /// `playing=false` engine event cannot flip the icon back, and the session is
  /// left in [AudioProcessingState.idle] so Android tears the notification down.
  ///
  /// Note the two early returns when the queue is empty: those are the
  /// *notification swipe-away* and *re-attach* paths. Firing a fresh state into
  /// the media session there used to re-enter `setState()`, whose idle branch
  /// calls `deactivateMediaSession()` (and `stopSelf()`), killing the very
  /// session the new track was about to use.
  Future<void> stopPlayback() async {
    _stopDemoTick();
    _wantPlaying = false;
    _ignoreEnginePlayUntil = DateTime.now().add(const Duration(seconds: 1));
    _sourceReady = false;
    _acceptEnginePosition = false;
    if (state.current != null) {
      await _engine.pause();
    }
    if (state.display == PlayerDisplayState.idle) {
      // Already stopped — broadcasting again would only churn setState().
      return;
    }
    _zeroCursor();
    state = state.copyWith(
      display: PlayerDisplayState.idle,
      positionMs: 0,
      errorCode: '',
    );
    _syncBridge();
  }

  /// Public snapshot for media handler / external callers.
  PlayerState get snapshot => state;

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    PlaybackQueueSource source = PlaybackQueueSource.none,
  }) async {
    if (tracks.isEmpty) return;
    final index = startIndex.clamp(0, tracks.length - 1);
    final seq = ++_seq;
    _sourceReady = false;
    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    _lyricsInFlightKey = null;
    _lyricsLoadedKey = null;
    _zeroCursor();
    state = state.copyWith(
      queue: List.unmodifiable(tracks),
      currentIndex: index,
      display: PlayerDisplayState.loading,
      positionMs: 0,
      lyrics: const [],
      lyricsStatus: LyricsStatus.loading,
      errorCode: '',
      seq: seq,
      queueSource: source,
      engineDurationMs: 0,
    );
    _syncBridge();
    unawaited(_persistQueue());
    unawaited(_ensureLyrics());
    await _loadCurrent(seq: seq);
  }

  /// 标记当前队列的来源，但不重载曲目。
  ///
  /// 冷启动恢复队列时用：Drift 快照里没有来源位（加列要走 codegen），
  /// 由 FM 会话用自己的标记判断「恢复出来的队列就是 FM 流」后回填。
  void markQueueSource(PlaybackQueueSource source) {
    if (state.queue.isEmpty || state.queueSource == source) return;
    state = state.copyWith(queueSource: source);
    _syncBridge();
  }

  /// 往活动队列尾部追加，不动游标（FM 续流用：边播边补）。
  Future<void> appendToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    state = state.copyWith(
      queue: List.unmodifiable([...state.queue, ...tracks]),
    );
    _syncBridge();
    unawaited(_persistQueue());
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

  /// Prefer engine-reported duration; also patch the queue track so list UIs
  /// stay consistent. Ignores zero (not ready) and sub-second glitch values
  /// when metadata already has a plausible length.
  void _applyEngineDuration(int ms) {
    if (ms < 0) ms = 0;
    if (ms == state.engineDurationMs) return;

    final meta = state.current?.durationMs ?? 0;
    final looksGlitched = ms > 0 && ms < 2000 && meta >= 30000;
    if (looksGlitched) return;

    final idx = state.currentIndex;
    final queue = state.queue;
    if (ms > 0 && idx >= 0 && idx < queue.length) {
      final track = queue[idx];
      if (track.durationMs != ms) {
        final next = [...queue];
        next[idx] = track.copyWith(durationMs: ms);
        state = state.copyWith(
          queue: List.unmodifiable(next),
          engineDurationMs: ms,
        );
        unawaited(_persistQueue());
        return;
      }
    }
    state = state.copyWith(engineDurationMs: ms);
  }

  Future<void> _loadCurrent({required int seq}) async {
    final track = state.current;
    if (track == null) return;
    if (seq != state.seq) return;

    // Freeze the media cursor at 0 and ignore the outgoing source's samples
    // until the new one is actually live (see [_acceptEnginePosition]).
    _acceptEnginePosition = false;
    _resetMediaPosition(0);

    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    state = state.copyWith(
      display: PlayerDisplayState.loading,
      errorCode: '',
      engineDurationMs: 0,
    );
    _syncBridge();
    // 歌词与起播解耦：URL resolve 失败也不该挡住歌词。
    unawaited(_ensureLyrics());

    if (!track.hasHash) {
      _wantPlaying = true;
      state = state.copyWith(display: PlayerDisplayState.playing);
      _startDemoTick();
      _syncBridge(track: track);
      return;
    }

    _stopDemoTick();
    _sourceReady = false;

    var liveTrack = track;
    if (liveTrack.hasHash && liveTrack.availableQualities.isEmpty) {
      final fetched = await _playRepo.fetchRelateGoods(liveTrack);
      if (seq != state.seq) return;
      final goods = fetched?.goods;
      if (goods != null && goods.isNotEmpty) {
        final available = AudioQualityUtil.availableFromGoods(goods);
        liveTrack = liveTrack
            .copyWith(
              relateGoods: goods,
              availableQualities: available,
              qualityCatalogComplete: fetched?.catalogComplete ?? false,
            )
            .withAvailableQualities(available);
        _patchCurrentTrack(liveTrack);
      }
    }

    final preferred =
        ref.read(settingsControllerProvider).quality;
    final candidates = AudioQualityUtil.resolveCandidates(
      preferred: preferred,
      available: liveTrack.availableQualities,
      compatibilityMode: true,
      catalogComplete: liveTrack.qualityCatalogComplete,
    );
    final resolved = await _playRepo.resolveUrlWithFallback(
      liveTrack,
      qualityCandidates: [for (final q in candidates) q.param],
    );
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
    if (!_wantPlaying) {
      // User paused while URL was resolving — stop engine, keep paused icon.
      unawaited(_engine.pause());
      _sourceReady = true;
      _armEnginePositionAfterLoad();
      state = state.copyWith(
        display: PlayerDisplayState.paused,
        resolvedQuality: () => resolved.qualityEnum,
      );
      _syncBridge(track: liveTrack);
      return;
    }
    _failStreak = 0;
    _sourceReady = true;
    _armEnginePositionAfterLoad();
    state = state.copyWith(
      display: PlayerDisplayState.playing,
      resolvedQuality: () => resolved.qualityEnum,
    );
    _syncBridge(track: liveTrack);
  }

  /// New source is live: re-accept engine samples and force the platform cursor
  /// back to 0 so a car head unit cannot keep the previous track's elapsed time.
  void _armEnginePositionAfterLoad() {
    _acceptEnginePosition = true;
    _resetMediaPosition(0);
    _publishMediaPosition(0, force: true);
  }

  void _patchCurrentTrack(Track updated) {
    final q = state.queue.toList();
    if (state.currentIndex < 0 || state.currentIndex >= q.length) return;
    q[state.currentIndex] = updated;
    state = state.copyWith(queue: List.unmodifiable(q));
  }

  /// Resolve + load the current track into the engine (cold start / failed source).
  Future<void> reloadCurrent() => _reloadCurrent();

  /// 播放页/歌词页打开时补拉：当前曲有 hash 但尚未拿到歌词结论则请求。
  ///
  /// [retryIfEmpty]：UI 主动打开时置 true，允许对「空结论」再试一次
  ///（覆盖网络恢复后仍停在同一首的场景）；已有 ready 结论仍不会重复请求。
  void ensureLyricsForCurrent({bool retryIfEmpty = false}) {
    final track = state.current;
    if (retryIfEmpty &&
        track != null &&
        track.hasHash &&
        state.lyricsStatus == LyricsStatus.empty) {
      final key = _lyricsTrackKey(track);
      if (_lyricsLoadedKey == key) _lyricsLoadedKey = null;
    }
    unawaited(_ensureLyrics());
  }

  /// 播放页切换音质：写入默认偏好并立即重载当前曲（对齐 EchoMusic）。
  Future<void> applyQuality(AppQuality quality) async {
    final settings = ref.read(settingsControllerProvider.notifier);
    await settings.setQuality(quality);
    if (state.current == null) return;
    // Preserve play intent: if currently paused, stay paused after reload.
    await _reloadCurrent();
  }

  /// 打开音质 sheet 前懒加载当前曲可用音质；已知则跳过。
  Future<Set<AppQuality>> ensureCurrentQualities({bool forceRefresh = false}) async {
    final track = state.current;
    if (track == null || !track.hasHash) return const {};
    if (!forceRefresh && track.availableQualities.isNotEmpty) {
      return track.availableQualities;
    }
    final fetched = await _playRepo.fetchRelateGoods(track);
    if (fetched == null) return track.availableQualities;
    final goods = fetched.goods;
    final available = AudioQualityUtil.availableFromGoods(goods);
    if (available.isEmpty) return track.availableQualities;
    final updated = track
        .copyWith(
          relateGoods: goods,
          availableQualities: available,
          qualityCatalogComplete: fetched.catalogComplete,
        )
        .withAvailableQualities(available);
    _patchCurrentTrack(updated);
    return updated.availableQualities;
  }

  static String _lyricsTrackKey(Track t) =>
      '${t.id}|${t.hash.trim().toLowerCase()}';

  /// 保证「当前曲」的歌词已发起加载；与播放/起播成败无关。
  ///
  /// - 无曲 / 无 hash：直接给出 empty/idle 结论
  /// - 同一曲已有结论（ready 或 empty）：不重复请求
  /// - 同一曲已在飞：去重
  /// - 结果回来时若 current 已换成别的曲：丢弃，由新曲的 ensure 接管
  Future<void> _ensureLyrics() async {
    final track = state.current;
    if (track == null) {
      _lyricsInFlightKey = null;
      _lyricsLoadedKey = null;
      if (state.lyrics.isNotEmpty ||
          state.lyricsStatus != LyricsStatus.idle) {
        state = state.copyWith(
          lyrics: const [],
          lyricsStatus: LyricsStatus.idle,
        );
      }
      return;
    }

    if (!track.hasHash) {
      _lyricsInFlightKey = null;
      _lyricsLoadedKey = _lyricsTrackKey(track);
      state = state.copyWith(
        lyrics: const [],
        lyricsStatus: LyricsStatus.empty,
      );
      return;
    }

    final key = _lyricsTrackKey(track);
    if (_lyricsLoadedKey == key) return;
    if (_lyricsInFlightKey == key) return;

    _lyricsInFlightKey = key;
    state = state.copyWith(
      lyrics: const [],
      lyricsStatus: LyricsStatus.loading,
    );

    List<LyricLine> lines = const [];
    try {
      lines = await _lyricRepo.fetchLyrics(track);
    } catch (_) {}

    final current = state.current;
    if (current == null || _lyricsTrackKey(current) != key) {
      return;
    }

    _lyricsInFlightKey = null;
    _lyricsLoadedKey = key;
    state = state.copyWith(
      lyrics: lines,
      lyricsStatus: lines.isEmpty ? LyricsStatus.empty : LyricsStatus.ready,
    );
    _maybeUpdateMediaSubtitle();
  }

  void togglePlay() {
    final track = state.current;
    if (track == null) return;
    if (state.isPlaying) {
      // Intent first so late engine playing=true cannot flip the icon back.
      _wantPlaying = false;
      _ignoreEnginePlayUntil =
          DateTime.now().add(const Duration(milliseconds: 600));
      if (track.hasHash) {
        unawaited(_engine.pause());
      }
      _stopDemoTick();
      state = state.copyWith(display: PlayerDisplayState.paused);
      _syncBridge();
      return;
    }
    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    if (track.hasHash && !_sourceReady) {
      // Restored queue after cold start: engine has no URL — resolve first.
      unawaited(_reloadCurrent());
      return;
    }
    if (track.hasHash) {
      unawaited(_engine.play());
    } else {
      _startDemoTick();
    }
    state = state.copyWith(display: PlayerDisplayState.playing);
    _syncBridge();
  }

  /// Resolve + load the current track into the engine (cold start / failed source).
  Future<void> _reloadCurrent() async {
    if (state.current == null) return;
    final seq = ++_seq;
    _sourceReady = false;
    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    _lyricsInFlightKey = null;
    _lyricsLoadedKey = null;
    _zeroCursor();
    state = state.copyWith(
      display: PlayerDisplayState.loading,
      positionMs: 0,
      errorCode: '',
      seq: seq,
      resolvedQuality: () => null,
    );
    _syncBridge();
    await _loadCurrent(seq: seq);
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    _sourceReady = false;
    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    var index = state.currentIndex + 1;
    if (index >= state.queue.length) {
      // FM 是流，不是歌单：没有「下一首」可退化成环绕。续流由 FM 会话负责，
      // 它会在接近池尾时提前 append；真到边界这里就停住，不绕回第一首。
      if (state.queueSource == PlaybackQueueSource.fm) return;
      if (state.mode == PlayerLoopMode.order) {
        await _engine.pause();
        _stopDemoTick();
        _zeroCursor();
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
    } else if (state.mode == PlayerLoopMode.shuffle &&
        state.queue.length > 1 &&
        state.queueSource != PlaybackQueueSource.fm) {
      index = _randomIndex(state.queue.length, exclude: state.currentIndex);
    }
    await _jumpTo(index);
  }

  /// 跳到队列里指定下标（FM 待播列表点选用）。
  Future<void> playAtIndex(int index) async {
    if (state.queue.isEmpty) return;
    if (index < 0 || index >= state.queue.length) return;
    await _jumpTo(index);
  }

  Future<void> _jumpTo(int index) async {
    final seq = ++_seq;
    _lyricsInFlightKey = null;
    _lyricsLoadedKey = null;
    _zeroCursor();
    state = state.copyWith(
      currentIndex: index,
      positionMs: 0,
      display: PlayerDisplayState.loading,
      seq: seq,
      lyrics: const [],
      lyricsStatus: LyricsStatus.loading,
    );
    unawaited(_persistQueue());
    unawaited(_ensureLyrics());
    await _loadCurrent(seq: seq);
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    _sourceReady = false;
    _wantPlaying = true;
    _ignoreEnginePlayUntil = null;
    var index = state.currentIndex - 1;
    if (index < 0) {
      // FM 只允许池内回退：边界上按 [PlayerState.canStepBack] 已经禁用，
      // 这里是双保险，绝不环绕到队列尾部。
      if (state.queueSource == PlaybackQueueSource.fm) return;
      index = state.queue.length - 1;
    }
    await _jumpTo(index);
  }

  /// Snap the live cursor (and the media-session cursor) back to 0.
  void _zeroCursor() {
    if (position.value != 0) position.value = 0;
    _resetMediaPosition(0);
  }

  /// Relative seek from the live cursor (keyboard ±5s etc.).
  void seekBy(int deltaMs) => seekTo(position.value + deltaMs);

  void seekTo(int positionMs) {
    final duration = state.durationMs;
    final clamped = positionMs.clamp(0, duration);
    if (position.value != clamped) position.value = clamped;
    state = state.copyWith(positionMs: clamped);
    final track = state.current;
    if (track != null && track.hasHash) {
      unawaited(_engine.seek(Duration(milliseconds: clamped)));
    }
    // A seek is an intentional jump, so reset the monotonic guard with it.
    _resetMediaPosition(clamped);
    _publishMediaPosition(clamped, force: true);
  }

  void setVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    unawaited(_engine.setVolume(clamped));
  }

  void setMode(PlayerLoopMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    unawaited(_persistQueue());
  }

  void cycleMode() {
    const order = PlayerLoopMode.values;
    final nextIndex = (order.indexOf(state.mode) + 1) % order.length;
    setMode(order[nextIndex]);
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
      final nextPos = position.value + 400;
      if (nextPos >= state.durationMs) {
        _onCompleted();
        return;
      }
      // Demo path is 2.5 Hz — safe to mirror into state for tests / snapshot.
      position.value = nextPos;
      state = state.copyWith(positionMs: nextPos);
      // Keep MediaSession/Bluetooth progress in sync for non-engine demo tracks.
      _publishMediaPosition(nextPos);
      _maybeUpdateMediaSubtitle();
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
    _ensureMediaTick();
    final current = track ?? state.current;
    final subtitle = current == null ? null : _mediaSubtitleFor(current);
    if (current != null) _lastMediaSubtitle = subtitle;
    _bridge?.sync(
      playing: state.isPlaying,
      processing: switch (state.display) {
        PlayerDisplayState.loading => AudioProcessingState.loading,
        PlayerDisplayState.playing => AudioProcessingState.ready,
        PlayerDisplayState.paused => AudioProcessingState.ready,
        PlayerDisplayState.error => AudioProcessingState.error,
        PlayerDisplayState.idle => AudioProcessingState.idle,
      },
      position: Duration(milliseconds: position.value),
      bufferedPosition: _bufferedDuration,
      track: current,
      subtitle: subtitle,
    );
    _syncQueueBridge();
  }

  /// Steady heartbeat: the MediaSession keeps only the *raw* position snapshot
  /// and Android's AVRCP target stops refreshing the car progress bar once two
  /// consecutive reads are identical, so never let the value go stale.
  /// Only runs once a bridge (system media handler) is attached.
  void _ensureMediaTick() {
    if (_bridge == null || _mediaTick != null) return;
    _mediaTick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pushMediaPosition(),
    );
  }

  Duration get _bufferedDuration => Duration(milliseconds: _bufferedMs);

  /// Restart position extrapolation from [ms] (track change / seek).
  void _resetMediaPosition(int ms) {
    _tickBaseMs = ms;
    _tickBaseAt = DateTime.now();
    _lastPushedMs = ms;
  }

  /// Push a fresh position to the system media session on a steady tick.
  ///
  /// The MediaSession stores a **snapshot**, not a live value: AVRCP reads back
  /// exactly what was last written. Android's AVRCP target additionally stops
  /// emitting `EVENT_PLAYBACK_POS_CHANGED` for good once two consecutive reads
  /// return the same value, which freezes the car progress bar. So this timer
  /// is the single authority on what the platform sees: it extrapolates from
  /// the last engine event (`position + elapsed`) so the value keeps advancing
  /// even if the engine stream stalls (buffering, background, track switch),
  /// and [updatePosition] is deliberately *not* wired to the raw engine stream.
  ///
  /// Counting monotonic elapsed time also makes the sequence strictly
  /// increasing by construction — using wall-clock deltas instead would let
  /// timer jitter push a smaller value than the previous tick.
  void _pushMediaPosition() {
    if (_bridge == null || !state.isPlaying) return;
    final now = DateTime.now();
    final elapsed = now.difference(_tickBaseAt);
    _tickBaseAt = now;
    _tickBaseMs += elapsed.inMilliseconds;

    final duration = state.durationMs;
    if (duration > 0 && _tickBaseMs >= duration) {
      // End of track: hold the last value rather than emitting a frozen
      // position that would kill AVRCP notifications; completion/next() resets
      // the base via [seekTo] or [_loadCurrent].
      _tickBaseMs = duration;
      return;
    }
    _publishMediaPosition(_tickBaseMs, buffered: _bufferedDuration);
  }

  /// Single gate for every position that reaches the media session.
  ///
  /// Guarantees the value never collapses below what the platform already saw —
  /// unless [force] marks an intentional discontinuity (seek / track change).
  /// Engine samples arrive on their own 200ms cadence, so a stale sample landing
  /// between two timer ticks would otherwise look like a backwards jump.
  void _publishMediaPosition(int ms, {Duration? buffered, bool force = false}) {
    var value = ms;
    if (!force) {
      if (value <= _lastPushedMs) value = _lastPushedMs + 1;
      if (value > _tickBaseMs) {
        // Re-anchor so the next timer computation continues from here.
        _tickBaseMs = value;
        _tickBaseAt = DateTime.now();
      }
    }
    _lastPushedMs = value;
    _bridge?.updatePosition(
      Duration(milliseconds: value),
      bufferedPosition: buffered ?? _bufferedDuration,
    );
  }

  /// Mirror the queue into the media session so head units can resolve the
  /// current item (only sent when it actually changed).
  void _syncQueueBridge() {
    final bridge = _bridge;
    final queue = state.queue;
    if (bridge == null || queue.isEmpty) return;
    final sig = '${state.currentIndex}:${queue.length}:'
        '${Object.hashAll([for (final t in queue) t.id])}';
    if (sig == _lastQueueSig) return;
    _lastQueueSig = sig;
    bridge.syncQueue(queue, state.currentIndex);
  }

  /// System media / Bluetooth secondary line: artist, or `artist · lyric`.
  String _mediaSubtitleFor(Track track) {
    final enabled = ref.read(settingsControllerProvider).mediaLyricSubtitle;
    if (!enabled) return track.artist;
    final line = _activeLyricText();
    if (line.isEmpty) return track.artist;
    return '${track.artist} · $line';
  }

  String _activeLyricText() {
    final lines = state.lyrics;
    if (lines.isEmpty) return '';
    var active = '';
    for (final line in lines) {
      if (line.timeMs > position.value) break;
      active = line.text.trim();
    }
    return active;
  }

  void _maybeUpdateMediaSubtitle() {
    final track = state.current;
    if (track == null || _bridge == null) return;
    final next = _mediaSubtitleFor(track);
    if (next == _lastMediaSubtitle) return;
    _lastMediaSubtitle = next;
    _bridge?.updateMediaSubtitle(next);
  }
}

/// Bridge used by the platform media handler to push system UI updates.
abstract class KugoMediaBridge {
  void sync({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
    Duration bufferedPosition = Duration.zero,
    Track? track,
    String? subtitle,
  });

  void updatePosition(Duration position, {Duration? bufferedPosition});

  /// Publish the current queue so the system/car UI can resolve the item.
  void syncQueue(List<Track> tracks, int currentIndex);

  /// Refresh lock-screen / Bluetooth secondary text without touching play state.
  void updateMediaSubtitle(String subtitle);
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

/// Live playback cursor. **Use this for progress bars, time labels, lyrics.**
///
/// Engine ticks only notify this listenable — assigning [PlayerState] on every
/// position sample used to rebuild every full-state watcher in the app.
final playerPositionProvider = Provider<ValueListenable<int>>((ref) {
  // Tie lifetime to the controller (created on first read, disposed with it).
  ref.watch(playerControllerProvider);
  return ref.read(playerControllerProvider.notifier).position;
});

/// Rebuilds only when the live playback cursor ticks (or [when] changes).
class PlayerPositionBuilder extends ConsumerWidget {
  const PlayerPositionBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, int positionMs) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listenable = ref.watch(playerPositionProvider);
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, ms, _) => builder(context, ms),
    );
  }
}

/// Factory for tests: inject a fake engine (and optional fake repos).
PlayerController createPlayerController(
  AudioPlayerPort engine, {
  LyricRepository? lyricRepo,
  PlayRepository? playRepo,
}) =>
    PlayerController(
      engine: engine,
      lyricRepo: lyricRepo,
      playRepo: playRepo,
    );

final currentTrackProvider = Provider<Track?>((ref) {
  return ref.watch(playerControllerProvider.select((s) => s.current));
});
