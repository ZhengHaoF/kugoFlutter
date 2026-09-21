// Probe KuGouMusicApi-aligned rank audio list.
// Run: dart run tool/probe_rank_audio.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kugo/core/api/endpoints.dart';
import 'package:kugo/core/api/kugo_client.dart';
import 'package:kugo/core/api/kugo_sign.dart';
import 'package:kugo/core/api/mappers.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      validateStatus: (c) => c != null && c >= 200 && c < 500,
    ),
  );

  final guid = KugoSign.randomAlnum(32);
  final mid = KugoSign.calculateMid(guid);
  final dfid = '-';
  final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<void> post(
    String name, {
    required String path,
    Map<String, dynamic> body = const {},
  }) async {
    final bodyJson = jsonEncode(body);
    final params = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };
    params['signature'] =
        KugoSign.signatureAndroidParams(params, data: bodyJson);
    final headers = <String, dynamic>{
      'User-Agent': KugoSign.userAgent,
      'Content-Type': 'application/json',
      'dfid': dfid,
      'clienttime': '$clienttime',
      'mid': mid,
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      'kg-tid': '369',
      'Cookie': 'dfid=$dfid;KUGOU_API_MID=$mid;KUGOU_API_GUID=$guid',
    };
    final url = '${KugoEndpoints.gateway}$path';
    stdout.writeln('=== $name ===');
    stdout.writeln('POST $url');
    stdout.writeln('body=$bodyJson');
    try {
      final res = await dio.post<dynamic>(
        url,
        queryParameters: params,
        data: bodyJson,
        options: Options(headers: headers),
      );
      final raw = res.data?.toString() ?? '';
      stdout.writeln('http=${res.statusCode} len=${raw.length}');
      if (looksLikeUrlFilter(raw)) {
        stdout.writeln('URL FILTER');
        return;
      }
      final decoded = decodeKugoBody(res.data);
      if (decoded is! Map) {
        stdout.writeln(raw.substring(0, raw.length.clamp(0, 500)));
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      stdout.writeln(
        'status=${map['status']} err=${map['err_code'] ?? map['error_code']} '
        'msg=${map['msg'] ?? map['message'] ?? map['error']}',
      );
      final data = map['data'];
      stdout.writeln('data.runtime=${data.runtimeType}');
      final songs = extractRankAudioSongs(map);
      final total = extractRankAudioTotal(map);
      stdout.writeln('extract songs=${songs.length} total=$total');
      var mapped = 0;
      var withHash = 0;
      for (final item in songs) {
        if (item is! Map) continue;
        final t = mapMobileSearchSong(Map<String, dynamic>.from(item));
        mapped++;
        if (t.hash.isNotEmpty) withHash++;
        if (mapped == 1) {
          stdout.writeln(
            'first=${t.name} / ${t.artist} hash=${t.hash} '
            'dur=${t.durationMs} album=${t.album} cover=${t.coverUrl}',
          );
        }
      }
      stdout.writeln('mapped=$mapped withHash=$withHash');
      if (data is Map) {
        final dm = Map<String, dynamic>.from(data);
        stdout.writeln('data.keys=${dm.keys.take(30).toList()}');
        for (final k in ['info', 'list', 'song_list', 'songs', 'rank_info']) {
          final v = dm[k];
          if (v is List) {
            stdout.writeln('  $k: List(${v.length})');
            if (v.isNotEmpty && v.first is Map) {
              final first = Map<String, dynamic>.from(v.first as Map);
              stdout.writeln('  $k[0].keys=${first.keys.take(40).toList()}');
              stdout.writeln(
                '  $k[0] name=${first['songname'] ?? first['name']} '
                'hash=${first['hash']} author=${first['author_name'] ?? first['singername']}',
              );
            }
          } else if (v is Map) {
            final fm = Map<String, dynamic>.from(v);
            stdout.writeln('  $k: Map keys=${fm.keys.take(20).toList()}');
          } else if (v != null) {
            stdout.writeln('  $k: $v');
          }
        }
        final total = dm['total'] ?? dm['count'] ?? dm['song_count'];
        if (total != null) stdout.writeln('data.total=$total');
      } else if (data is List) {
        stdout.writeln('data List(${data.length})');
        if (data.isNotEmpty && data.first is Map) {
          final first = Map<String, dynamic>.from(data.first as Map);
          stdout.writeln('data[0].keys=${first.keys.take(40).toList()}');
        }
      }
      stdout.writeln('rawHead=${raw.substring(0, raw.length.clamp(0, 600))}');
    } catch (e) {
      stdout.writeln('ERR ${e.toString().split('\n').first}');
    }
    stdout.writeln('');
  }

  // EchoMusic / KuGouMusicApi rank_audio.js body (rank_id = rankid).
  await post(
    'rank-audio-cid0',
    path: '/openapi/kmr/v2/rank/audio',
    body: {
      'show_portrait_mv': 1,
      'show_type_total': 1,
      'filter_original_remarks': 1,
      'area_code': 1,
      'pagesize': 30,
      'rank_cid': 0,
      'type': 1,
      'page': 1,
      'rank_id': 8888,
    },
  );
  await post(
    'rank-audio-cid128095',
    path: '/openapi/kmr/v2/rank/audio',
    body: {
      'show_portrait_mv': 1,
      'show_type_total': 1,
      'filter_original_remarks': 1,
      'area_code': 1,
      'pagesize': 30,
      'rank_cid': 128095,
      'type': 1,
      'page': 1,
      'rank_id': 8888,
    },
  );
  // Also try without kg-tid / with empty rank_cid via second clienttime.
  final clienttime2 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final params2 = <String, dynamic>{
    'dfid': dfid,
    'mid': mid,
    'uuid': '-',
    'appid': int.parse(KugoSign.appId),
    'clientver': int.parse(KugoSign.clientVer),
    'clienttime': clienttime2,
  };
  final body2 = jsonEncode({
    'show_portrait_mv': 1,
    'show_type_total': 1,
    'filter_original_remarks': 1,
    'area_code': 1,
    'pagesize': 20,
    'rank_cid': 0,
    'type': 1,
    'page': 1,
    'rank_id': 6666,
  });
  params2['signature'] =
      KugoSign.signatureAndroidParams(params2, data: body2);
  stdout.writeln('=== rank-audio-6666 ===');
  try {
    final res = await dio.post<dynamic>(
      '${KugoEndpoints.gateway}/openapi/kmr/v2/rank/audio',
      queryParameters: params2,
      data: body2,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'dfid': dfid,
          'clienttime': '$clienttime2',
          'mid': mid,
          'kg-rc': '1',
          'kg-thash': '5d816a0',
          'kg-rec': '1',
          'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
          'kg-tid': '369',
          'Cookie': 'dfid=$dfid;KUGOU_API_MID=$mid;KUGOU_API_GUID=$guid',
        },
      ),
    );
    final raw = res.data?.toString() ?? '';
    stdout.writeln('http=${res.statusCode} len=${raw.length}');
    stdout.writeln(raw.substring(0, raw.length.clamp(0, 500)));
  } catch (e) {
    stdout.writeln('ERR ${e.toString().split('\n').first}');
  }
}
