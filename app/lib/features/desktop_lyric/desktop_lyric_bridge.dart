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
    if (_settings.desktopLyricEnabled) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 800), open));
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
        await _pushSnapshot(forceLyrics: true);
        return 'ok';
      case DesktopLyricCommand.playPause:
        _player.togglePlay();
        return 'ok';
      case DesktopLyricCommand.next:
        await _player.next();
        return 'ok';
      case DesktopLyricCommand.previous:
        await _player.previous();
        return 'ok';
      case DesktopLyricCommand.close:
        unawaited(close());
        return 'ok';
      case DesktopLyricCommand.toggleLock:
        await _container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricLocked(!_settings.desktopLyricLocked);
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
            await c.invokeMethod('close');
          } catch (_) {
            try {
              await c.hide();
            } catch (_) {}
          }
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
    try {
      if (win != null) {
        await win.invokeMethod('close');
      }
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
