import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api/kugo_client.dart';
import 'core/api/network_log.dart';
import 'data/repositories/play_repository.dart';
import 'data/repositories/song_detail_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/debug/network_log_provider.dart';
import 'features/player/audio_service_handler.dart';
import 'features/player/player_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0E14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final container = ProviderContainer();
  final player = container.read(playerControllerProvider.notifier);

  // Pipe Dio interceptor logs into Riverpod network log list.
  void sink(NetworkLog log) {
    container.read(networkLogProvider.notifier).addLog(log);
  }

  kugoClient.setLogSink(sink);
  PlayRepository.logSink = sink;
  SongDetailRepository.logSink = sink;

  // Restore login session (and device mid) BEFORE any play-url resolve.
  await container.read(authControllerProvider.notifier).ensureReady();

  final handler = await AudioService.init(
    builder: () => KugoAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.kugo.player',
      androidNotificationChannelName: 'kugo 播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: Color(0xFF5B7CFF),
    ),
  );
  player.attachBridge(handler);
  await player.restoreOrSeed();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KugoApp(),
    ),
  );
}