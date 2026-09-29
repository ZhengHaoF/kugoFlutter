import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/mv_models.dart';
import '../../core/platform.dart' show isWindowsPlatform;
import '../player/player_controller.dart';

/// MV 引擎宿主（应用级）的可见状态。
///
/// 只放低频、UI 需要 watch 的字段；高频游标（position 等）通过
/// [MvPlayerHostController] 上的 ValueListenable 暴露，不进 state——
/// 与音频侧 `PlayerController.position` 的隔离策略一致。
class MvHostState {
  const MvHostState({
    this.engineActive = false,
    this.mini = false,
    this.brief,
    this.rate = 1.0,
    this.volume = 100.0,
    this.muted = false,
    this.videoAspect = 16 / 9,
    this.controllerEpoch = 0,
  });

  /// 引擎是否存活（media_kit Player 已创建、未 shutdown）。
  final bool engineActive;

  /// 应用内浮动小窗（P2-3）是否显示。
  final bool mini;

  /// 当前会话的 MV：小窗回全页、会话匹配（takeover）用。
  final MvBrief? brief;

  /// 倍速（1.0 = 正常）。
  final double rate;

  /// 播放器音量，media_kit 量纲 0–100。
  final double volume;
  final bool muted;

  /// 视频宽高比（w/h）；无视频信号时 16:9。
  final double videoAspect;

  /// VideoController 重建计数（软解回退时 +1）。
  /// 页面 watch 到它变化即重挂 `Video` widget。
  final int controllerEpoch;

  MvHostState copyWith({
    bool? engineActive,
    bool? mini,
    MvBrief? brief,
    double? rate,
    double? volume,
    bool? muted,
    double? videoAspect,
    int? controllerEpoch,
  }) {
    return MvHostState(
      engineActive: engineActive ?? this.engineActive,
      mini: mini ?? this.mini,
      brief: brief ?? this.brief,
      rate: rate ?? this.rate,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      videoAspect: videoAspect ?? this.videoAspect,
      controllerEpoch: controllerEpoch ?? this.controllerEpoch,
    );
  }
}

/// MV 播放引擎宿主（P2 前置重构）：把 media_kit `Player` / `VideoController`
/// 从 `MvPlayerPage` 的 State 提升到应用级，支撑三类形态——
///
/// * 全页播放（页面挂 `Video`，退页即停）；
/// * 应用内浮动小窗（P2-3，页面 pop 后引擎继续活）；
/// * Android 系统画中画（P2-1，Activity 缩小、纹理照常渲染）。
///
/// 取流 / 多地址重试 / 软解回退等引擎策略从页面原样搬来；页面只负责 UI。
class MvPlayerHostController extends Notifier<MvHostState> {
  Player? _player;
  VideoController? _videoController;

  // ── 引擎游标（页面与小窗共用，不进 state）──
  final ValueNotifier<int> _positionMs = ValueNotifier(0);
  final ValueNotifier<int> _durationMs = ValueNotifier(0);
  final ValueNotifier<int> _bufferedMs = ValueNotifier(0);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final ValueNotifier<String> _engineError = ValueNotifier('');

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;
  StreamSubscription<String>? _errorSub;
  Timer? _swFallbackTimer;

  /// Windows 硬解经常「有声有进度无画」且 width/height 照样上报，
  /// 软解回退判据踩空；直接默认软解。其它平台仍硬解优先。
  bool _hwAccel = !isWindowsPlatform;
  bool _swFallbackTried = false;
  bool _started = false;
  String _lastMediaUrl = '';
  Map<String, String> _httpHeaders = const {};
  int _videoWidth = 0;
  int _videoHeight = 0;

  @override
  MvHostState build() {
    // Provider 释放（应用退出）时同步拆引擎。
    ref.onDispose(() => _disposeEngine(resetState: false));
    // 音乐起播时自动暂停 MV：小窗播放中用户点了首歌，避免双声。
    // （MV 页进入时本来就会暂停音乐，这里兜的是小窗形态。）
    ref.listen(playerControllerProvider, (prev, next) {
      if (prev?.isPlaying != next.isPlaying &&
          next.isPlaying &&
          state.engineActive &&
          _playing.value) {
        pause();
      }
    });
    return const MvHostState();
  }

  // ── 对外只读句柄 ──

  VideoController? get videoController => _videoController;
  ValueListenable<int> get position => _positionMs;
  ValueListenable<int> get duration => _durationMs;
  ValueListenable<int> get buffered => _bufferedMs;
  ValueListenable<bool> get playing => _playing;
  ValueListenable<String> get engineError => _engineError;

  /// 是否已成功发起过 open（取流失败重试前为 false）。
  bool get started => _started;

  // ── 会话生命周期 ──

  /// 同曲会话接管（从小窗 / 列表重复入口回到全页）：不重拉、不重开引擎。
  /// 返回 false 表示无活跃会话，页面走正常 load。
  bool takeover(MvBrief brief) {
    if (!state.engineActive || !sessionMatches(brief)) return false;
    state = state.copyWith(mini: false);
    return true;
  }

  bool sessionMatches(MvBrief brief) {
    final cur = state.brief;
    if (cur == null) return false;
    if (brief.id.isNotEmpty && brief.id == cur.id) return true;
    if (brief.hash.isNotEmpty && brief.hash == cur.hash) return true;
    return false;
  }

  /// 缩为应用内浮动小窗：引擎保持存活，页面 pop 时不再 shutdown。
  void enterMini() {
    if (!state.engineActive || state.mini) return;
    state = state.copyWith(mini: true);
  }

  void exitMini() {
    if (!state.mini) return;
    state = state.copyWith(mini: false);
  }

  /// 结束会话：销毁引擎、释放常亮与小窗。幂等。
  Future<void> shutdown() async {
    _disposeEngine();
  }

  /// 播放失败重试前的复位：保住引擎，重置 open 状态与解码策略，
  /// 让随后的 `load` → `openPlayUrl` 能完整重走地址重试链。
  void resetForRetry() {
    _engineError.value = '';
    _started = false;
    _swFallbackTried = false;
    _swFallbackTimer?.cancel();
    _swFallbackTimer = null;
    _hwAccel = !isWindowsPlatform;
    _lastMediaUrl = '';
    _httpHeaders = const {};
  }

  // ── 取流（多地址重试 + 软解回退，自页面原样迁移）──

  /// 页面 load 完成后喂数据：先挂控制器再 open，与 media_kit 官方示例一致。
  Future<void> openPlayUrl(
    MvBrief brief,
    MvPlayUrlResult play, {
    int resumeMs = 0,
  }) async {
    if (play.allUrls.isEmpty) return;
    // 同一地址已 open / 正在 open：跳过（load 路径 listener 与 bootstrap 会各触发一次）。
    if (_started && play.url == _lastMediaUrl) return;
    _ensureEngine();
    // 打开新 MV 视为全页会话：小窗让位（从小窗跳转其它 MV 的场景）。
    state = state.copyWith(brief: brief, mini: false);
    _started = true;
    // 看视频期间保持屏幕常亮（shutdown 释放）。
    unawaited(_setWakelock(true));
    final seekTo = resumeMs;
    _engineError.value = '';
    _httpHeaders = play.headers;
    _lastMediaUrl = play.url;

    // 依次尝试：主地址（带防盗链头）→ 主地址（裸）→ 备用地址。
    // EchoMusic 网页端是裸 URL 直出，说明头不是必须；但带上更稳。
    final attempts = <(String, Map<String, String>)>[
      (play.url, play.headers),
      (play.url, const {}),
      for (final b in play.backupUrls) (b, play.headers),
      for (final b in play.backupUrls) (b, const {}),
    ];
    Object? lastErr;
    for (final (url, hdr) in attempts) {
      final p = _player;
      if (p == null) return;
      _lastMediaUrl = url;
      _httpHeaders = hdr;
      try {
        await p.open(
          Media(url, httpHeaders: hdr.isEmpty ? null : hdr),
          play: true,
        );
        if (seekTo > 0) {
          await p.seek(Duration(milliseconds: seekTo));
        }
        // open 换流后重放倍速（mpv 的 speed 属性可能被重置）。
        if (state.rate != 1.0) {
          await p.setRate(state.rate);
        }
        _armSwFallback(seekTo);
        return;
      } catch (e) {
        lastErr = e;
        continue;
      }
    }
    _engineError.value = lastErr == null ? '无法打开视频地址' : '$lastErr';
  }

  // ── 播控 ──

  void togglePlay() {
    final p = _player;
    if (p == null || !_started) return;
    if (p.state.playing) {
      p.pause();
    } else {
      p.play();
    }
  }

  void pause() {
    final p = _player;
    if (p == null || !_started) return;
    if (p.state.playing) p.pause();
  }

  void seekTo(double progress) {
    final p = _player;
    final dur = _durationMs.value;
    if (p == null || dur <= 0) return;
    final ms = (progress * dur).round().clamp(0, dur);
    p.seek(Duration(milliseconds: ms));
    _positionMs.value = ms;
  }

  /// 相对当前进度快进/快退 [deltaMs] 毫秒。
  void seekBy(int deltaMs) {
    final p = _player;
    final dur = _durationMs.value;
    if (p == null || dur <= 0) return;
    final ms = (_positionMs.value + deltaMs).clamp(0, dur);
    p.seek(Duration(milliseconds: ms));
    _positionMs.value = ms;
  }

  // ── 倍速 / 音量 ──

  void setRate(double rate) {
    if (state.rate == rate) return;
    unawaited(_player?.setRate(rate));
    state = state.copyWith(rate: rate);
  }

  void toggleMute() {
    if (state.muted) {
      final v = state.volume <= 0 ? 50.0 : state.volume;
      unawaited(_player?.setVolume(v));
      state = state.copyWith(muted: false, volume: v);
    } else {
      unawaited(_player?.setVolume(0));
      state = state.copyWith(muted: true);
    }
  }

  /// 直接设定音量（手势/键盘路径，0 即静音）。
  void setVolume(double v) {
    final value = v.clamp(0.0, 100.0);
    unawaited(_player?.setVolume(value));
    state = state.copyWith(volume: value, muted: value <= 0);
  }

  // ── 引擎内部 ──

  void _ensureEngine() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _videoController = _createController(p);
    _posSub = p.stream.position.listen((d) {
      _positionMs.value = d.inMilliseconds;
    });
    _durSub = p.stream.duration.listen((d) {
      _durationMs.value = d.inMilliseconds;
    });
    _bufferSub = p.stream.buffer.listen((d) {
      _bufferedMs.value = d.inMilliseconds;
    });
    _playingSub = p.stream.playing.listen((v) {
      _playing.value = v;
      if (v) _engineError.value = '';
    });
    // 视频轨宽高：出画的唯一可靠信号（软解回退判据），顺带喂宽高比给小窗。
    _widthSub = p.stream.width.listen(_onVideoSize);
    _heightSub = p.stream.height.listen(_onVideoSize);
    _errorSub = p.stream.error.listen((msg) {
      _engineError.value = msg;
    });
    state = state.copyWith(engineActive: true);
  }

  VideoController _createController(Player p) {
    return VideoController(
      p,
      configuration: VideoControllerConfiguration(
        // Windows 默认软解（见 _hwAccel）；其它平台硬解，失败再降级。
        enableHardwareAcceleration: _hwAccel,
        hwdec: _hwAccel ? null : 'no',
      ),
    );
  }

  void _onVideoSize(int? _) {
    final p = _player;
    if (p == null) return;
    final w = p.state.width ?? 0;
    final h = p.state.height ?? 0;
    if (w == _videoWidth && h == _videoHeight) return;
    _videoWidth = w;
    _videoHeight = h;
    if (w > 0 && h > 0) {
      _swFallbackTimer?.cancel();
      _swFallbackTimer = null;
      final aspect = w / h;
      if ((state.videoAspect - aspect).abs() > 0.01) {
        state = state.copyWith(videoAspect: aspect);
      }
    }
  }

  /// 有声音、有进度，但 N 秒后仍无视频宽高 → 判定硬解黑屏，降级软解重开。
  void _armSwFallback(int seekTo) {
    _swFallbackTimer?.cancel();
    if (_swFallbackTried || !_hwAccel) return;
    _swFallbackTimer = Timer(const Duration(seconds: 3), () {
      final p = _player;
      if (p == null) return;
      if ((p.state.width ?? 0) > 0 && (p.state.height ?? 0) > 0) {
        return; // 已经出画
      }
      // 还在 loading / 没起播就先不降级，避免误判。
      if (_durationMs.value <= 0 && !_playing.value) return;
      _swFallbackTried = true;
      _hwAccel = false;
      unawaited(_recreateControllerForSoftDecode(seekTo: seekTo));
    });
  }

  /// 硬解黑屏时丢掉 controller 再建；Player 本体复用。
  Future<void> _recreateControllerForSoftDecode({required int seekTo}) async {
    final p = _player;
    if (p == null) return;
    _videoController = _createController(p);
    // 通知页面重挂 Video（新 controller 实例）。
    state = state.copyWith(controllerEpoch: state.controllerEpoch + 1);
    final url = _lastMediaUrl;
    if (url.isEmpty) return;
    try {
      await p.open(
        Media(url, httpHeaders: _httpHeaders.isEmpty ? null : _httpHeaders),
        play: true,
      );
      if (seekTo <= 0) return;
      await p.seek(Duration(milliseconds: seekTo));
    } catch (e) {
      _engineError.value = '软解重开失败：$e';
    }
  }

  /// 屏幕常亮是「尽力而为」：binding 未初始化（纯 dart 单测）或平台无实现
  /// 时静默失败，不影响播放主流程。
  Future<void> _setWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _disposeEngine({bool resetState = true}) {
    final p = _player;
    _player = null;
    _videoController = null;
    _started = false;
    _lastMediaUrl = '';
    _httpHeaders = const {};
    _swFallbackTimer?.cancel();
    _swFallbackTimer = null;
    _swFallbackTried = false;
    _hwAccel = !isWindowsPlatform;
    unawaited(_posSub?.cancel());
    unawaited(_durSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_bufferSub?.cancel());
    unawaited(_widthSub?.cancel());
    unawaited(_heightSub?.cancel());
    unawaited(_errorSub?.cancel());
    _posSub = null;
    _durSub = null;
    _playingSub = null;
    _bufferSub = null;
    _widthSub = null;
    _heightSub = null;
    _errorSub = null;
    _positionMs.value = 0;
    _durationMs.value = 0;
    _bufferedMs.value = 0;
    _playing.value = false;
    _engineError.value = '';
    _videoWidth = 0;
    _videoHeight = 0;
    unawaited(_setWakelock(false));
    if (p != null) {
      // 同步释放，避免会话结束后仍占解码器。
      // ignore: discarded_futures
      p.dispose();
    }
    if (resetState) state = const MvHostState();
  }
}

final mvPlayerHostProvider =
    NotifierProvider<MvPlayerHostController, MvHostState>(
      MvPlayerHostController.new,
    );
