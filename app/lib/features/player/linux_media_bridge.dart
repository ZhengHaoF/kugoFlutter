import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/track.dart';
import '../../core/cache/cover_cache.dart';
import 'player_controller.dart';

const mprisRoot = 'org.mpris.MediaPlayer2';
const mprisPlayer = 'org.mpris.MediaPlayer2.Player';

/// Injectable commands keep the D-Bus contract testable without native audio.
class LinuxMediaActions {
  const LinuxMediaActions({
    required this.snapshot,
    required this.positionMs,
    required this.play,
    required this.pause,
    required this.toggle,
    required this.stop,
    required this.next,
    required this.previous,
    required this.seek,
    required this.volume,
    required this.mode,
  });
  final PlayerState Function() snapshot;
  final int Function() positionMs;
  final Future<void> Function() play, pause, toggle, stop, next, previous;
  final void Function(int) seek;
  final void Function(double) volume;
  final void Function(PlayerLoopMode) mode;

  factory LinuxMediaActions.player(PlayerController player) =>
      LinuxMediaActions(
        snapshot: () => player.snapshot,
        positionMs: () => player.position.value,
        play: () async {
          if (!player.snapshot.isPlaying) player.togglePlay();
        },
        pause: () async {
          if (player.snapshot.isPlaying) player.togglePlay();
        },
        toggle: () async => player.togglePlay(),
        stop: player.stopPlayback,
        next: player.next,
        previous: player.previous,
        seek: player.seekTo,
        volume: player.setVolume,
        mode: player.setMode,
      );
}

/// Session-only service. Never launches a private bus or uses the system bus.
class LinuxMediaBridge implements KugoMediaBridge {
  LinuxMediaBridge(this.object, this._client);
  final LinuxMprisObject object;
  final DBusClient _client;
  bool _closed = false;
  static LinuxMediaBridge? instance;

  static Future<LinuxMediaBridge?> start(
    LinuxMediaActions actions, {
    DBusClient? client,
    String? busName,
  }) async {
    var bus = client;
    final object = LinuxMprisObject(actions);
    try {
      bus ??= DBusClient.session();
      await bus.registerObject(object).timeout(const Duration(seconds: 2));
      final reply = await bus
          .requestName(
            busName ?? '$mprisRoot.kugo.instance$pid',
            flags: {DBusRequestNameFlag.doNotQueue},
          )
          .timeout(const Duration(seconds: 2));
      if (reply != DBusRequestNameReply.primaryOwner) {
        throw StateError('MPRIS service name unavailable');
      }
      return instance = LinuxMediaBridge(object, bus);
    } catch (e) {
      await bus?.close();
      debugPrint('[linux] media session unavailable: ${e.runtimeType}');
      return null;
    }
  }

  @override
  void sync({
    required bool playing,
    required AudioProcessingState processing,
    required Duration position,
    Duration bufferedPosition = Duration.zero,
    Track? track,
    String? subtitle,
  }) {
    object.stopped = processing == AudioProcessingState.idle;
    object.publish();
  }

  @override
  void updatePosition(Duration position, {Duration? bufferedPosition}) {
    // Position is read from the live player clock; do not flood the session bus
    // with every audio tick. MPRIS does not signal continuous Position changes.
  }

  @override
  void syncQueue(List<Track> tracks, int currentIndex) => object.publish();

  @override
  void updateMediaSubtitle(String subtitle) {}

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    object.closed = true;
    await _client.close();
    if (identical(instance, this)) instance = null;
  }
}

class LinuxMprisObject extends DBusObject {
  LinuxMprisObject(this.actions, {Future<Uri?> Function(String)? artwork})
    : _artwork = artwork ?? CoverCache.instance.fileUri,
      super(DBusObjectPath('/org/mpris/MediaPlayer2'));
  final LinuxMediaActions actions;
  final Future<Uri?> Function(String) _artwork;
  String _coverKey = '';
  Uri? _cover;
  bool stopped = true;
  bool closed = false;
  Map<String, DBusValue> _published = {};

  String get trackPath {
    final track = actions.snapshot().current;
    return track == null
        ? '/org/mpris/MediaPlayer2/TrackList/NoTrack'
        : '/org/mpris/MediaPlayer2/track/t${sha1.convert(utf8.encode(track.identityKey))}';
  }

  Map<String, DBusValue> get rootProperties => {
    'CanQuit': const DBusBoolean(false),
    'CanRaise': const DBusBoolean(false),
    'HasTrackList': const DBusBoolean(false),
    'Identity': const DBusString('kugo'),
    'DesktopEntry': const DBusString('com.kugo.kugo'),
    'SupportedUriSchemes': DBusArray.string([]),
    'SupportedMimeTypes': DBusArray.string([]),
  };

  Map<String, DBusValue> get playerProperties {
    final s = actions.snapshot();
    final t = s.current;
    final hasTrack = t != null;
    return {
      'PlaybackStatus': DBusString(
        s.isPlaying ? 'Playing' : (stopped || !hasTrack ? 'Stopped' : 'Paused'),
      ),
      'LoopStatus': DBusString(
        s.mode == PlayerLoopMode.single
            ? 'Track'
            : s.mode == PlayerLoopMode.listLoop
            ? 'Playlist'
            : 'None',
      ),
      'Shuffle': DBusBoolean(s.mode == PlayerLoopMode.shuffle),
      'Rate': const DBusDouble(1),
      'MinimumRate': const DBusDouble(1),
      'MaximumRate': const DBusDouble(1),
      'Volume': DBusDouble(s.volume),
      'Position': DBusInt64(actions.positionMs() * 1000),
      'Metadata': DBusDict.stringVariant({
        'mpris:trackid': DBusObjectPath(trackPath),
        if (t != null) ...{
          'xesam:title': DBusString(t.name),
          'xesam:artist': DBusArray.string([t.artist]),
          'xesam:album': DBusString(t.album),
          'mpris:length': DBusInt64(s.durationMs * 1000),
          if (_cover != null) 'mpris:artUrl': DBusString(_cover.toString()),
        },
      }),
      'CanGoNext': DBusBoolean(s.queue.length > 1),
      'CanGoPrevious': DBusBoolean(s.canStepBack),
      'CanPlay': DBusBoolean(hasTrack),
      'CanPause': DBusBoolean(hasTrack),
      'CanSeek': DBusBoolean(hasTrack && s.durationMs > 0),
      'CanControl': const DBusBoolean(true),
    };
  }

  /// Only changed properties are signaled; sensitive stream URLs are not sent.
  void publish() {
    if (closed) return;
    final coverKey = actions.snapshot().current?.coverUrl ?? '';
    if (coverKey != _coverKey) {
      _coverKey = coverKey;
      _cover = null;
      if (coverKey.isNotEmpty) unawaited(_loadArtwork(coverKey));
    }
    final properties = playerProperties..remove('Position');
    final changed = <String, DBusValue>{
      for (final entry in properties.entries)
        if (_published[entry.key] != entry.value) entry.key: entry.value,
    };
    _published = properties;
    if (changed.isNotEmpty && client != null) {
      unawaited(
        emitPropertiesChanged(
          mprisPlayer,
          changedProperties: changed,
        ).catchError((Object e) {
          debugPrint('[linux] media update unavailable: ${e.runtimeType}');
        }),
      );
    }
  }

  Future<void> _loadArtwork(String key) async {
    try {
      final uri = await _artwork(key);
      if (closed || key != _coverKey) return;
      // Only files under our cache are provided by the default resolver.
      _cover = uri?.scheme == 'file' ? uri : null;
      publish();
    } catch (_) {
      // Missing artwork never disables transport controls.
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      mprisRoot,
      methods: [DBusIntrospectMethod('Raise'), DBusIntrospectMethod('Quit')],
      properties: [
        for (final e in rootProperties.entries)
          DBusIntrospectProperty(
            e.key,
            e.value.signature,
            access: DBusPropertyAccess.read,
          ),
      ],
    ),
    DBusIntrospectInterface(
      mprisPlayer,
      methods: [
        for (final m in [
          'Next',
          'Previous',
          'Pause',
          'PlayPause',
          'Stop',
          'Play',
        ])
          DBusIntrospectMethod(m),
        DBusIntrospectMethod(
          'Seek',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Offset',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'SetPosition',
          args: [
            DBusIntrospectArgument(
              DBusSignature('o'),
              DBusArgumentDirection.in_,
              name: 'TrackId',
            ),
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Position',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'OpenUri',
          args: [
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'Uri',
            ),
          ],
        ),
      ],
      signals: [
        DBusIntrospectSignal(
          'Seeked',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.out,
              name: 'Position',
            ),
          ],
        ),
      ],
      properties: [
        for (final e in playerProperties.entries)
          DBusIntrospectProperty(
            e.key,
            e.value.signature,
            access: ['Volume', 'Rate', 'LoopStatus', 'Shuffle'].contains(e.key)
                ? DBusPropertyAccess.readwrite
                : DBusPropertyAccess.read,
          ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      interface == mprisRoot
      ? DBusGetAllPropertiesResponse(rootProperties)
      : interface == mprisPlayer
      ? DBusGetAllPropertiesResponse(playerProperties)
      : DBusMethodErrorResponse.unknownInterface();

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final properties = interface == mprisRoot
        ? rootProperties
        : interface == mprisPlayer
        ? playerProperties
        : null;
    if (properties == null) return DBusMethodErrorResponse.unknownInterface();
    final value = properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface != mprisPlayer) {
      return interface == mprisRoot
          ? DBusMethodErrorResponse.propertyReadOnly()
          : DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'Volume':
        if (value is! DBusDouble || !value.value.isFinite) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        actions.volume(value.value.clamp(0.0, 1.0));
      case 'Rate':
        if (value is! DBusDouble || value.value != 1) {
          return DBusMethodErrorResponse.notSupported(
            'Only rate 1 is supported',
          );
        }
      case 'LoopStatus':
        if (value is! DBusString ||
            !['None', 'Track', 'Playlist'].contains(value.value)) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        actions.mode(switch (value.value) {
          'Track' => PlayerLoopMode.single,
          'Playlist' => PlayerLoopMode.listLoop,
          _ => PlayerLoopMode.order,
        });
      case 'Shuffle':
        if (value is! DBusBoolean) return DBusMethodErrorResponse.invalidArgs();
        actions.mode(
          value.value ? PlayerLoopMode.shuffle : PlayerLoopMode.listLoop,
        );
      default:
        return playerProperties.containsKey(name)
            ? DBusMethodErrorResponse.propertyReadOnly()
            : DBusMethodErrorResponse.unknownProperty();
    }
    publish();
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    final call = methodCall;
    if (call.interface == mprisRoot) {
      return DBusMethodErrorResponse.notSupported();
    }
    if (call.interface != mprisPlayer) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final expected = switch (call.name) {
      'Seek' => 'x',
      'SetPosition' => 'ox',
      'OpenUri' => 's',
      'Next' || 'Previous' || 'Pause' || 'PlayPause' || 'Stop' || 'Play' => '',
      _ => null,
    };
    if (expected == null) return DBusMethodErrorResponse.unknownMethod();
    if (call.signature != DBusSignature(expected)) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    try {
      final s = actions.snapshot();
      switch (call.name) {
        case 'Play':
          if (s.current != null) await actions.play();
        case 'Pause':
          await actions.pause();
        case 'PlayPause':
          if (s.current != null) await actions.toggle();
        case 'Stop':
          await actions.stop();
          stopped = true;
        case 'Next':
          if (s.queue.length > 1) await actions.next();
        case 'Previous':
          if (s.canStepBack) await actions.previous();
        case 'Seek':
          if (s.current != null && s.durationMs > 0) {
            _seek(actions.positionMs() + call.values[0].asInt64() ~/ 1000);
          }
        case 'SetPosition':
          if (call.values[0].asObjectPath().value == trackPath &&
              s.current != null &&
              s.durationMs > 0) {
            final us = call.values[1].asInt64();
            if (us >= 0 && us <= s.durationMs * 1000) _seek(us ~/ 1000);
          }
        case 'OpenUri':
          return DBusMethodErrorResponse.notSupported();
      }
      publish();
      return DBusMethodSuccessResponse();
    } catch (e) {
      return DBusMethodErrorResponse.failed('Playback command failed');
    }
  }

  void _seek(int ms) {
    final target = ms.clamp(0, actions.snapshot().durationMs);
    actions.seek(target);
    if (client != null) {
      unawaited(
        emitSignal(mprisPlayer, 'Seeked', [
          DBusInt64(target * 1000),
        ]).catchError((Object _) {}),
      );
    }
  }
}
