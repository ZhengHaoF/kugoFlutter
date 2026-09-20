// Probe style-recommend / special-recommend / top-ip against live gateway.
// Run: dart run tool/probe_style_recommend.dart
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
    required String url,
    String? router,
    Map<String, dynamic> extraQuery = const {},
    Map<String, dynamic>? body,
  }) async {
    final bodyJson = body == null ? '' : jsonEncode(body);
    final params = <String, dynamic>{
      'dfid': dfid,
      'mid': mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      ...extraQuery,
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
      if (router != null) 'x-router': router,
      'Cookie': 'dfid=$dfid;KUGOU_API_MID=$mid;KUGOU_API_GUID=$guid',
    };
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
      stdout.writeln('status=${res.statusCode} len=${raw.length}');
      if (looksLikeUrlFilter(raw)) {
        stdout.writeln('URL FILTER / 拦截');
      } else {
        final decoded = decodeKugoBody(res.data);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          stdout.writeln(
            'api status=${map['status']} err=${map['err_code'] ?? map['error_code']} '
            'msg=${map['msg'] ?? map['message']}',
          );
          final songs = extractEverydayList(map);
          final groups = extractStyleTagGroups(map);
          stdout.writeln('songs=${songs.length} tagGroups=${groups.length}');
          if (songs.isNotEmpty) {
            final t = mapEverydaySong(Map<String, dynamic>.from(songs.first as Map));
            stdout.writeln('firstSong=${t.name} / ${t.artist} hash=${t.hash}');
          }
          if (groups.isNotEmpty) {
            stdout.writeln(
              'firstGroup=${groups.first.name} tags=${groups.first.child.map((e) => e.name).take(5).toList()}',
            );
          }
          stdout.writeln('rawHead=${raw.substring(0, raw.length.clamp(0, 400))}');
        } else {
          stdout.writeln(raw.substring(0, raw.length.clamp(0, 400)));
        }
      }
    } catch (e) {
      stdout.writeln('ERR ${e.toString().split('\n').first}');
    }
    stdout.writeln('');
  }

  await post(
    'style-prefixed',
    url:
        '${KugoEndpoints.gateway}${KugoEndpoints.everydayStyleRecommendPrefixed}',
    extraQuery: {'tagids': ''},
    body: const <String, dynamic>{},
  );

  await post(
    'style-xrouter',
    url: '${KugoEndpoints.gateway}${KugoEndpoints.everydayStyleRecommendPrefixed}',
    router: KugoEndpoints.everydayRouter,
    extraQuery: {'tagids': ''},
    body: const <String, dynamic>{},
  );

  await post(
    'daily-parity',
    url: '${KugoEndpoints.gateway}${KugoEndpoints.everydayRecommend}',
    router: KugoEndpoints.everydayRouter,
    extraQuery: {'platform': 'ios'},
    body: null,
  );

  await post(
    'special-recommend',
    url: '${KugoEndpoints.gateway}${KugoEndpoints.specialRecommend}',
    router: KugoEndpoints.specialRecommendRouter,
    body: {
      'appid': int.parse(KugoSign.appId),
      'mid': mid,
      'clientver': int.parse(KugoSign.clientVer),
      'platform': 'android',
      'clienttime': clienttime,
      'userid': 0,
      'module_id': 1,
      'page': 1,
      'pagesize': 6,
      'key': KugoSign.signParamsKey('$clienttime'),
      'special_recommend': {
        'withtag': 1,
        'withsong': 0,
        'sort': 1,
        'ugc': 1,
        'is_selected': 0,
        'withrecommend': 1,
        'area_code': 1,
        'categoryid': 0,
      },
      'req_multi': 1,
      'retrun_min': 5,
      'return_special_falg': 1,
    },
  );

  await post(
    'top-ip',
    url: '${KugoEndpoints.musicAdService}${KugoEndpoints.topIp}',
    extraQuery: {'clientver': 12349, 'area_code': 1},
    body: {'tags': <String, dynamic>{}},
  );
}
