import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/linux_media_bridge.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/shared/tray/linux_tray_host.dart';

Track track(String id) => Track(
  id: id,
  name: '曲目 $id',
  artist: '作者',
  album: '专辑',
  coverUrl: '',
  durationMs: 10000,
);

class Harness {
  PlayerState state = PlayerState(queue: [track('a'), track('b')]);
  int position = 2000;
  final commands = <String>[];
  late final actions = LinuxMediaActions(
    snapshot: () => state,
    positionMs: () => position,
    play: () async {
      commands.add('play');
      state = state.copyWith(display: PlayerDisplayState.playing);
    },
    pause: () async {
      commands.add('pause');
      state = state.copyWith(display: PlayerDisplayState.paused);
    },
    toggle: () async => commands.add('toggle'),
    stop: () async {
      commands.add('stop');
      state = state.copyWith(display: PlayerDisplayState.idle);
    },
    next: () async {
      commands.add('next');
      state = state.copyWith(currentIndex: 1);
    },
    previous: () async {
      commands.add('previous');
      state = state.copyWith(currentIndex: 0);
    },
    seek: (ms) => position = ms,
    volume: (volume) => state = state.copyWith(volume: volume),
    mode: (mode) => state = state.copyWith(mode: mode),
  );
  late final object = LinuxMprisObject(actions);
  Future<DBusMethodResponse> call(
    String name, [
    List<DBusValue> values = const [],
  ]) => object.handleMethodCall(
    DBusMethodCall(
      sender: ':1.1',
      interface: mprisPlayer,
      name: name,
      values: values,
    ),
  );
}

class Watcher extends DBusObject {
  Watcher() : super(DBusObjectPath('/StatusNotifierWatcher'));
  bool hosted = false;
  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async =>
      DBusGetPropertyResponse(DBusBoolean(hosted));
}

void main() {
  test(
    'MPRIS artwork exports cached file URI, not remote signed URL',
    () async {
      final h = Harness();
      h.state = h.state.copyWith(
        queue: [
          track(
            'a',
          ).copyWith(coverUrl: 'https://example.com/art?token=private'),
        ],
      );
      final object = LinuxMprisObject(
        h.actions,
        artwork: (_) async => Uri.file('/tmp/kugo-cover'),
      );
      object.publish();
      await Future<void>.delayed(Duration.zero);
      final metadata = object.playerProperties['Metadata']!
          .asStringVariantDict();
      expect(metadata['mpris:artUrl']!.asString(), 'file:///tmp/kugo-cover');
      expect(metadata.toString(), isNot(contains('token=private')));
    },
  );
  test(
    'MPRIS metadata has a valid stable object-path track ID, no stream URLs',
    () {
      final h = Harness();
      final meta = h.object.playerProperties['Metadata']!.asStringVariantDict();
      expect(meta['mpris:trackid'], isA<DBusObjectPath>());
      expect(meta['xesam:title']!.asString(), '曲目 a');
      expect(meta['mpris:length']!.asInt64(), 10000000);
      expect(meta.containsKey('xesam:url'), isFalse);
      final first = h.object.trackPath;
      expect(h.object.trackPath, first);
      h.state = h.state.copyWith(currentIndex: 1);
      expect(h.object.trackPath, isNot(first));
    },
  );

  for (final command in [
    'Play',
    'Pause',
    'PlayPause',
    'Stop',
    'Next',
    'Previous',
  ]) {
    test('MPRIS $command dispatches the real action', () async {
      final h = Harness();
      expect(await h.call(command), isA<DBusMethodSuccessResponse>());
      expect(h.commands, hasLength(1));
    });
  }

  test(
    'empty queue advertises no transport capability and does not start',
    () async {
      final h = Harness()..state = const PlayerState();
      for (final name in [
        'CanPlay',
        'CanPause',
        'CanGoNext',
        'CanGoPrevious',
        'CanSeek',
      ]) {
        expect(h.object.playerProperties[name]!.asBoolean(), isFalse);
      }
      await h.call('Play');
      await h.call('Next');
      await h.call('Previous');
      expect(h.commands, isEmpty);
    },
  );

  test(
    'Seek uses microseconds and clamps negative / oversized offsets',
    () async {
      final h = Harness();
      await h.call('Seek', [const DBusInt64(3000000)]);
      expect(h.position, 5000);
      await h.call('Seek', [const DBusInt64(-9000000)]);
      expect(h.position, 0);
      await h.call('Seek', [const DBusInt64(999999999)]);
      expect(h.position, 10000);
    },
  );

  test(
    'SetPosition checks current track ID and ignores stale/invalid positions',
    () async {
      final h = Harness();
      await h.call('SetPosition', [
        DBusObjectPath(h.object.trackPath),
        const DBusInt64(4000000),
      ]);
      expect(h.position, 4000);
      await h.call('SetPosition', [
        DBusObjectPath('/stale'),
        const DBusInt64(1000000),
      ]);
      expect(h.position, 4000);
      for (final us in [-1, 10000001]) {
        await h.call('SetPosition', [
          DBusObjectPath(h.object.trackPath),
          DBusInt64(us),
        ]);
        expect(h.position, 4000);
      }
    },
  );

  test(
    'Volume has actual state, rejects nonfinite values and clamps',
    () async {
      final h = Harness();
      await h.object.setProperty(mprisPlayer, 'Volume', const DBusDouble(0.25));
      expect(h.state.volume, 0.25);
      await h.object.setProperty(mprisPlayer, 'Volume', const DBusDouble(2));
      expect(h.state.volume, 1);
      expect(
        await h.object.setProperty(
          mprisPlayer,
          'Volume',
          DBusDouble(double.nan),
        ),
        isA<DBusMethodErrorResponse>(),
      );
    },
  );

  test(
    'unsupported methods, bad signatures and read-only properties report errors',
    () async {
      final h = Harness();
      expect(
        await h.call('OpenUri', [const DBusString('file:///secret')]),
        isA<DBusMethodErrorResponse>(),
      );
      expect(
        await h.call('Seek', [const DBusString('bad')]),
        isA<DBusMethodErrorResponse>(),
      );
      expect(await h.call('NoMethod'), isA<DBusMethodErrorResponse>());
      expect(
        await h.object.setProperty(mprisPlayer, 'Position', const DBusInt64(0)),
        isA<DBusMethodErrorResponse>(),
      );
      expect(
        await h.object.setProperty(mprisPlayer, 'Rate', const DBusDouble(2)),
        isA<DBusMethodErrorResponse>(),
      );
    },
  );

  test('loop and shuffle setters update actual playback modes', () async {
    final h = Harness();
    await h.object.setProperty(
      mprisPlayer,
      'LoopStatus',
      const DBusString('Track'),
    );
    expect(h.state.mode, PlayerLoopMode.single);
    await h.object.setProperty(mprisPlayer, 'Shuffle', const DBusBoolean(true));
    expect(h.state.mode, PlayerLoopMode.shuffle);
    expect(
      await h.object.setProperty(
        mprisPlayer,
        'LoopStatus',
        const DBusString('Bad'),
      ),
      isA<DBusMethodErrorResponse>(),
    );
  });

  test(
    'a real private D-Bus bus transports commands and distinguishes watcher from host',
    () async {
      final directory = await Directory.systemTemp.createTemp('kugo-dbus-test');
      final server = DBusServer();
      final address = await server.listenAddress(
        DBusAddress.unix(dir: directory),
      );
      final bridgeClient = DBusClient(address);
      final remoteClient = DBusClient(address);
      final hostClient = DBusClient(address);
      final monitor = LinuxTrayHostMonitor(client: DBusClient(address));
      LinuxMediaBridge? bridge;
      try {
        final h = Harness();
        bridge = await LinuxMediaBridge.start(
          h.actions,
          client: bridgeClient,
          busName: '$mprisRoot.kugo.test',
        );
        expect(bridge, isNotNull);
        final remote = DBusRemoteObject(
          remoteClient,
          name: '$mprisRoot.kugo.test',
          path: DBusObjectPath('/org/mpris/MediaPlayer2'),
        );
        await remote.callMethod(mprisPlayer, 'Stop', []);
        expect(h.commands, ['stop']);
        await remote.callMethod(mprisPlayer, 'SetPosition', [
          DBusObjectPath(bridge!.object.trackPath),
          const DBusInt64(5000000),
        ]);
        expect(h.position, 5000);
        final properties = await remote.getAllProperties(mprisPlayer);
        expect(properties['Position']!.asInt64(), 5000000);

        expect(await monitor.refresh(), isFalse);
        final watcher = Watcher();
        await hostClient.registerObject(watcher);
        await hostClient.requestName('org.kde.StatusNotifierWatcher');
        expect(await monitor.refresh(), isFalse);
        watcher.hosted = true;
        expect(await monitor.refresh(), isTrue);
        watcher.hosted = false;
        expect(await monitor.refresh(), isFalse);
      } finally {
        await monitor.close();
        await bridge?.close();
        await remoteClient.close();
        await hostClient.close();
        await server.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
