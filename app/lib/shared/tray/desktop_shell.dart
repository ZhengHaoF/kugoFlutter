import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import 'desktop_tray.dart';

/// Windows / 桌面壳：托盘 + 关闭到托盘。
///
/// 只在 `main()` 调用；测试直接 pump [KugoApp]，不会碰到 window_manager。
class DesktopShell with WindowListener {
  DesktopShell(this._container);

  final ProviderContainer _container;
  DesktopTray? _tray;
  bool _quitting = false;

  PlayerController get _player => _container.read(playerControllerProvider.notifier);

  PlayerState get _playerState => _container.read(playerControllerProvider);

  bool get _closeToTray => _container.read(settingsControllerProvider).closeToTray;

  static Future<DesktopShell?> boot(ProviderContainer container) async {
    if (!isDesktopPlatform) return null;
    final shell = DesktopShell(container);
    await shell._start();
    return shell;
  }

  Future<void> _start() async {
    await windowManager.ensureInitialized();
    // 始终拦截原生关闭：关到托盘或真正退出都由我们决定，
    // 避免 win32 SetQuitOnClose 在 hide 前把进程带走。
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    final tray = DesktopTray(
      onShowWindow: showWindow,
      onTogglePlayback: () => _player.togglePlay(),
      onPrevious: () => _player.previous(),
      onNext: () => _player.next(),
      onSetMode: _player.setMode,
      onVolumeDelta: (delta) {
        final next = (_playerState.volume + delta).clamp(0.0, 1.0);
        _player.setVolume(next);
      },
      onQuit: quit,
    );
    _tray = tray;
    await tray.init();
    _syncTray();

    _container.listen<PlayerState>(playerControllerProvider, (_, _) => _syncTray());
  }

  void _syncTray() {
    final s = _playerState;
    _tray?.syncPlayback(
      TrayPlaybackSnapshot(
        isPlaying: s.isPlaying,
        mode: s.mode,
        volume: s.volume,
        hasTrack: s.current != null,
        canStepBack: s.canStepBack,
      ),
    );
  }

  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    final tray = _tray;
    _tray = null;
    await tray?.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    if (_closeToTray) {
      unawaited(windowManager.hide());
      return;
    }
    unawaited(quit());
  }
}
