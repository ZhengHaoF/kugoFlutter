// Probe Kugou MV endpoints (KuGouMusicApi video_* / kmr_audio_mv / artist_videos).
// Run: dart run tool/probe_mv.dart
//
// Pipeline:
//   1. search/mv        → sample mvHash / videoId
//   2. search/song      → sample album_audio_id (song → MV)
//   3. kmr/audio/mv     → MV versions for a song
//   4. video/detail     → MV meta + multi-resolution sources
//   5. video/privilege  → quality privilege per hash
//   6. video/url        → playable mp4 URL  ← the hard gate
//   7. artist/videos    → artist MV list
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kugo/core/api/kugou/kugo_client.dart';
import 'package:kugo/core/api/kugou/kugo_sign.dart';

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
  final uuid = '-';

  Map<String, String> baseHeaders({String? router, String? kgTid}) => {
        'User-Agent': KugoSign.userAgent,
        'Content-Type': 'application/json',
        'dfid': dfid,
        'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'mid': mid,
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
        if (router != null) 'x-router': router,
        if (kgTid != null) 'kg-tid': kgTid,
        'Cookie': [
          'dfid=$dfid',
          'KUGOU_API_MID=$mid',
          'KUGOU_API_GUID=$guid',
        ].join(';'),
      };

  Map<String, dynamic> defaultQuery({int? clienttime}) => {
        'dfid': dfid,
        'mid': mid,
        'uuid': uuid,
        'appid': int.parse(KugoSign.appId),
        'clientver': int.parse(KugoSign.clientVer),
        'clienttime': clienttime ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };

  void dump(String name, Response<dynamic> res) {
    final raw = res.data?.toString() ?? '';
    final filtered = raw.contains('URL过滤') || raw.contains('Access Deny');
    print('[$name] http=${res.statusCode} filtered=$filtered len=${raw.length}');
    // Print a readable slice; also expand JSON when possible.
    final decoded = decodeKugoBody(raw);
    if (decoded is Map || decoded is List) {
      const encoder = JsonEncoder.withIndent('  ');
      final pretty = encoder.convert(decoded);
      print(pretty.length > 1800 ? '${pretty.substring(0, 1800)}…' : pretty);
    } else {
      print(raw.length > 600 ? '${raw.substring(0, 600)}…' : raw);
    }
    print('---');
  }

  Future<void> get(
    String name, {
    required String url,
    Map<String, dynamic> query = const {},
    String? router,
    String? kgTid,
  }) async {
    try {
      final res = await dio.get<dynamic>(
        url,
        queryParameters: query,
        options: Options(headers: baseHeaders(router: router, kgTid: kgTid)),
      );
      dump(name, res);
    } catch (e) {
      print('[$name] ERR ${e.toString().split('\n').first}');
      print('---');
    }
  }

  Future<void> post(
    String name, {
    required String url,
    Map<String, dynamic> query = const {},
    Map<String, dynamic>? body,
    String? router,
    String? kgTid,
  }) async {
    try {
      final res = await dio.post<dynamic>(
        url,
        queryParameters: query,
        data: body == null ? null : jsonEncode(body),
        options: Options(headers: baseHeaders(router: router, kgTid: kgTid)),
      );
      dump(name, res);
    } catch (e) {
      print('[$name] ERR ${e.toString().split('\n').first}');
      print('---');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 1. Search MV — public mobilecdn (known reachable)
  // ─────────────────────────────────────────────────────────────
  print('======== 1. search/mv (mobilecdn) ========');
  Response<dynamic> searchRes;
  try {
    searchRes = await dio.get<dynamic>(
      'http://mobilecdn.kugou.com/api/v3/search/mv',
      queryParameters: {
        'format': 'json',
        'keyword': '周杰伦 晴天',
        'page': 1,
        'pagesize': 3,
      },
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Referer': 'http://www.kugou.com/',
        },
      ),
    );
    dump('search-mv', searchRes);
  } catch (e) {
    print('[search-mv] ERR ${e.toString().split('\n').first}');
    print('---');
    searchRes = Response(
      requestOptions: RequestOptions(path: ''),
      data: '{}',
    );
  }

  final searchJson = decodeKugoBody(searchRes.data) as Map? ?? const {};
  final infoList = (searchJson['data'] is Map
          ? (searchJson['data'] as Map)['info']
          : null) ??
      const [];
  String mvHash = '';
  String mvId = '';
  String mvName = '';
  String mvPic = '';
  String mvAlbumAudioId = '';
  if (infoList is List && infoList.isNotEmpty) {
    final first = Map<String, dynamic>.from(infoList.first as Map);
    mvHash = '${first['hash'] ?? ''}';
    mvName = '${first['filename'] ?? ''}';
    mvPic = '${first['imgurl'] ?? ''}';
    print('SAMPLE MV (mobilecdn): hash=$mvHash name=$mvName');
    print('SAMPLE KEYS: ${first.keys.take(24).toList()}');
  } else {
    print('SAMPLE MV: search returned no rows — later steps may fail.');
  }
  print('========');

  // Gateway complexsearch (EchoMusic /search?type=mv path) — richer fields.
  print('======== 1b. search/mv (gateway complexsearch) ========');
  {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final query = defaultQuery(clienttime: clienttime)
      ..addAll({
        'albumhide': 0,
        'iscorrection': 1,
        'keyword': '周杰伦 晴天',
        'nocollect': 0,
        'page': 1,
        'pagesize': 3,
        'platform': 'AndroidFilter',
      });
    query['signature'] = KugoSign.signatureAndroidParams(query);
    try {
      final res = await dio.get<dynamic>(
        'https://gateway.kugou.com/v1/search/mv',
        queryParameters: query,
        options: Options(headers: baseHeaders(router: 'complexsearch.kugou.com')),
      );
      dump('search-mv-gateway', res);
      final json = decodeKugoBody(res.data) as Map? ?? const {};
      final lists = (json['data'] is Map ? (json['data'] as Map)['lists'] : null) ??
          const [];
      if (lists is List && lists.isNotEmpty) {
        final first = Map<String, dynamic>.from(lists.first as Map);
        mvHash = ('${first['MvHash'] ?? first['hash'] ?? ''}').toLowerCase();
        mvId = '${first['MvID'] ?? first['video_id'] ?? ''}';
        mvName = '${first['MvName'] ?? first['FileName'] ?? ''}';
        mvAlbumAudioId =
            '${first['MixSongID'] ?? first['AudioID'] ?? first['album_audio_id'] ?? ''}';
        print(
          'SAMPLE MV (gateway): hash=$mvHash id=$mvId name=$mvName '
          'mixSongId=$mvAlbumAudioId audioId=${first['AudioID']} '
          'mark=${first['MvHashMark']}',
        );
      }
    } catch (e) {
      print('[search-mv-gateway] ERR ${e.toString().split('\n').first}');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Search song — grab album_audio_id for song→MV
  // ─────────────────────────────────────────────────────────────
  print('======== 2. search/song (for album_audio_id) ========');
  String albumAudioId = '';
  String songHash = '';
  try {
    final res = await dio.get<dynamic>(
      'http://mobilecdn.kugou.com/api/v3/search/song',
      queryParameters: {
        'format': 'json',
        'keyword': '周杰伦 晴天',
        'page': 1,
        'pagesize': 1,
      },
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Referer': 'http://www.kugou.com/',
        },
      ),
    );
    final json = decodeKugoBody(res.data) as Map? ?? const {};
    final info = (json['data'] is Map ? (json['data'] as Map)['info'] : null) ??
        const [];
    if (info is List && info.isNotEmpty) {
      final first = Map<String, dynamic>.from(info.first as Map);
      songHash = '${first['hash'] ?? ''}';
      albumAudioId =
          '${first['mixsongid'] ?? first['audio_id'] ?? first['album_audio_id'] ?? ''}';
      print(
        'SAMPLE SONG: hash=$songHash album_audio_id=$albumAudioId '
        'mvhash=${first['mvhash'] ?? first['mv_hash'] ?? ''} '
        'has_mv=${first['has_mv'] ?? first['hasmv'] ?? ''}',
      );
      print('SONG KEYS: ${first.keys.take(28).toList()}');
    }
  } catch (e) {
    print('[search-song] ERR ${e.toString().split('\n').first}');
  }
  print('========');

  // ─────────────────────────────────────────────────────────────
  // 3. kmr/audio/mv — MV versions for a song
  //    KuGouMusicApi kmr_audio_mv.js
  //    POST /kmr/v1/audio/mv  x-router: openapi.kugou.com  KG-TID: 38
  // ─────────────────────────────────────────────────────────────
  final mvCandidateIds = <String>[
    if (mvAlbumAudioId.isNotEmpty) mvAlbumAudioId,
    if (albumAudioId.isNotEmpty) albumAudioId,
  ];
  if (mvCandidateIds.isNotEmpty) {
    print('======== 3. kmr/audio/mv (ids: $mvCandidateIds) ========');
    for (final id in mvCandidateIds) {
      final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = <String, dynamic>{
        'data': [
          {'album_audio_id': id},
        ],
        'fields': 'mkv,tags,h264,h265,authors',
      };
      final bodyJson = jsonEncode(body);
      final query = defaultQuery(clienttime: clienttime);
      query['signature'] =
          KugoSign.signatureAndroidParams(query, data: bodyJson);
      await post(
        'kmr-audio-mv id=$id',
        url: 'https://gateway.kugou.com/kmr/v1/audio/mv',
        query: query,
        body: body,
        router: 'openapi.kugou.com',
        kgTid: '38',
      );
    }
    print('========');
  }

  // ─────────────────────────────────────────────────────────────
  // 4. video/detail — MV meta
  //    KuGouMusicApi video_detail.js
  //    POST /v1/video  x-router: kmr.service.kugou.com
  //    clearDefaultParams: auth fields live in BODY; key = signParamsKey(clienttime)
  // ─────────────────────────────────────────────────────────────
  if (mvId.isNotEmpty) {
    print('======== 4. video/detail ========');
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      'mid': mid,
      'uuid': KugoSign.md5Hex('$dfid$mid'),
      'dfid': dfid,
      'token': '',
      'key': KugoSign.signParamsKey('$clienttime'),
      'show_resolution': 1,
      'data': [
        {'video_id': mvId},
      ],
    };
    final bodyJson = jsonEncode(body);

    // Variant A: empty query + signature over body (clearDefaultParams style).
    {
      final query = <String, dynamic>{};
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
      await post(
        'video-detail-A',
        url: 'https://gateway.kugou.com/v1/video',
        query: query,
        body: body,
        router: 'kmr.service.kugou.com',
      );
    }
    // Variant B: default query + signature over body (no clearDefaultParams).
    {
      final query = defaultQuery(clienttime: clienttime);
      query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
      await post(
        'video-detail-B',
        url: 'https://gateway.kugou.com/v1/video',
        query: query,
        body: body,
        router: 'kmr.service.kugou.com',
      );
    }
    print('========');
  }

  // ─────────────────────────────────────────────────────────────
  // 5. video/privilege — quality privilege
  //    KuGouMusicApi video_privilege.js
  //    POST /v1/get_video_privilege  x-router: media.store.kugou.com
  // ─────────────────────────────────────────────────────────────
  if (mvHash.isNotEmpty) {
    print('======== 5. video/privilege ========');
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final body = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'area_code': 1,
      'behavior': 'play',
      'clientver': int.parse(KugoSign.clientVer),
      'dfid': dfid,
      'mid': mid,
      'resource': [
        {'hash': mvHash, 'id': 0, 'name': ''},
      ],
      'token': '',
      'userid': 0,
      'vip': 0,
    };
    final bodyJson = jsonEncode(body);
    final query = defaultQuery(clienttime: clienttime);
    query['signature'] = KugoSign.signatureAndroidParams(query, data: bodyJson);
    await post(
      'video-privilege',
      url: 'https://gateway.kugou.com/v1/get_video_privilege',
      query: query,
      body: body,
      router: 'media.store.kugou.com',
    );
    print('========');
  }

  // ─────────────────────────────────────────────────────────────
  // 6. video/url — playable URL (THE gate)
  //    KuGouMusicApi video_url.js
  //    GET /v2/interface/index  x-router: trackermv.kugou.com
  //    encryptKey: true → key = signKey(hash, mid)
  // ─────────────────────────────────────────────────────────────
  if (mvHash.isNotEmpty) {
    print('======== 6. video/url ========');
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final query = defaultQuery(clienttime: clienttime)
      ..addAll({
        'backupdomain': 1,
        'cmd': 123,
        'ext': 'mp4',
        'ismp3': 0,
        'hash': mvHash,
        'pid': 1,
        'type': 1,
      });
    query['key'] = KugoSign.signKey(mvHash, mid);
    query['signature'] = KugoSign.signatureAndroidParams(query);
    await get(
      'video-url',
      url: 'https://gateway.kugou.com/v2/interface/index',
      query: query,
      router: 'trackermv.kugou.com',
    );

    // Fallback: same params, no key/signature (some CDNs accept bare).
    final bare = <String, dynamic>{
      'backupdomain': 1,
      'cmd': 123,
      'ext': 'mp4',
      'ismp3': 0,
      'hash': mvHash,
      'pid': 1,
      'type': 1,
    };
    await get(
      'video-url-bare',
      url: 'https://gateway.kugou.com/v2/interface/index',
      query: bare,
      router: 'trackermv.kugou.com',
    );
    print('========');
  }

  // ─────────────────────────────────────────────────────────────
  // 7. artist/videos — artist MV list
  //    KuGouMusicApi artist_videos.js
  //    GET https://openapicdn.kugou.com/kmr/v1/author/videos
  // ─────────────────────────────────────────────────────────────
  print('======== 7. artist/videos ========');
  {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final query = defaultQuery(clienttime: clienttime)
      ..addAll({
        'author_id': '3520', // 周杰伦
        'is_fanmade': '',
        'tag_idx': '',
        'pagesize': 3,
        'page': 1,
      });
    query['signature'] = KugoSign.signatureAndroidParams(query);
    await get(
      'artist-videos',
      url: 'https://openapicdn.kugou.com/kmr/v1/author/videos',
      query: query,
    );
  }

  print('======== probe done ========');
  exit(0);
}
