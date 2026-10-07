import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/platform.dart';
import '../player/player_controller.dart';
import '../settings/settings_controller.dart';
import 'desktop_lyric_ipc.dart';
import 'desktop_lyric_protocol.dart';
import 'desktop_lyric_store.dart';

void lyricLog(String msg) {
  debugPrint('[desktop_lyric] $msg');
}

/// 启动时是否自动恢复上次开着的桌面歌词窗。
///
/// 双进程方案下子窗与主窗隔离，可以打开；仍保留开关便于一键回退。
const bool kAutoRestoreDesktopLyric = true;

/// 主窗侧桌面歌词桥：组装 snapshot、spawn 歌词进程、收歌词进程命令。
///
/// 通信走 [LyricIpc]（TCP 换行 JSON），**不再用 desktop_multi_window**：
/// dmw 的 Windows 多引擎会踩坏主窗 task runner（见 桌面歌词接入方案.md §12）。
class DesktopLyricBridge {
  DesktopLyricBridge(this._container);

  final ProviderContainer _container;

  LyricIpcServer? _server;
  LyricIpcWriter? _writer;
  LyricIpcReader? _reader;
  StreamSubscription<Map<String, Object?>>? _msgSub;
  StreamSubscription<Socket>? _connSub;
  Process? _process;

  bool _handlerReady = false;
  bool _windowOpen = false;
  bool _childReady = false;
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

  /// 启动时挂载：恢复 bounds、起 IPC server、监听播放/设置变化。
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
      if (!_windowOpen || !_childReady) return;
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
      if (!_windowOpen || !_childReady) return;
      if (prev?.lyricTranslation != next.lyricTranslation ||
          prev?.lyricRomanization != next.lyricRomanization ||
          prev?.lyricFontScale != next.lyricFontScale ||
          prev?.desktopLyricLocked != next.desktopLyricLocked ||
          prev?.desktopLyricStyle != next.desktopLyricStyle) {
        unawaited(_pushSnapshot());
      }
    });

    // 开机自启（上次开着）：延迟一拍等主窗就绪。双进程下子窗与主窗引擎隔离，
    // 不会再踩坏主窗 task runner（§12），可安全恢复。
    if (_settings.desktopLyricEnabled && kAutoRestoreDesktopLyric) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 800), open));
    } else if (_settings.desktopLyricEnabled) {
      unawaited(_container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(false));
    }
  }

  Future<void> _ensureHandler() async {
    if (_handlerReady) return;
    _handlerReady = true;
    // 无 dmw channel：命令走 IPC，见 _onIpcMessage。
  }

  void _onIpcMessage(Map<String, Object?> msg) {
    if (msg['t'] != LyricIpc.typeCmd) return;
    final method = msg['m'] as String? ?? '';
    final args = msg['d'];
    unawaited(_handleCmd(method, args));
  }

  Future<void> _handleCmd(String method, Object? args) async {
    switch (method) {
      case DesktopLyricCommand.ready:
        _childReady = true;
        _lyricsDirty = true;
        _startPositionTimer();
        // 异步推 snapshot，避免堵在读帧回调里。
        Timer.run(() {
          if (_windowOpen && _childReady) {
            unawaited(_pushSnapshot(forceLyrics: true));
          }
        });
      case DesktopLyricCommand.playPause:
        _player.togglePlay();
      case DesktopLyricCommand.next:
        unawaited(_player.next());
      case DesktopLyricCommand.previous:
        unawaited(_player.previous());
      case DesktopLyricCommand.close:
        unawaited(close());
      case DesktopLyricCommand.toggleLock:
        unawaited(_container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricLocked(!_settings.desktopLyricLocked));
      case DesktopLyricCommand.bounds:
        final b = DesktopLyricBounds.fromWire(args);
        _bounds = b;
        await DesktopLyricBoundsStore.save(b);
      case DesktopLyricCommand.closed:
        _windowOpen = false;
        _childReady = false;
        _stopPositionTimer();
        await _container
            .read(settingsControllerProvider.notifier)
            .setDesktopLyricEnabled(false);
    }
  }

  /// 打开（已存在则显示）。幂等；并发调用会合并到同一次 spawn。
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

    // 1. 歌词进程仍在：直接 show（hide/show 复用，不重复 spawn）。
    // 每次显示都回屏幕顶部居中，保持默认位稳定（用户拖动仅在当次会话有效）。
    if (_childReady && _writer?.isOpen == true) {
      _windowOpen = true;
      _writer!.send(LyricIpc.signal(LyricIpc.typeReposition));
      _writer!.send(LyricIpc.signal(LyricIpc.typeShow));
      _startPositionTimer();
      Timer.run(() {
        if (_windowOpen && _childReady) {
          unawaited(_pushSnapshot(forceLyrics: true));
        }
      });
      unawaited(_container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(true));
      return;
    }

    // 2. 首次：起 IPC server → spawn 歌词进程 → 等它连上。
    try {
      final server = LyricIpcServer();
      final port = await server.listen();
      _server = server;

      _connSub = server.connections?.listen((s) => unawaited(_onConnected(s)));
      if (_connSub == null) {
        throw StateError('lyric ipc server has no connection stream');
      }

      final exe = Platform.resolvedExecutable;
      final exeDir = File(exe).parent.path;
      lyricLog('spawn lyric process: $exe dir=$exeDir port=$port');
      final process = await Process.start(
        exe,
        [LyricIpc.argProcess, '${LyricIpc.argPortPrefix}$port'],
        workingDirectory: exeDir,
        environment: {
          ...Platform.environment,
          LyricIpc.envProcess: '1',
          LyricIpc.envPort: '$port',
        },
      );
      _process = process;
      process.exitCode.then((code) {
        lyricLog('lyric process exit code=$code');
        if (_process == process) {
          _process = null;
          _windowOpen = false;
          _childReady = false;
          _stopPositionTimer();
          unawaited(_teardownIpc());
        }
      }).catchError((_) {});

      _windowOpen = true;
      _childReady = false;
      _lyricsDirty = true;
      unawaited(_container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(true));
    } catch (e, st) {
      debugPrint('[desktop_lyric] open failed: $e\n$st');
      _windowOpen = false;
      _childReady = false;
      await _teardownIpc();
    }
  }

  Future<void> _onConnected(Socket socket) async {
    lyricLog('lyric process connected');
    // 单连接：后连上的顶掉旧的（异常残留）。
    await _reader?.close();
    await _writer?.close();
    await _msgSub?.cancel();

    final reader = LyricIpcReader(socket);
    _reader = reader;
    _writer = LyricIpcWriter(socket);
    _msgSub = reader.messages.listen(_onIpcMessage);
    _childReady = false;
    // ready 由歌词进程主动发；连上后由其 ready 触发首帧 snapshot。
  }

  Future<void> _teardownIpc() async {
    await _msgSub?.cancel();
    _msgSub = null;
    await _reader?.close();
    _reader = null;
    await _writer?.close();
    _writer = null;
    await _connSub?.cancel();
    _connSub = null;
    await _server?.close();
    _server = null;
    _childReady = false;
  }

  Future<void> close() async {
    _stopPositionTimer();
    _windowOpen = false;
    // 隐藏歌词窗，保留进程与连接，下次 open 秒开。
    _writer?.send(LyricIpc.signal(LyricIpc.typeHide));
    unawaited(_container
        .read(settingsControllerProvider.notifier)
        .setDesktopLyricEnabled(false));
  }

  Future<void> toggle() async {
    if (_windowOpen) {
      await close();
    } else {
      await open();
    }
  }

  /// 重置歌词窗位置：清掉存档坐标，并让已开的窗立刻回顶部居中。
  Future<void> resetPosition() async {
    await DesktopLyricBoundsStore.clearPosition();
    _bounds = const DesktopLyricBounds();
    _writer?.send(LyricIpc.signal(LyricIpc.typeReposition));
  }

  /// 主窗退出前调用：杀掉歌词进程并关掉 IPC。
  Future<void> shutdown() async {
    _stopPositionTimer();
    _windowOpen = false;
    _childReady = false;
    final p = _process;
    _process = null;
    try {
      _writer?.send(LyricIpc.signal(LyricIpc.typeClose));
    } catch (_) {}
    await _teardownIpc();
    if (p != null) {
      try {
        p.kill();
      } catch (_) {}
    }
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    // 对时：播放中低频推 position，歌词进程本地 Ticker 自走。
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
    if (!_windowOpen || !_childReady) return;
    final writer = _writer;
    if (writer == null || !writer.isOpen) return;

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
      // 始终用实时游标：`state.positionMs` 只在离散跳变（seek/换曲）时同步，
      // 播放中不更新。若暂停那一刻推它，子窗会跳到旧位置对应的行、恢复后才纠正。
      positionMs: _player.position.value,
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
      style: s.desktopLyricStyle,
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

    writer.send(LyricIpc.snapshot(wire));
  }

  /// 窗口 bounds（歌词进程启动时读取）。
  DesktopLyricBounds get bounds => _bounds;
}

final desktopLyricBridgeProvider = Provider<DesktopLyricBridge>((ref) {
  final b = DesktopLyricBridge.instance;
  if (b == null) {
    throw StateError('DesktopLyricBridge.boot() has not run yet');
  }
  return b;
});
