import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overtone/features/settings/settings_controller.dart';
import 'package:overtone/shared/taskbar/desktop_media_controller.dart';
import 'package:overtone/shared/taskbar/taskbar_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('artwork revisions', () {
    late List<String> sent;
    late Map<String, Completer<Uint8List?>> pending;
    late DesktopMediaArtwork artwork;
    setUp(() {
      sent = [];
      pending = {};
      artwork = DesktopMediaArtwork(
        load: (url) => (pending[url] = Completer<Uint8List?>()).future,
        fallback: () async => Uint8List.fromList([0]),
        decode: (bytes) async {
          if (bytes[0] == 255) throw const FormatException('corrupt');
          return MediaPixels(1, 1, bytes);
        },
        send: (key, rev, pixels) async =>
            sent.add('$key:$rev:${pixels.rgba[0]}'),
      );
    });
    tearDown(() => artwork.dispose());

    Future<void> flush() => Future<void>.delayed(Duration.zero);
    test('old download cannot overwrite new track', () async {
      final a = artwork.update('a', 'a');
      await flush();
      final b = artwork.update('b', 'b');
      await flush();
      pending['b']!.complete(Uint8List.fromList([2]));
      await b;
      pending['a']!.complete(Uint8List.fromList([1]));
      await a;
      expect(sent, ['a:1:0', 'b:2:0', 'b:2:2']);
    });
    test('same song with changed URL invalidates earlier artwork', () async {
      final a = artwork.update('a', 'url1');
      await flush();
      final b = artwork.update('a', 'url2');
      await flush();
      pending['url1']!.complete(Uint8List.fromList([1]));
      pending['url2']!.complete(Uint8List.fromList([2]));
      await Future.wait([a, b]);
      expect(sent.last, 'a:2:2');
      expect(sent, isNot(contains('a:1:1')));
    });
    test('failure keeps G fallback', () async {
      final task = artwork.update('a', 'url');
      await flush();
      pending['url']!.complete(null);
      await task;
      expect(sent, ['a:1:0']);
    });
    test('corrupt downloaded image keeps fallback', () async {
      final task = artwork.update('a', 'url');
      await flush();
      pending['url']!.complete(Uint8List.fromList([255]));
      await task;
      expect(sent, ['a:1:0']);
    });
    test('unknown artwork uses fallback without network', () async {
      await artwork.update('a', '');
      expect(pending, isEmpty);
      expect(sent, ['a:1:0']);
    });
    test('no track uses fallback', () async {
      await artwork.update('', '');
      expect(sent, [':1:0']);
    });
    test('progress ticks do not re-download', () async {
      final task = artwork.update('a', 'url');
      await flush();
      await artwork.update('a', 'url');
      expect(pending.length, 1);
      pending['url']!.complete(null);
      await task;
      expect(sent.length, 1);
    });
    test('shutdown prevents in-flight publish', () async {
      final task = artwork.update('a', 'url');
      await flush();
      artwork.dispose();
      pending['url']!.complete(Uint8List.fromList([1]));
      await task;
      expect(sent, ['a:1:0']);
    });
    test('old fallback decode cannot overwrite current track', () async {
      final fallbacks = <Completer<Uint8List>>[];
      final pipeline = DesktopMediaArtwork(
        load: (_) async => null,
        fallback: () {
          final c = Completer<Uint8List>();
          fallbacks.add(c);
          return c.future;
        },
        decode: (b) async => MediaPixels(1, 1, b),
        send: (k, r, p) async => sent.add(k),
      );
      final a = pipeline.update('a', '');
      final b = pipeline.update('b', '');
      fallbacks[1].complete(Uint8List(4));
      await b;
      fallbacks[0].complete(Uint8List(4));
      await a;
      expect(sent, ['b']);
      pipeline.dispose();
    });
  });

  group('command boundary', () {
    bool valid(
      Map<Object?, Object?> event, {
      String key = 'b',
      int duration = 1000,
      bool previous = true,
    }) => validMediaCommand(
      event,
      currentKey: key,
      durationMs: duration,
      canPrevious: previous,
    );
    for (final cmd in ['playPause', 'next', 'previous', 'favorite']) {
      test('$cmd rejects old track', () {
        expect(valid({'command': cmd, 'trackKey': 'a'}), false);
        expect(valid({'command': cmd, 'trackKey': 'b'}), true);
        expect(valid({'command': cmd, 'trackKey': ''}, key: ''), false);
      });
    }
    test('previous honors player capability', () {
      expect(
        valid({'command': 'previous', 'trackKey': 'b'}, previous: false),
        false,
      );
    });
    test('unknown commands rejected', () {
      expect(valid({'command': 'spawn', 'trackKey': 'b'}), false);
    });
    test('seek requires identity, finite value, known duration', () {
      expect(valid({'command': 'seek', 'trackKey': 'b', 'value': 250}), true);
      for (final value in [-1, 1001, double.nan, double.infinity, '50', null]) {
        expect(
          valid({'command': 'seek', 'trackKey': 'b', 'value': value}),
          false,
        );
      }
      expect(valid({'command': 'seek', 'trackKey': 'a', 'value': 50}), false);
      expect(
        valid({'command': 'seek', 'trackKey': 'b', 'value': 0}, duration: 0),
        false,
      );
    });
    test('volume is global but finite and bounded', () {
      expect(valid({'command': 'volume', 'value': .5}, key: ''), true);
      for (final v in [-1, 2, double.nan, double.infinity, '0.5']) {
        expect(valid({'command': 'volume', 'value': v}), false);
      }
    });
    test('bounds require bounded integer coordinates', () {
      expect(valid({'command': 'barBounds', 'x': -1500, 'y': 200}), true);
      expect(valid({'command': 'barBounds', 'x': .5, 'y': 200}), false);
      expect(valid({'command': 'barBounds', 'x': 200001, 'y': 200}), false);
      expect(valid({'command': 'barBounds'}), false);
    });
    test('closing bar does not require a current track', () {
      expect(valid({'command': 'barClosed'}, key: ''), true);
    });
  });

  group('settings and channel', () {
    const channel = MethodChannel('kugo/taskbar');
    final calls = <MethodCall>[];
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test(
      'new features opt-in; settings survive restore and copyWith',
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final ctrl = c.read(settingsControllerProvider.notifier);
        await ctrl.ensureRestored();
        expect(c.read(settingsControllerProvider).taskbarCoverPreview, false);
        expect(c.read(settingsControllerProvider).taskbarMediaBar, false);
        await ctrl.setTaskbarCoverPreview(true);
        await ctrl.setTaskbarMediaBar(true);
        await ctrl.setTaskbarProgress(false);
        final copied = c.read(settingsControllerProvider).copyWith(volume: .3);
        expect(copied.taskbarCoverPreview, true);
        expect(copied.taskbarMediaBar, true);
        final next = ProviderContainer();
        addTearDown(next.dispose);
        await next.read(settingsControllerProvider.notifier).ensureRestored();
        expect(next.read(settingsControllerProvider).taskbarCoverPreview, true);
        expect(next.read(settingsControllerProvider).taskbarMediaBar, true);
      },
    );
    test('configure restores saved bar position', () async {
      final controller = DesktopMediaController();
      await controller.saveBounds(-1200, 800);
      await controller.configure(true, true);
      expect(calls.single.method, 'configureMedia');
      expect(calls.single.arguments, {
        'preview': true,
        'bar': true,
        'x': -1200,
        'y': 800,
      });
      controller.dispose();
    });
    test('configuration after dispose does not revive bar', () async {
      final controller = DesktopMediaController();
      controller.dispose();
      await controller.configure(true, true);
      expect(calls, isEmpty);
    });
    test('newer configuration wins over pending preferences', () async {
      final controller = DesktopMediaController();
      final on = controller.configure(true, true);
      final off = controller.configure(false, false);
      await Future.wait([on, off]);
      expect(calls.length, 1);
      expect(calls.single.arguments, {'preview': false, 'bar': false});
      controller.dispose();
    });
    test('artwork payload carries raw pixels and revision', () async {
      await TaskbarBridge.mediaArtwork(
        trackKey: 'kugou:1',
        revision: 2,
        width: 1,
        height: 1,
        rgba: Uint8List.fromList([1, 2, 3, 255]),
      );
      expect(calls.single.method, 'mediaArtwork');
      expect((calls.single.arguments as Map)['revision'], 2);
      expect((calls.single.arguments as Map)['rgba'], [1, 2, 3, 255]);
    });
    test('new Dart session reset precedes artwork on the shared channel', () async {
      await TaskbarBridge.beginMediaSession();
      await TaskbarBridge.mediaArtwork(
        trackKey: 'kugou:1', revision: 1, width: 1, height: 1,
        rgba: Uint8List.fromList([1, 2, 3, 255]),
      );
      expect(calls.map((c) => c.method), ['beginMediaSession', 'mediaArtwork']);
    });
    test('actual G asset decodes into bounded straight RGBA for native host',
        () async {
      final controller = DesktopMediaController();
      await controller.artwork.update('kugou:1', '');
      expect(calls.length, 1);
      expect(calls.single.method, 'mediaArtwork');
      final payload = calls.single.arguments as Map;
      expect(payload['trackKey'], 'kugou:1');
      expect(payload['width'], 256);
      expect(payload['height'], 256);
      expect((payload['rgba'] as Uint8List).length, 256 * 256 * 4);
      controller.dispose();
    });
  });
}
