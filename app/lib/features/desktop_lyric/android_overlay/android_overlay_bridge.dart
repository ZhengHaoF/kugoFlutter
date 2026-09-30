import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/track.dart';
import '../../../core/platform.dart';
import '../../player/player_controller.dart';
import '../../settings/settings_controller.dart';
import '../desktop_lyric_protocol.dart';
import '../desktop_lyric_store.dart';
import 'android_overlay_host.dart';

void androidLyricLog(String msg) {
  debugPrint('[android_lyric] $msg');
}

/// Android 悬浮歌词桥：组装 snapshot，经 MethodChannel 推给原生 Overlay。
///
/// 与桌面端 [DesktopLyricBridge] 共享 [DesktopLyricSnapshot] 协议与设置字段，
/// 但传输层是同进程 MethodChannel，不 spawn 歌词进程。
class AndroidLyricBridge {
  AndroidLyricBridge(this._container);

  final ProviderContainer _container;

  bool _ready = false;
  bool _open = false;
  bool _opening = false;
  int _revision = 0;
  String? _lastLyricKey;
  int _lastPushedPos = -1;
  bool _lyricsDirty = true;
  Timer? _positionTimer;

  static AndroidLyricBridge? instance;

  bool get isOpen => _open;

  PlayerController get _player =>
      _container.read(playerControllerProvider.notifier);

  PlayerState get _playerState => _container.read(playerControllerProvider);

  AppSettings get _settings => _container.read(settingsControllerProvider);

  static Future<AndroidLyricBridge> boot(ProviderContainer container) async {
    final bridge = AndroidLyricBridge(container);
    instance = bridge;
    if (!isAndroidPlatform) return bridge;
    await bridge._start();
    return bridge;
  }

  Future<void> _start() async {
    // 位置持久化仍走 DesktopLyricBoundsStore（与桌面端同一套键）。
    await DesktopLyricBoundsStore.load();
    _ready = true;

    AndroidOverlayHost.setCommandHandler(_onCommand);

    _container.listen<PlayerState>(playerControllerProvider, (prev, next) {
      if (!_open) return;
      final trackChanged =
          prev?.current?.identityKey != next.current?.identityKey;
      final lyricsChanged = !identical(prev?.lyrics, next.lyrics) ||
          prev?.lyricsStatus != next.lyricsStatus;
      final playChanged = prev?.isPlaying != next.isPlaying;
      final discretePos = prev?.positionMs != next.positionMs &&
          (trackChanged || playChanged || lyricsChanged);
      if (trackChanged || lyricsChanged) _lyricsDirty = true;
      if (trackChanged || lyricsChanged || playChanged || discretePos) {
        unawaited(
          _pushSnapshot(forceLyrics: trackChanged || lyricsChanged),
        );
      }
    });

    _container.listen<AppSettings>(settingsControllerProvider, (prev, next) {
      if (!_open) return;
      if (prev?.lyricTranslation != next.lyricTranslation ||
          prev?.lyricRomanization != next.lyricRomanization ||
          prev?.lyricFontScale != next.lyricFontScale ||
          prev?.desktopLyricLocked != next.desktopLyricLocked ||
          prev?.desktopLyricOffsetMs != next.desktopLyricOffsetMs ||
          prev?.desktopLyricStyle != next.desktopLyricStyle) {
        unawaited(_pushSnapshot());
      }
    });

    // 上次开着则自动恢复（权限可能被系统收回，open() 内会检测）。
    if (_settings.desktopLyricEnabled) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), open));
    }
  }

  void _onCommand(String method, Map<String, Object?> data) {
    unawaited(_handleCmd(method, data));
  }

  Future<void> _handleCmd(String method, Map<String, Object?> data) async {
    switch (method) {
      case DesktopLyricCommand.playPause:
      case 'tap':
        // 未锁定轻点 = 播放/暂停（锁定态点击已穿透，到不了这里）。
        _player.togglePlay();
      case 'longPress':
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
        await DesktopLyricBoundsStore.save(DesktopLyricBounds.fromWire(data));
    }
  }

  /// 打开悬浮歌词。无权限时返回 false 并保持设置为关。
  Future<bool> open() async {
    if (!isAndroidPlatform || !_ready) return false;
    if (_open) return true;
    if (_opening) return false;
    _opening = true;
    try {
      final can = await AndroidOverlayHost.canDrawOverlays();
      if (!can) {
        androidLyricLog('overlay permission denied');
        return false;
      }
      _lyricsDirty = true;
      final bounds = await DesktopLyricBoundsStore.load();
      final ok = await AndroidOverlayHost.show(
        _buildWire(forceLyrics: true),
        boundsX: bounds.x?.round(),
        boundsY: bounds.y?.round(),
      );
      if (!ok) {
        androidLyricLog('show failed');
        return false;
      }
      _open = true;
      _lastPushedPos = -1;
      _startPositionTimer();
      unawaited(_container
          .read(settingsControllerProvider.notifier)
          .setDesktopLyricEnabled(true));
      return true;
    } finally {
      _opening = false;
    }
  }

  Future<void> close() async {
    _stopPositionTimer();
    _open = false;
    await AndroidOverlayHost.hide();
    unawaited(_container
        .read(settingsControllerProvider.notifier)
        .setDesktopLyricEnabled(false));
  }

  Future<void> toggle() async {
    if (_open) {
      await close();
    } else {
      await open();
    }
  }

  Future<void> resetPosition() async {
    await AndroidOverlayHost.resetPosition();
  }

  Future<bool> requestPermission() async {
    final can = await AndroidOverlayHost.canDrawOverlays();
    if (can) return true;
    await AndroidOverlayHost.openOverlaySettings();
    return AndroidOverlayHost.canDrawOverlays();
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    // 对时：播放中低频推 position，原生侧本地自走扫光。
    _positionTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!_open) return;
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

  Map<String, Object?> _buildWire({
    bool forceLyrics = false,
    bool positionOnly = false,
  }) {
    final state = _playerState;
    final track = state.current;
    final lyrics = state.lyrics;
    final hash = desktopLyricHash(lyrics);
    final lyricKey =
        '${track?.identityKey ?? ''}|$hash|${state.lyricsStatus.name}';
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
      positionMs:
          positionOnly ? _player.position.value : state.positionMs,
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
      return const {};
    }
    _lastPushedPos = pos;

    final wire = snap.toWire();
    if (positionOnly && !_lyricsDirty && !forceLyrics) {
      wire['lyrics'] = const [];
      wire['lyricsOmitted'] = true;
    } else {
      _lyricsDirty = false;
    }
    return wire;
  }

  Future<void> _pushSnapshot({
    bool forceLyrics = false,
    bool positionOnly = false,
  }) async {
    if (!_open) return;
    final wire = _buildWire(
      forceLyrics: forceLyrics,
      positionOnly: positionOnly,
    );
    if (wire.isEmpty) return;
    await AndroidOverlayHost.updateSnapshot(wire);
  }

  /// 应用退出 / 切后台不需要主动关：进程在悬浮窗就在。
  Future<void> shutdown() async {
    _stopPositionTimer();
    _open = false;
    await AndroidOverlayHost.hide();
  }
}

final androidLyricBridgeProvider = Provider<AndroidLyricBridge>((ref) {
  final b = AndroidLyricBridge.instance;
  if (b == null) {
    throw StateError('AndroidLyricBridge.boot() has not run yet');
  }
  return b;
});
