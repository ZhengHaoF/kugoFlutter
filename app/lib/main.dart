import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/api/kugou/kugo_client.dart';
import 'core/api/netease/netease_client.dart';
import 'core/api/network_log.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/diagnostics/startup_gate.dart';
import 'core/diagnostics/startup_services.dart';
import 'core/platform.dart';
import 'core/desktop_capabilities.dart';
import 'core/theme/kugo_theme.dart';
import 'data/sources/sources.dart';
import 'data/sources/bili/bili_source.dart';
import 'data/storage/bili_auth_store.dart';
import 'data/storage/credential_store.dart';
import 'data/storage/netease_auth_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/fm/fm_controller.dart';
import 'features/debug/network_log_provider.dart';
import 'features/desktop_lyric/android_overlay/android_overlay_bridge.dart';
import 'features/desktop_lyric/desktop_lyric_ipc.dart';
import 'features/desktop_lyric/lyric_window/lyric_window_app.dart';
import 'features/player/audio_service_handler.dart';
import 'features/player/player_controller.dart';
import 'features/player/linux_media_bridge.dart';
import 'features/settings/settings_controller.dart';
import 'shared/tray/desktop_shell.dart';

void main(List<String> args) {
  runZonedGuarded(() async {
    // Binding and every runApp call must share the same Zone.
    WidgetsFlutterBinding.ensureInitialized();
    await CrashLog.install();
    runApp(
      StartupGate(
        initialize: () => _bootApp(args),
        onError: (error, stack) {
          CrashLog.onPlatformError(error, stack);
        },
      ),
    );
  }, CrashLog.onPlatformError);
}

/// 原 main 内容，仅拆出来以便包进 [runZonedGuarded]。
Future<Widget> _bootApp(List<String> args) async {
  // ── 桌面歌词独立进程分流：只承载歌词 UI，不做音频/托盘/数据源初始化 ──
  // 双进程（不再用 desktop_multi_window）：主窗 spawn 本 exe 并带上
  // `desktop_lyric --ipc-port=N`，两边走 TCP。见 桌面歌词接入方案.md §12。
  await DesktopCapabilities.initialize();
  if (isDesktopPlatform) {
    final lyricArgs = LyricIpc.isLyricProcessArgs(args);
    debugPrint(
      '[desktop_lyric] main args=$args lyric=$lyricArgs '
      'envPort=${Platform.environment[LyricIpc.envPort]}',
    );
    if (lyricArgs) {
      if (!supportsDesktopLyrics) {
        debugPrint('[desktop_lyric] unsupported backend; refusing lyric child');
        exit(64);
      }
      return DesktopLyricApp(ipcPort: LyricIpc.portFromArgs(args));
    }
  }

  registerDefaultMusicSources();
  // 桌面端音频后端是 media_kit（libmpv），必须先初始化。
  // 移动端不加载 libmpv，不能调 —— 见 features/player/audio_engine.dart。
  if (isDesktopPlatform) MediaKit.ensureInitialized();
  // Larger in-memory decode cache; disk cache lives in CoverCache.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20; // 64 MB

  final container = ProviderContainer();
  try {
    final player = container.read(playerControllerProvider.notifier);

    // Load saved settings first so the very first frame already uses the theme
    // the user picked (no dark→light flash on launch).
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    final themeMode = container
        .read(settingsControllerProvider)
        .materialThemeMode;
    final initialBrightness = switch (themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    applyKugoSystemUi(initialBrightness);

    // Pipe Dio interceptor logs into Riverpod network log list.
    void sink(NetworkLog log) {
      container.read(networkLogProvider.notifier).addLog(log);
    }

    NetworkLogHub.bind(sink);
    kugoClient.setLogSink(sink);

    // Restore login session (and device mid) BEFORE any play-url resolve.
    final credentialWarnings = <String>[];
    final auth = container.read(authControllerProvider.notifier);
    await auth.ensureReady().timeout(
      const Duration(seconds: 8),
      onTimeout: auth.abandonPendingRestore,
    );
    if (container.read(authControllerProvider).errorMessage.isNotEmpty) {
      credentialWarnings.add('酷狗登录恢复');
    }

    // 网易云登录态：把上次落盘的 cookie 灌回共享客户端，否则重启即掉登录。
    var neteaseLogged = false;
    try {
      neteaseLogged = await NeteaseAuthStore.restoreInto(
        neteaseClient,
      ).timeout(const Duration(seconds: 8));
    } catch (error, stack) {
      credentialWarnings.add('网易云登录恢复');
      CredentialStore.invalidateRestore('netease.auth.v1');
      CrashLog.onPlatformError(error, stack);
      neteaseClient.clearLogin();
    }
    try {
      await BiliAuthStore.restoreInto(
        biliSource.client,
      ).timeout(const Duration(seconds: 8));
    } catch (error, stack) {
      credentialWarnings.add('B 站登录恢复');
      CredentialStore.invalidateRestore(BiliAuthStore.key);
      CrashLog.onPlatformError(error, stack);
      biliSource.client.clearCookies();
    }

    // 网易云音源需登录才生效：未登录时把它从启用集清掉（旧数据 / 默认全集都可能
    // 带着它）。已登录方向**不动**——保留用户在登录态下对网易云的手动停用；
    // 只有「登录事件」才会重新并入（见 NeteaseLoginController._onConfirmed）。
    if (!neteaseLogged) {
      await container
          .read(settingsControllerProvider.notifier)
          .setNeteaseAccess(false);
    }

    await player.restoreOrSeed();
    return StartupServices(
      initialWarnings: credentialWarnings,
      onError: (error, stack) {
        CrashLog.onPlatformError(error, stack);
      },
      services: {
        '系统媒体会话': () => _startMediaSession(player, initialBrightness),
        'FM 会话': () => container.read(fmControllerProvider.notifier).restore(),
        '桌面托盘与歌词': () async {
          await DesktopShell.boot(container);
        },
        'Android 悬浮歌词': () async {
          await AndroidLyricBridge.boot(container);
        },
      },
      child: UncontrolledProviderScope(
        container: container,
        child: const KugoApp(),
      ),
    );
  } catch (_) {
    NetworkLogHub.bind(null);
    kugoClient.setLogSink(null);
    container.dispose();
    rethrow;
  }
}

Future<void> _startMediaSession(
  PlayerController player,
  Brightness initialBrightness,
) async {
  // The nullable bridge allows playback even if the system session fails.
  if (hasSystemMediaSession) {
    // Audio attributes + audio focus. Without this the app may not be treated as
    // the active media player, and some car head units then show no progress bar.
    // audio_session 无 Windows 实现，只在支持的平台配置。
    if (hasAudioFocusSession) {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    }

    player.attachBridge(
      await AudioService.init<KugoAudioHandler>(
        builder: () => KugoAudioHandler(player),
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.kugo.player',
          androidNotificationChannelName: 'kugo 播放',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // 通知的主色跟着当前调色板走（原来是写死的深色 primary）。
          notificationColor: kugoPaletteFor(initialBrightness).primary,
          // Monochrome white icon: needed for the seek bar to render on some
          // Android builds / head units (see audio_service docs).
          androidNotificationIcon: 'drawable/ic_stat_music',
        ),
      ),
    );
  }
  if (hasLinuxSessionBus) {
    final bridge = await LinuxMediaBridge.start(
      LinuxMediaActions.player(player),
    );
    if (bridge != null) player.attachBridge(bridge);
  }
}
