import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cover artwork cache: memory → disk → network.
///
/// Flutter's [Image.network] only keeps a volatile in-memory [ImageCache];
/// leaving a route (or remounting a tab) often re-downloads covers. This
/// store pins bytes under app support so revisits paint from disk instantly.
class CoverCache {
  CoverCache._();

  static final CoverCache instance = CoverCache._();

  static const Map<String, String> _headers = {
    'Referer': 'http://www.kugou.com/',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  };

  final Map<String, Uint8List> _mem = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  Directory? _dir;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.bytes,
      headers: _headers,
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ),
  );

  String _key(String url) => sha1.convert(utf8.encode(url)).toString();

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}cover_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  /// Synchronous memory hit — used on first paint so Hero landing never
  /// flashes a gradient placeholder after the mini-player already showed art.
  Uint8List? peek(String url) => _mem[url.trim()];

  /// Returns cover bytes for [url], or null when the URL is non-network /
  /// download failed (caller falls back to the seed gradient).
  Future<Uint8List?> get(String url) {
    final key = url.trim();
    if (key.isEmpty ||
        !(key.startsWith('http://') || key.startsWith('https://'))) {
      return Future.value(null);
    }

    final hit = _mem[key];
    if (hit != null) return Future.value(hit);

    final pending = _inflight[key];
    if (pending != null) return pending;

    final task = _load(key);
    _inflight[key] = task;
    return task.whenComplete(() => _inflight.remove(key));
  }

  Future<Uint8List?> _load(String url) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_key(url)}');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _mem[url] = bytes;
          return bytes;
        }
      }

      final resp = await _dio.get<List<int>>(url);
      final data = resp.data;
      if (data == null || data.isEmpty) return null;
      final bytes = Uint8List.fromList(data);
      _mem[url] = bytes;
      unawaited(
        file.writeAsBytes(bytes, flush: true).catchError((Object _) => file),
      );
      return bytes;
    } catch (e) {
      debugPrint('CoverCache load failed: $url ($e)');
      return null;
    }
  }

  /// Drop memory + disk covers (settings → 清理图片缓存).
  Future<void> clear() async {
    _mem.clear();
    _inflight.clear();
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            unawaited(entity.delete().catchError((Object _) => entity));
          }
        }
      }
    } catch (_) {}
  }
}
