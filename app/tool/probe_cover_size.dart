// Probe real cover-art resolution per source (kugou / netease / bili).
//
// Answers the "click cover to view large image" evaluation:
//  1. what pixel size do we actually get from each source's cover URL;
//  2. is a bigger variant cheaply obtainable (netease ?param=wN yN).
//
// Uses the app's own API layer (same URLs the player renders). Anti-hotlink
// headers mirror CoverCache.headersFor (copied verbatim — cover_cache.dart
// imports flutter/foundation, which plain `dart run` cannot compile).
//
// Run: dart run tool/probe_cover_size.dart [--keyword 周杰伦] [--n 6]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:overtone/core/api/bili/bili_client.dart';
import 'package:overtone/core/api/netease/netease_client.dart';
import 'package:overtone/core/api/netease/netease_mappers.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/data/repositories/search_repository.dart';

/// Verbatim copy of `CoverCache.headersFor` (防盗链按 CDN 域名下发)。
Map<String, String> headersFor(String url) {
  final u = url.toLowerCase();
  final isNetease =
      u.contains('126.net') || u.contains('163.com') || u.contains('music.126');
  final isBili = u.contains('hdslb.com') || u.contains('biliimg.com');
  return {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': isNetease
        ? 'https://music.163.com'
        : isBili
            ? 'https://www.bilibili.com'
            : 'http://www.kugou.com/',
  };
}

Future<void> main(List<String> args) async {
  final kw = _arg(args, '--keyword') ?? '周杰伦';
  final n = int.tryParse(_arg(args, '--n') ?? '') ?? 6;

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c >= 200 && c < 400,
    ),
  );

  Future<({int w, int h, int bytes, String fmt})?> fetch(String url) async {
    try {
      final r = await dio.get<List<int>>(
        url,
        options: Options(headers: headersFor(url)),
      );
      final data = r.data;
      if (data == null || data.isEmpty) return null;
      final b = Uint8List.fromList(data);
      final size = probeImageSize(b);
      if (size == null) return null;
      return (w: size.$1, h: size.$2, bytes: b.length, fmt: size.$3);
    } catch (_) {
      return null;
    }
  }

  Future<void> dump(String label, List<Track> tracks) async {
    stdout.writeln('==== $label · keyword=$kw ====');
    if (tracks.isEmpty) {
      stdout.writeln('(no tracks)');
      return;
    }
    for (final t in tracks.take(n)) {
      final url = t.coverUrl.trim();
      if (url.isEmpty) {
        stdout.writeln('  [no coverUrl] ${t.name}');
        continue;
      }
      final m = await fetch(url);
      if (m == null) {
        stdout.writeln('  [fetch fail] $url');
        continue;
      }
      stdout.writeln(
        '  ${m.w}x${m.h} ${m.fmt} ${(m.bytes / 1024).toStringAsFixed(0)}KB  ${t.name}',
      );
      stdout.writeln('    $url');

      // Kugou: the /400/ path segment looks like a size knob — try bigger.
      final kgSize = RegExp(r'(imge\.kugou\.com/stdmusic/)(\d+)(/)').firstMatch(url);
      if (kgSize != null) {
        for (final size in const ['640', '1080']) {
          final big = url.replaceFirst(
            RegExp(r'(imge\.kugou\.com/stdmusic/)\d+(/)'),
            '${kgSize.group(1)}$size${kgSize.group(3)}',
          );
          final m2 = await fetch(big);
          stdout.writeln(
            m2 == null
                ? '    /$size/ -> fail'
                : '    /$size/ -> ${m2.w}x${m2.h} ${(m2.bytes / 1024).toStringAsFixed(0)}KB',
          );
        }
      }

      // Netease: replace (not append — URLs already carry ?param=300y300).
      if (url.contains('126.net') || url.contains('163.com')) {
        for (final param in const ['param=w640y640', 'param=w2000y2000']) {
          final big = await fetch(url.replaceFirst(
            RegExp(r'param=[^&]*'),
            param,
          ));
          stdout.writeln(
            big == null
                ? '    ?$param -> fail'
                : '    ?$param -> ${big.w}x${big.h} ${(big.bytes / 1024).toStringAsFixed(0)}KB',
          );
        }
      }
    }
    stdout.writeln('');
  }

  // 1) Kugou — app's own SearchRepository (pure Dart).
  try {
    final page = await SearchRepository().searchSongsPage(kw, pageSize: n);
    await dump('kugou', page.items);
  } catch (e) {
    stdout.writeln('==== kugou FAILED: ${e.toString().split('\n').first} ====\n');
  }

  // 2) Netease — searchRaw + app's own mapper.
  try {
    final raw = await NeteaseClient().searchRaw(keyword: kw, limit: n);
    await dump('netease', mapNeteaseSearchSongs(raw).items);
  } catch (e) {
    stdout.writeln('==== netease FAILED: ${e.toString().split('\n').first} ====\n');
  }

  // 3) Bili — searchVideos; BiliVideoItem.coverUrl is what the app renders.
  try {
    final page = await BiliClient().searchVideos(kw, page: 1);
    final tracks = page.items
        .map((e) => Track(
              id: e.bvid,
              name: e.title,
              artist: e.author,
              album: '',
              coverUrl: e.coverUrl,
              durationMs: e.durationSec * 1000,
            ))
        .toList();
    await dump('bili', tracks);
  } catch (e) {
    stdout.writeln('==== bili FAILED: ${e.toString().split('\n').first} ====\n');
  }
}

/// (width, height, format) parsed from magic bytes, or null if unrecognized.
/// Pure-Dart header sniffing — no image package in this project.
(int, int, String)? probeImageSize(Uint8List b) {
  if (b.length < 16) return null;
  // PNG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return (_beU32(b, 16), _beU32(b, 20), 'png');
  }
  // JPEG — walk segments for SOF0/SOF1/SOF2.
  if (b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        i += 2;
        continue;
      }
      final len = _beU16(b, i + 2);
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        return (_beU16(b, i + 7), _beU16(b, i + 5), 'jpeg');
      }
      i += 2 + len;
    }
    return null;
  }
  // GIF
  if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return (_leU16(b, 6), _leU16(b, 8), 'gif');
  }
  // WebP (RIFF/WEBP): VP8X extended, VP8 lossy, VP8L lossless.
  if (b.length > 30 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) {
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    if (chunk == 'VP8X') {
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return (w, h, 'webp');
    }
    if (chunk == 'VP8 ') {
      return (_leU16(b, 26) & 0x3FFF, _leU16(b, 28) & 0x3FFF, 'webp');
    }
    if (chunk == 'VP8L') {
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1, 'webp');
    }
  }
  return null;
}

int _beU16(Uint8List b, int i) => (b[i] << 8) | b[i + 1];
int _beU32(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
int _leU16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}
