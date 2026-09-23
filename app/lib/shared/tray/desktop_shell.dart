import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_navigator.dart';
import '../../core/platform.dart';
import '../../features/likes/likes_controller.dart';
import '../../features/player/player_controller.dart';
import '../../features/settings/settings_controller.dart';
import '../taskbar/taskbar_bridge.dart';
import 'close_behavior_dialog.dart';
import 'desktop_tray.dart';

/// Windows / 桌面壳：托盘 + 关闭到托盘 + 任务栏 Thumbar/进度条。
///
/// 只在 `main()` 调用；测试直接 pump [KugoApp]，不会碰到 window_manager。
class DesktopShell with WindowListener {
  DesktopShell(this._container);

  /// Echo taskbarProgress THROTTLE_MS / RATIO_EPSILON.
  static const _progressThrottle = Duration(milliseconds: 200);

  final ProviderContainer _container;
  DesktopTray? _tray;
  bool _quitting = false;

  /// Guards the「每次询问」prompt against a second close (taskbar / Alt+F4)
  /// arriving while it is already on screen.
  bool _closePromptOpen = false;
  Timer? _progressTimer;
  VoidCallback? _positionListener;
  int _lastProgressPermille = -1;
  String _lastProgressMode = 'none';

  PlayerController get _player => _container.read(playerControllerProvider.notifier);

  PlayerState get _playerState => _container.read(playerControllerProvider);

  CloseBehavior get _closeBehavior =>
      _container.read(settingsControllerProvider).closeBehavior;

  bool get _taskbarProgressEnabled =>
      _container.read(settingsControllerProvider).taskbarProgress;

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
    _wireTaskbar();

    _container.listen<PlayerState>(playerControllerProvider, (_, _) {
      _syncTray();
      _syncTaskbarFromState();
    });
    _container.listen<List>(likesProvider, (_, _) => _syncTaskbarFromState());
    _container.listen<AppSettings>(settingsControllerProvider, (prev, next) {
      if (prev?.taskbarProgress != next.taskbarProgress) {
        // Toggle off must clear immediately; on re-applies current ratio.
        _lastProgressMode = 'none';
        _lastProgressPermille = -1;
        _pushProgress(force: true);
      }
    });
  }

  void _wireTaskbar() {
    if (!isWindowsPlatform) return;
    TaskbarBridge.ensureListening();
    TaskbarBridge.onThumbarCommand = _onThumbarCommand;
    final position = _player.position;
    void onPosition() => _scheduleProgressSync();
    position.addListener(onPosition);
    _positionListener = onPosition;
    _syncTaskbarFromState();
    _scheduleProgressSync();
  }

  void _onThumbarCommand(String command) {
    switch (command) {
      case 'previous':
        _player.previous();
      case 'playPause':
        _player.togglePlay();
      case 'next':
        _player.next();
      case 'favorite':
        final track = _playerState.current;
        if (track != null) {
          unawaited(_container.read(likesProvider.notifier).toggle(track));
        }
    }
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

  void _syncTaskbarFromState() {
    final s = _playerState;
    final track = s.current;
    final hasTrack = track != null;
    final isFavorite =
        track != null && _container.read(likesProvider).any((t) => t.id == track.id);
    unawaited(
      TaskbarBridge.updateButtons(
        hasTrack: hasTrack,
        isPlaying: s.isPlaying,
        isFavorite: isFavorite,
        canStepBack: s.canStepBack,
      ),
    );
    // Mode is discrete — push immediately so pause turns yellow at once.
    _pushProgress(force: true);
  }

  void _scheduleProgressSync() {
    if (_progressTimer?.isActive ?? false) return;
    _progressTimer = Timer(_progressThrottle, () => _pushProgress(force: false));
  }

  void _pushProgress({required bool force}) {
    final s = _playerState;
    final hasTrack = s.current != null;
    // Setting off is equivalent to Echo's enabled=false → always clear.
    final enabled = _taskbarProgressEnabled;
    final mode = !enabled
        ? TaskbarProgressMode.none
        : taskbarModeFor(
            hasTrack: hasTrack,
            isPlaying: s.isPlaying,
            durationMs: s.durationMs,
          );
    final durationMs = s.durationMs;
    final positionMs = _player.position.value.clamp(0, durationMs <= 0 ? 0 : durationMs);
    var permille = 0;
    if (durationMs > 0) {
      permille = (positionMs * 1000) ~/ durationMs;
    }
    final modeName = mode.wireName;
    final modeChanged = modeName != _lastProgressMode;
    final ratioChanged =
        _lastProgressPermille < 0 || (permille - _lastProgressPermille).abs() >= 1;
    if (!force && !modeChanged && !ratioChanged) return;
    // Already cleared and still none — skip the channel round-trip.
    if (!force && modeName == 'none' && _lastProgressMode == 'none') return;

    _lastProgressMode = modeName;
    _lastProgressPermille = modeName == 'none' ? -1 : permille;
    unawaited(
      TaskbarBridge.updateProgress(
        mode: modeName,
        positionMs: positionMs,
        durationMs: durationMs,
      ),
    );
  }

  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
    // 任务栏按钮重建后 thumbar 会丢，显示时重放一次。
    if (isWindowsPlatform) {
      unawaited(TaskbarBridge.refresh());
    }
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    _progressTimer?.cancel();
    _progressTimer = null;
    final listener = _positionListener;
    if (listener != null) {
      _player.position.removeListener(listener);
      _positionListener = null;
    }
    TaskbarBridge.onThumbarCommand = null;
    final tray = _tray;
    _tray = null;
    await tray?.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    if (isWindowsPlatform) {
      // window_manager 的 destroy() 在 Windows 上只 PostQuitMessage(0)：消息循环
      // 先退出、窗口没被销毁，引擎 shutdown 跑在正常窗口生命周期之外，表现就是
      // 进程卡住不退出（leanflutter/window_manager#502 / #478 / #590）。
      // 改走标准关闭路径：SC_CLOSE → WM_CLOSE → DestroyWindow → WM_DESTROY →
      // FlutterWindow::OnDestroy（引擎收尾）→ main.cpp 里 quit_on_close 的
      // PostQuitMessage。此处的 close 不会再触发 onWindowClose 分支：监听已摘、
      // preventClose 已关。
      await windowManager.close();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  void onWindowClose() {
    if (_quitting || _closePromptOpen) return;
    switch (_closeBehavior) {
      case CloseBehavior.tray:
        unawaited(windowManager.hide());
      case CloseBehavior.quit:
        unawaited(quit());
      case CloseBehavior.ask:
        unawaited(_promptClose());
    }
  }

  ///「每次询问」branch: show the prompt, then act on the answer (and persist it
  /// when「记住我的选择」was ticked).
  Future<void> _promptClose() async {
    final context = kugoNavigatorKey.currentContext;
    if (context == null) {
      // First frame has not been mounted yet (close during startup). The tray
      // already exists, so hide instead of risking a half-built navigator.
      await windowManager.hide();
      return;
    }
    _closePromptOpen = true;
    try {
      final choice = await showCloseBehaviorDialog(context);
      if (choice == null) return; // 取消 / 点遮罩 → 保持窗口打开
      if (choice.remember) {
        await _container
            .read(settingsControllerProvider.notifier)
            .setCloseBehavior(choice.behavior);
      }
      if (choice.behavior == CloseBehavior.tray) {
        await windowManager.hide();
      } else {
        await quit();
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  @override
  void onWindowRestore() {
    if (isWindowsPlatform) {
      unawaited(TaskbarBridge.refresh());
    }
  }
}
