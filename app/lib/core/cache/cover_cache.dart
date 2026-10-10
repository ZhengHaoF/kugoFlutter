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

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 防盗链按 CDN 域名下发：网易系画布要 music.163.com，酷狗系要 kugou，
  /// B 站系（`hdslb.com` / `biliimg.com`）要 www.bilibili.com（方案 §3.4：
  /// 不带 Referer 会 403；与取流直链同一套口径）。
  static Map<String, String> headersFor(String url) {
    final u = url.toLowerCase();
    final isNetease = u.contains('126.net') ||
        u.contains('163.com') ||
        u.contains('music.126') ||
        u.contains('p1.music.126');
    final isBili = u.contains('hdslb.com') || u.contains('biliimg.com');
    return {
      'User-Agent': _ua,
      'Referer': isNetease
          ? 'https://music.163.com'
          : isBili
              ? 'https://www.bilibili.com'
              : 'http://www.kugou.com/',
    };
  }

  /// Upper bound on retained cover byte payloads.
  ///
  /// Covers are commonly 0.3–1.5 MB each, so an unbounded map grows into the
  /// hundreds of MB over a long session and shows up as GC stutter while
  /// scrolling. Bounded to roughly 30 MB of raw bytes; anything evicted here
  /// is still on disk, so the next paint just re-reads a local file.
  static const int _maxMemBytes = 30 << 20;

  /// Insertion-ordered (Dart's LinkedHashMap keeps first-insert order), so the
  /// first key is the coldest and gets evicted first.
  final Map<String, Uint8List> _mem = {};
  int _memBytes = 0;
  final Map<String, Future<Uint8List?>> _inflight = {};
  Directory? _dir;

  void _remember(String url, Uint8List bytes) {
    final previous = _mem.remove(url);
    if (previous != null) _memBytes -= previous.length;
    _mem[url] = bytes;
    _memBytes += bytes.length;
    while (_memBytes > _maxMemBytes && _mem.length > 1) {
      final oldest = _mem.keys.first;
      final dropped = _mem.remove(oldest);
      if (dropped != null) _memBytes -= dropped.length;
    }
  }

  late Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.bytes,
      headers: headersFor(''),
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ),
  );

  /// 测试注入下载用的 Dio，避免用例真去打 CDN。
  @visibleForTesting
  set dioForTesting(Dio dio) => _dio = dio;

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

  /// Export only a local cover file to desktop media clients. Remote artwork
  /// may require Referer headers, and signed URLs must not go onto D-Bus.
  Future<Uri?> fileUri(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;
    final bytes = await get(key);
    if (bytes == null) return null;
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_key(key)}');
      await file.writeAsBytes(bytes, flush: true);
      return file.uri;
    } catch (_) {
      return null;
    }
  }

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
          _remember(url, bytes);
          return bytes;
        }
      }

      final resp = await _dio.get<List<int>>(
        url,
        options: Options(headers: headersFor(url)),
      );
      final data = resp.data;
      if (data == null || data.isEmpty) return null;
      final bytes = Uint8List.fromList(data);
      _remember(url, bytes);
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
    _memBytes = 0;
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
