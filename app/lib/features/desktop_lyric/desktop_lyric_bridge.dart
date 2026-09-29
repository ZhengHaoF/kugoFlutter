import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';
import 'desktop_lyric_protocol.dart';
import 'desktop_lyric_store.dart';

void lyricLog(String msg) {
  debugPrint('[desktop_lyric] $msg');
}

/// 启动时是否自动恢复上次开着的桌面歌词窗。
///
/// Windows 上必须为 false：歌词窗（dmw 子窗）会让主窗假死，自动恢复等于启动
/// 即死。见 桌面歌词接入方案.md §12。
const bool kAutoRestoreDesktopLyric = false;

/// 主窗侧桌面歌词桥：组装 snapshot、管子窗生命周期、收歌词窗命令。
///
/// 对齐 EchoMusic 主进程职责：唯一 snapshot / 切歌 revision / 回传命令执行。
/// 歌词窗自身不碰播放。
class DesktopLyricBridge {
  DesktopLyricBridge(this._container);

  final ProviderContainer _container;
  final WindowMethodChannel _channel =
      const WindowMethodChannel(kDesktopLyricChannel);

  WindowController? _window;
  bool _handlerReady = false;
  bool _windowOpen = false;
  bool _opening = false;
  int _revision = 0;
  String? _lastLyricKey;
  DesktopLyricBounds _bounds = const DesktopLyricBounds();
  Timer? _positionTimer;
  int _lastPushedPos = -1;
  bool _lyricsDirty = true;

  bool get isOpen => _windowOpen;

  PlayerController get _player =>
      _container.read(playerControllerProvider.notifier);

  PlayerState get _playerState => _container.read(playerControllerProvider);

  AppSettings get _settings => _container.read(settingsControllerProvider);

  /// 启动时挂载：恢复 bounds、注册命令 handler、监听播放/设置变化。
  static Future<DesktopLyricBridge> boot(ProviderContainer container) async {
    final bridge = DesktopLyricBridge(container);
    instance = bridge;
    if (!isDesktopPlatform) return bridge;
    await bridge._start();
    return bridge;
  }

  /// 已 boot 的桥。设置页 / 托盘经 [desktopLyricBridgeProvider] 访问。
  static DesktopLyricBridge? instance;

  Future<void> _start() async {
    _bounds = await DesktopLyricBoundsStore.load();
    await _ensureHandler();

    _container.listen<PlayerState>(playerControllerProvider, (prev, next) {
      if (!_windowOpen) return;
      final trackChanged = prev?.current?.identityKey != next.current?.identityKey;
      final lyricsChanged = !identical(prev?.lyrics, next.lyrics) ||
          prev?.lyricsStatus != next.lyricsStatus;
      final playChanged = prev?.isPlaying != next.isPlaying;
      final discretePos = prev?.positionMs != next.positionMs &&
          (trackChanged || playChanged || lyricsChanged);
      if (trackChanged || lyricsChanged) _lyricsDirty = true;
      if (trackChanged || lyricsChanged || playChanged || discretePos) {
        unawaited(_pushSnapshot(forceLyrics: trackChanged || lyricsChanged));
      }
    });

    _container.listen<AppSettings>(settingsControllerProvider, (prev, next) {
      if (!_windowOpen) return;
      if (prev?.lyricTranslation != next.lyricTranslation ||
          prev?.lyricRomanization != next.lyricRomanization ||
          prev?.lyricFontScale != next.lyricFontScale ||
          prev?.desktopLyricLocked != next.desktopLyricLocked) {
        unawaited(_pushSnapshot());
      }
    });

    // 开机自启（上次开着）：延迟一拍等主窗就绪。
    //
    // ⚠️ 2026-09-30 停用自动恢复：dmw 子窗一出现就会踩坏主窗引擎的 task
    // runner（`Failed to post message to main thread`），主窗随即假死；而
    // `desktopLyricEnabled` 一旦为 true，每次启动都会在 800ms 后自动开窗，
    // 等于**启动即死**——连 flutter run 都连不上（报 Error connecting to the
    // service protocol）。详见 桌面歌词接入方案.md §12。
    // 等桌面歌词在 Windows 上稳定后把 kAutoRestoreDesktopLyric 改回 true。
    if (_settings.desktopLyricEnabled && kAutoRestoreDesktopLyric) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 800), open));
    } else if (_settings.desktopLyricEnabled) {
      // 清掉上次残留的开启态，否则设置页显示「已开启」而窗口其实没开。
      unawaited(_container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(false));
    }
  }

  Future<void> _ensureHandler() async {
    if (_handlerReady) return;
    await _channel.setMethodCallHandler(_onLyricCall);
    _handlerReady = true;
  }

  Future<dynamic> _onLyricCall(MethodCall call) async {
    switch (call.method) {
      case DesktopLyricCommand.ready:
        _lyricsDirty = true;
        // 不要在这里 await push：同通道嵌套 invokeMethod（ready → snapshot）
        // 在 Windows 多引擎下会堵死 platform 线程，表现为开词后假死。
        unawaited(_pushSnapshot(forceLyrics: true));
        return 'ok';
      case DesktopLyricCommand.playPause:
        _player.togglePlay();
        return 'ok';
      case DesktopLyricCommand.next:
        // 切歌可能做网络解析，别堵在通道 handler 里。
        unawaited(_player.next());
        return 'ok';
      case DesktopLyricCommand.previous:
        unawaited(_player.previous());
        return 'ok';
      case DesktopLyricCommand.close:
        unawaited(close());
        return 'ok';
      case DesktopLyricCommand.toggleLock:
        // 立刻回包；设置写入与 snapshot 由 listener 异步推。
        unawaited(_container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricLocked(!_settings.desktopLyricLocked));
        return 'ok';
      case DesktopLyricCommand.bounds:
        final b = DesktopLyricBounds.fromWire(call.arguments);
        _bounds = b;
        await DesktopLyricBoundsStore.save(b);
        return 'ok';
      case DesktopLyricCommand.closed:
        _windowOpen = false;
        _window = null;
        _stopPositionTimer();
        await _container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricEnabled(false);
        return 'ok';
      default:
        return null;
    }
  }

  /// 打开（已存在则前置）。幂等；并发调用会合并到同一次 create。
  Future<void> open() async {
    if (!isDesktopPlatform) return;
    if (_opening) return;
    _opening = true;
    try {
      await _openInner();
    } finally {
      _opening = false;
    }
  }

  Future<void> _openInner() async {
    await _ensureHandler();
    if (_windowOpen && _window != null) {
      try {
        await _window!.show();
        return;
      } catch (_) {}
    }

    // 只保留一个歌词窗：异常残留的多余实例直接关掉，避免叠两层「当前词」。
    try {
      final all = await WindowController.getAll();
      WindowController? keep;
      for (final c in all) {
        if (c.arguments != kDesktopLyricWindowArg) continue;
        if (keep == null) {
          keep = c;
        } else {
          try {
            await c.hide();
          } catch (_) {}
        }
      }
      if (keep != null) {
        _window = keep;
        _windowOpen = true;
        await keep.show();
        _startPositionTimer();
        await _pushSnapshot(forceLyrics: true);
        await _container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricEnabled(true);
        return;
      }
    } catch (_) {}

    try {
      final win = await WindowController.create(
        const WindowConfiguration(
          arguments: kDesktopLyricWindowArg,
          hiddenAtLaunch: true,
        ),
      );
      _window = win;
      _windowOpen = true;
      _lyricsDirty = true;
      _startPositionTimer();
      await _container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(true);
      // 只在子窗 ready 后推 snapshot：init 阶段并发调 window_manager 会死锁。
    } catch (e, st) {
      debugPrint('[desktop_lyric] open failed: $e\n$st');
      _windowOpen = false;
      _window = null;
    }
  }

  Future<void> close() async {
    _stopPositionTimer();
    final win = _window;
    _window = null;
    _windowOpen = false;
    // 走歌词通道让子窗自毁。WindowController.invokeMethod('close') 打的是
    // mixin.one/window_controller/*，子窗从未 setWindowMethodHandler，只会 hide 残留。
    try {
      await _channel.invokeMethod('close');
    } catch (_) {
      try {
        await win?.hide();
      } catch (_) {}
    }
    await _container
        .read(settingsControllerProvider.notifier)
        .setDesktopLyricEnabled(false);
  }

  Future<void> toggle() async {
    if (_windowOpen) {
      await close();
    } else {
      await open();
    }
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    // 对时：播放中低频推 position，歌词窗本地 Ticker 自走。
    _positionTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!_windowOpen) return;
      if (!_playerState.isPlaying) return;
      final pos = _player.position.value;
      if ((pos - _lastPushedPos).abs() < 80) return;
      unawaited(_pushSnapshot(positionOnly: true));
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
    _lastPushedPos = -1;
  }

  Future<void> _pushSnapshot({bool forceLyrics = false, bool positionOnly = false}) async {
    if (!_windowOpen) return;
    final state = _playerState;
    final track = state.current;
    final lyrics = state.lyrics;
    final hash = desktopLyricHash(lyrics);
    final lyricKey = '${track?.identityKey ?? ''}|$hash|${state.lyricsStatus.name}';
    if (lyricKey != _lastLyricKey) {
      _lastLyricKey = lyricKey;
      _revision++;
      _lyricsDirty = true;
    }

    final s = _settings;
    final snap = DesktopLyricSnapshot(
      trackId: track?.identityKey ?? '',
      title: track?.name ?? '',
      artist: track?.artist ?? '',
      isPlaying: state.isPlaying,
      positionMs: positionOnly ? _player.position.value : state.positionMs,
      durationMs: state.durationMs,
      lyrics: lyrics,
      lyricsReady: state.lyricsStatus == LyricsStatus.ready,
      lyricHash: hash,
      revision: _revision,
      translation: s.lyricTranslation,
      romanization: s.lyricRomanization,
      fontScale: s.lyricFontScale,
      locked: s.desktopLyricLocked,
      offsetMs: s.desktopLyricOffsetMs,
    );

    final pos = snap.positionMs;
    if (positionOnly && !_lyricsDirty && (pos - _lastPushedPos).abs() < 80) {
      return;
    }
    _lastPushedPos = pos;

    // 歌词很重：仅在 dirty/force 时带上完整数组，平时只推游标与播放态。
    final wire = snap.toWire();
    if (positionOnly && !_lyricsDirty && !forceLyrics) {
      wire['lyrics'] = const [];
      wire['lyricsOmitted'] = true;
    } else {
      _lyricsDirty = false;
    }

    try {
      await _channel.invokeMethod('snapshot', wire);
    } catch (e) {
      debugPrint('[desktop_lyric] push snapshot failed: $e');
    }
  }

  /// 窗口 bounds（歌词窗启动时读取）。
  DesktopLyricBounds get bounds => _bounds;
}

final desktopLyricBridgeProvider = Provider<DesktopLyricBridge>((ref) {
  final b = DesktopLyricBridge.instance;
  if (b == null) {
    throw StateError('DesktopLyricBridge.boot() has not run yet');
  }
  return b;
});
