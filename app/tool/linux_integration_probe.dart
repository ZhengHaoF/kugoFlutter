// Native Linux probe. Build with:
// flutter build linux --release -t tool/linux_integration_probe.dart
// Run in an isolated desktop session using tool/run_linux_probe.sh.
// Offline fixtures are injected explicitly; this is not real-account evidence.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kugo/core/desktop_capabilities.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/data/storage/kugo_db.dart';
import 'package:kugo/shared/tray/window_bounds_store.dart';
import 'package:kugo/features/mv/mv_desktop_mini.dart';
import 'package:kugo/features/player/linux_media_bridge.dart';
import 'package:kugo/features/player/media_kit_player.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:media_kit/media_kit.dart' show MediaKit, Player, Media;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../test/fakes/fake_music_source.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await DesktopCapabilities.initialize();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1000, 700),
      title: 'kugo Linux integration probe',
    ),
    () async => windowManager.show(),
  );
  runApp(const MaterialApp(home: Probe()));
}

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  VideoController? video;
  final notes = <String>[];
  void say(String note) {
    // ignore: avoid_print
    print('[linux-probe] $note');
    if (mounted) setState(() => notes.add(note));
  }

  void check(bool condition, String note) {
    if (!condition) throw StateError(note);
    say('PASS $note');
  }

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 90), () => exit(2));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
  }

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline))
        throw TimeoutException('probe state');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> run() async {
    HttpServer? server;
    ProviderContainer? container;
    DBusClient? remoteClient;
    LinuxMediaBridge? bridge;
    Player? videoPlayer;
    var code = 0;
    try {
      say('backend=${DesktopCapabilities.current.backend}');
      final wave = tone();
      var accepted = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.headers.value('Referer') != 'https://www.bilibili.com' ||
            request.headers.value('User-Agent') != 'kugo-linux-probe') {
          request.response.statusCode = 403;
          await request.response.close();
          return;
        }
        accepted++;
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.headers.set('Accept-Ranges', 'bytes');
        final range = request.headers.value('Range');
        final match = range == null
            ? null
            : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        var start = 0;
        var end = wave.length - 1;
        if (match != null) {
          start = int.parse(match[1]!);
          if (match[2]!.isNotEmpty) end = int.parse(match[2]!).clamp(0, end);
          if (start > end) {
            request.response.statusCode = 416;
            await request.response.close();
            return;
          }
          request.response.statusCode = 206;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/${wave.length}',
          );
        }
        request.response.contentLength = end - start + 1;
        request.response.add(wave.sublist(start, end + 1));
        await request.response.close();
      });
      final fixture = FakeMusicSource()
        ..nextPlayUrl = PlayUrlResult(
          url: 'http://127.0.0.1:${server.port}/tone.wav',
          headers: {
            'Referer': 'https://www.bilibili.com',
            'User-Agent': 'kugo-linux-probe',
          },
        );
      final rawPlayer = Player();
      final engine = MediaKitPlayerImpl(player: rawPlayer);
      var engineCursor = 0;
      engine.positionStream.listen((position) {
        engineCursor = position.inMilliseconds;
      });
      container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine, source: fixture),
          ),
        ],
      );
      final controller = container.read(playerControllerProvider.notifier);
      final queue = [
        for (final id in ['fixture-a', 'fixture-b'])
          Track(
            id: id,
            name: '离线测试 $id',
            artist: 'Linux probe',
            album: 'Offline fixture',
            coverUrl: '',
            durationMs: 20000,
            hash: id,
          ),
      ];
      await DesktopWindowBoundsStore.save(
        const DesktopWindowBounds(width: 1111, height: 777),
      );
      check(
        (await DesktopWindowBoundsStore.load()).width == 1111,
        'native SharedPreferences window settings persist',
      );
      final database = KugoDb();
      await database.writeQueue(queue, 1, 'listLoop');
      await database.appendHistory(queue.first);
      await database.close();
      final reopened = KugoDb();
      try {
        final restored = await reopened.readQueue();
        check(
          restored?.queue.length == 2 && restored?.index == 1,
          'native SQLite queue survives database reopen',
        );
        check(
          (await reopened.readHistory()).isNotEmpty,
          'native SQLite history persists',
        );
      } finally {
        await reopened.close();
      }
      bridge = await LinuxMediaBridge.start(
        LinuxMediaActions.player(controller),
      );
      check(bridge != null, 'MPRIS registered on real session bus');
      controller.attachBridge(bridge!);
      container.listen<PlayerState>(playerControllerProvider, (_, _) {
        bridge?.object.publish();
      });
      await controller.playQueue(queue);
      say(
        'audio state=${controller.snapshot.display} '
        'playing=${controller.snapshot.isPlaying} requests=$accepted '
        'engineError=${engine.lastError}',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      say(
        'cursor controller=${controller.position.value} '
        'libmpv=${rawPlayer.state.position.inMilliseconds}',
      );
      await until(() => rawPlayer.state.position.inMilliseconds > 1000);
      say('live cursor=${controller.position.value} engine=$engineCursor');
      check(
        controller.position.value > 0,
        'application playback cursor advances',
      );
      check(
        accepted > 0,
        'libmpv HTTP headers, decoding and progressing clock',
      );
      remoteClient = DBusClient.session();
      final remote = DBusRemoteObject(
        remoteClient,
        name: '$mprisRoot.kugo.instance$pid',
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
      );
      await remote.callMethod(mprisPlayer, 'Pause', []);
      await until(() => !controller.snapshot.isPlaying);
      check(true, 'MPRIS Pause');
      await remote.callMethod(mprisPlayer, 'Play', []);
      await until(() => controller.snapshot.isPlaying);
      check(true, 'MPRIS Play');
      await remote.callMethod(mprisPlayer, 'SetPosition', [
        DBusObjectPath(bridge.object.trackPath),
        const DBusInt64(5000000),
      ]);
      await until(() => controller.position.value >= 4900);
      check(true, 'MPRIS SetPosition microseconds');
      await remote.callMethod(mprisPlayer, 'Next', []);
      await until(() => controller.snapshot.currentIndex == 1);
      check(true, 'MPRIS Next');
      await remote.callMethod(mprisPlayer, 'Previous', []);
      await until(() => controller.snapshot.currentIndex == 0);
      check(true, 'MPRIS Previous');
      await remote.setProperty(mprisPlayer, 'Volume', const DBusDouble(0.5));
      check(
        controller.snapshot.volume == 0.5,
        'MPRIS volume updates actual player',
      );
      await remote.callMethod(mprisPlayer, 'Stop', []);
      await until(() => !controller.snapshot.isPlaying);
      check(
        controller.snapshot.display == PlayerDisplayState.idle,
        'MPRIS Stop',
      );
      final saved = await MvDesktopMini.enter(16 / 9);
      check(saved != null, 'desktop mini-window entry');
      await MvDesktopMini.exit(saved);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      check(
        (await windowManager.getBounds()).width > 800,
        'desktop mini-window restores normal size',
      );

      final path = Platform.environment['KUGO_PROBE_VIDEO'];
      if (path == null) throw StateError('KUGO_PROBE_VIDEO fixture required');
      videoPlayer = Player();
      video = VideoController(
        videoPlayer,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
        ),
      );
      setState(() {});
      await videoPlayer.open(Media(Uri.file(path).toString()));
      await video!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 10),
      );
      await until(() => (video!.rect.value?.width ?? 0) >= 320);
      await Future<void>.delayed(const Duration(seconds: 1));
      await videoPlayer.pause();
      check(
        video!.rect.value!.width >= 320,
        'native video texture decoded frame',
      );
      say('SCREENSHOT_READY');
      await Future<void>.delayed(const Duration(seconds: 3));
      say('ALL_CHECKS_PASSED');
    } catch (e, st) {
      say('FAIL $e');
      // ignore: avoid_print
      print(st);
      code = 1;
    } finally {
      await videoPlayer?.dispose();
      await remoteClient?.close();
      await bridge?.close();
      container?.dispose();
      await server?.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(code);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Linux P0/P1 integration probe')),
    body: Column(
      children: [
        Expanded(
          child: ListView(children: [for (final note in notes) Text(note)]),
        ),
        if (video != null)
          SizedBox(height: 250, child: Video(controller: video!)),
      ],
    ),
  );
}

Uint8List tone() {
  const rate = 48000;
  const samples = rate * 20;
  final buffer = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      buffer.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  buffer.setUint32(4, buffer.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, 1, Endian.little);
  buffer.setUint32(24, rate, Endian.little);
  buffer.setUint32(28, rate * 2, Endian.little);
  buffer.setUint16(32, 2, Endian.little);
  buffer.setUint16(34, 16, Endian.little);
  text(36, 'data');
  buffer.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    buffer.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * 440 * i / rate) * 8000).round(),
      Endian.little,
    );
  }
  return buffer.buffer.asUint8List();
}
