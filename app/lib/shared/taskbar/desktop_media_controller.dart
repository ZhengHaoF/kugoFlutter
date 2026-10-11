import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cover_cache.dart';
import 'taskbar_bridge.dart';

typedef ArtworkLoader = Future<Uint8List?> Function(String url);
typedef ArtworkDecoder = Future<MediaPixels> Function(Uint8List bytes);
typedef ArtworkSender =
    Future<void> Function(String key, int revision, MediaPixels pixels);

class MediaPixels {
  const MediaPixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

/// Single-flight artwork pipeline. Changing tracks invalidates even a pending
/// fallback decode; failures never leave the previous track's cover visible.
class DesktopMediaArtwork {
  DesktopMediaArtwork({
    required this.load,
    required this.fallback,
    required this.decode,
    required this.send,
  });
  final ArtworkLoader load;
  final Future<Uint8List> Function() fallback;
  final ArtworkDecoder decode;
  final ArtworkSender send;
  int _revision = 0;
  bool _closed = false;
  String? _identity;

  Future<void> update(String key, String url) async {
    final identity = '$key\n$url';
    if (_closed || _identity == identity) return;
    _identity = identity;
    final revision = ++_revision;
    bool current() => !_closed && revision == _revision;
    try {
      // Always publish G first. A failed/slow download must not show old art.
      final defaultPixels = await decode(await fallback());
      if (!current()) return;
      await send(key, revision, defaultPixels);
      if (!current() || url.isEmpty) return;
      final bytes = await load(url);
      if (!current() || bytes == null) return;
      final pixels = await decode(bytes);
      if (current()) await send(key, revision, pixels);
    } catch (_) {
      // Native cleared art on track change; decoding/native failure is safe.
    }
  }

  void dispose() {
    _closed = true;
    _revision++;
  }
}

/// Validate commands against the current player, never the bar's old snapshot.
bool validMediaCommand(
  Map<Object?, Object?> event, {
  required String currentKey,
  required int durationMs,
  required bool canPrevious,
}) {
  final command = event['command'];
  if (command == 'barClosed' || command == 'previewUnavailable') return true;
  if (command == 'barBounds') {
    return event['x'] is int &&
        event['y'] is int &&
        (event['x'] as int).abs() <= 100000 &&
        (event['y'] as int).abs() <= 100000;
  }
  if (command == 'volume') {
    final value = event['value'];
    return value is num && value.isFinite && value >= 0 && value <= 1;
  }
  if (currentKey.isEmpty || event['trackKey'] != currentKey) return false;
  if (command == 'seek') {
    final value = event['value'];
    return durationMs > 0 &&
        value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= durationMs;
  }
  if (command == 'previous') return canPrevious;
  return command == 'playPause' || command == 'next' || command == 'favorite';
}

class DesktopMediaController {
  DesktopMediaController()
    : artwork = DesktopMediaArtwork(
        load: CoverCache.instance.get,
        fallback: () async {
          final data = await rootBundle.load('assets/app_icon.png');
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
        decode: _decode,
        send: (key, revision, pixels) => TaskbarBridge.mediaArtwork(
          trackKey: key,
          revision: revision,
          width: pixels.width,
          height: pixels.height,
          rgba: pixels.rgba,
        ),
      );
  final DesktopMediaArtwork artwork;
  bool _disposed = false;
  int _configuration = 0;

  static Future<MediaPixels> _decode(Uint8List bytes) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Artwork payload too large');
    }
    // Inspect dimensions before decoding, bound both dimensions, release all
    // engine resources even when a codec/image/byte conversion fails.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width < 1 || height < 1 || width > 8192 || height > 8192 ||
          width * height > 16 * 1024 * 1024) {
        throw const FormatException('Invalid artwork size');
      }
      final scale = 256 / (width > height ? width : height);
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round().clamp(1, 256),
        targetHeight: (height * scale).round().clamp(1, 256),
      );
      image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (bytes == null) throw const FormatException('Missing artwork pixels');
      return MediaPixels(
        image.width,
        image.height,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<void> configure(bool preview, bool bar) async {
    final configuration = ++_configuration;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || configuration != _configuration) return;
      await TaskbarBridge.configureMedia(
        preview: preview,
        bar: bar,
        x: prefs.getInt('desktop.mediaBar.x'),
        y: prefs.getInt('desktop.mediaBar.y'),
      );
    } catch (e) {
      debugPrint('[desktop media] configuration unavailable: ${e.runtimeType}');
    }
  }

  Future<void> saveBounds(int x, int y) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('desktop.mediaBar.x', x);
    await prefs.setInt('desktop.mediaBar.y', y);
  }

  void dispose() {
    _disposed = true;
    _configuration++;
    artwork.dispose();
  }
}
