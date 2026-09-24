import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/api/kugo_client.dart';
import 'core/api/network_log.dart';
import 'core/platform.dart';
import 'data/sources/kugou/kugou_source.dart';
import 'core/theme/kugo_theme.dart';
import 'data/repositories/discovery_repository.dart';
import 'data/repositories/fm_repository.dart';
import 'data/repositories/play_repository.dart';
import 'data/repositories/playlist_repository.dart';
import 'data/repositories/recommend_repository.dart';
import 'data/repositories/song_detail_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/fm/fm_controller.dart';
import 'features/debug/network_log_provider.dart';
import 'features/player/audio_service_handler.dart';
import 'features/player/player_controller.dart';
import 'features/settings/settings_controller.dart';
import 'shared/tray/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDefaultMusicSources();
  // 桌面端音频后端是 media_kit（libmpv），必须先初始化。
  // 移动端不加载 libmpv，不能调 —— 见 features/player/audio_engine.dart。
  if (isDesktopPlatform) MediaKit.ensureInitialized();
  // Larger in-memory decode cache; disk cache lives in CoverCache.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20; // 64 MB

  final container = ProviderContainer();
  final player = container.read(playerControllerProvider.notifier);

  // Load saved settings first so the very first frame already uses the theme
  // the user picked (no dark→light flash on launch).
  await container.read(settingsControllerProvider.notifier).ensureRestored();
  final themeMode = container.read(settingsControllerProvider).materialThemeMode;
  applyKugoSystemUi(
    switch (themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    },
  );

  // Pipe Dio interceptor logs into Riverpod network log list.
  void sink(NetworkLog log) {
    container.read(networkLogProvider.notifier).addLog(log);
  }

  kugoClient.setLogSink(sink);
  PlayRepository.logSink = sink;
  SongDetailRepository.logSink = sink;
  RecommendRepository.logSink = sink;
  FmRepository.logSink = sink;
  PlaylistRepository.logSink = sink;
  DiscoveryRepository.logSink = sink;

  // Restore login session (and device mid) BEFORE any play-url resolve.
  await container.read(authControllerProvider.notifier).ensureReady();

  // 系统媒体会话：移动端/macOS 走 audio_service 原生实现，Windows 走
  // audio_service_win（SMTC / 媒体键 / 系统媒体卡）。Linux 仍无实现。
  // PlayerController 的 bridge 可空，没挂就没有系统媒体 UI。
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
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.kugo.player',
          androidNotificationChannelName: 'kugo 播放',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          notificationColor: Color(0xFF5B7CFF),
          // Monochrome white icon: needed for the seek bar to render on some
          // Android builds / head units (see audio_service docs).
          androidNotificationIcon: 'drawable/ic_stat_music',
        ),
      ),
    );
  }
  await player.restoreOrSeed();

  // 冷启动认领 FM 会话：播放器队列已恢复，若与 FM 指纹相符就把来源标回 fm，
  // 播放页才会继续显示 FM 控件（循环/随机位换成「不喜欢」、上一首带边界禁用）。
  // 必须晚于 restoreOrSeed()，否则队列还没回来无从比对。
  await container.read(fmControllerProvider.notifier).restore();

  // 桌面壳：托盘 + 关闭到托盘。必须在 settings/player 就绪之后。
  await DesktopShell.boot(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KugoApp(),
    ),
  );
}