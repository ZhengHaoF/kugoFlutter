/// 酷狗音乐云盘仓库：列表 / 播放地址 / 删除。
///
/// 协议对齐 KuGouMusicApi `user_cloud.js` / `user_cloud_url.js` / `user_cloud_del.js`，
/// 上游对照见 `docs/api-notes.md`「音乐云盘」节与 `tool/probe_cloud_disk.dart`。
///
/// 协议要点：
/// - 列表/删除走 `mcloudservice`，**AES body + RSA `p`** 信封，无 android signature；
/// - 播放地址走 gateway，android signature + `signCloudKey`；
/// - 删除**必须有 kv_id**，当前上游不支持仅 hash 删除。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/kugou/kugo_client.dart';
import '../../core/api/kugou/kugo_crypto.dart';
import '../../core/api/kugou/kugo_sign.dart';
import '../../core/api/mappers.dart' show mapCloudCapacity, mapCloudTrack;
import '../../core/models/cloud_models.dart';
import '../../core/models/track.dart';
import '../../core/source/music_source.dart';
import '../../features/auth/auth_token_holder.dart';
import '../storage/device_identity.dart';

class CloudRepository {
  CloudRepository({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  String lastError = '';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.bytes,
        validateStatus: (c) => c != null && c >= 200 && c < 500,
      ),
    );
  }

  // ── 公开 API ──────────────────────────────────────────────────────

  /// 拉取云盘一页。未登录返回空页并置 [lastError]。
  Future<CloudDiskPage> fetchCloudDiskPage({
    int page = 1,
    int pageSize = 30,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    if (!auth.hasToken || auth.userId.isEmpty) {
      lastError = '未登录';
      throw const LoginRequired('请先登录后查看云盘');
    }

    try {
      final body = await _postMcloud(
        KugoEndpoints.cloudGetList,
        dataMap: {
          'page': page,
          'pagesize': pageSize,
          'getkmr': 1,
        },
      );
      final status = _statusCode(body);
      if (status != 1) {
        lastError = _statusMessage(body, fallback: '获取云盘列表失败');
        _throwBusiness(lastError, body);
      }

      final data = body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : const <String, dynamic>{};
      final rawList = _pickList(data);
      final tracks = <Track>[];
      final seenIds = <String>{};
      for (final item in rawList) {
        if (item is! Map) continue;
        final track = mapCloudTrack(Map<String, dynamic>.from(item));
        // 上游偶发重复 id，后缀去重（对齐 EchoMusic deduplicateCloudSongs）。
        var id = track.id;
        if (seenIds.contains(id)) {
          var n = 2;
          while (seenIds.contains('${id}_$n')) {
            n++;
          }
          id = '${id}_$n';
        }
        seenIds.add(id);
        tracks.add(id == track.id ? track : track.copyWith(id: id));
      }

      final total = _intOf(data['list_count'] ?? data['count'] ?? tracks.length);
      return CloudDiskPage(
        tracks: tracks,
        total: total > 0 ? total : tracks.length,
        capacity: mapCloudCapacity(data),
        page: page,
        hasMore: tracks.length >= pageSize &&
            (total <= 0 || tracks.length < total),
      );
    } on SourceFailure {
      rethrow;
    } on DioException catch (e) {
      lastError = _dioErrorText(e);
      throw NetworkFailure(lastError, filtered: lastError.contains('过滤'));
    }
  }

  /// 解析云盘文件播放地址。
  ///
  /// 入参优先 [Track.cloudAudioSource]，缺失时回退 [Track.hash]。
  Future<PlayUrlResult> resolveCloudPlayUrl(Track track) async {
    lastError = '';
    final source = track.cloudAudioSource;
    final hash = (source?.hash.isNotEmpty == true ? source!.hash : track.hash)
        .trim()
        .toLowerCase();
    if (hash.isEmpty) {
      lastError = '缺少云盘文件 hash';
      throw const NotFound('缺少云盘文件标识，无法播放');
    }

    final auth = AuthTokenHolder.instance;
    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hasLogin = auth.hasToken && auth.userId.isNotEmpty;

    // user_cloud_url.js dataMap（kv_id 上游硬编码 2，不传真实 fileid）。
    final params = <String, dynamic>{
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
      if (hasLogin) 'token': auth.token,
      if (hasLogin) 'userid': int.tryParse(auth.userId) ?? auth.userId,
      'hash': hash,
      'ssa_flag': 'is_fromtrack',
      'version': '20102',
      'ssl': 0,
      'album_audio_id': _intOf(source?.albumAudioId ?? track.mixSongId),
      'pid': KugoEndpoints.cloudPid,
      'audio_id': _intOf(source?.audioId ?? ''),
      'kv_id': 2,
      'key': KugoSign.signCloudKey(hash, KugoEndpoints.cloudPid),
      'bucket': 'musicclound',
      'name': source?.name ?? track.name,
      'with_res_tag': 0,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params);

    try {
      final res = await _dio.get<dynamic>(
        '${KugoEndpoints.gateway}${KugoEndpoints.cloudMusicUrl}',
        queryParameters: params,
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'dfid': device.dfid,
            'clienttime': '$clienttime',
            'mid': device.mid,
            'kg-rc': '1',
            'kg-thash': '5d816a0',
            'kg-rec': '1',
            'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
            'Cookie': _cookieHeader(device, auth),
          },
          responseType: ResponseType.plain,
        ),
      );

      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) {
        lastError = '网络网关拦截（URL过滤），无法访问酷狗';
        throw NetworkFailure(lastError, filtered: true);
      }
      final decoded = decodeKugoBody(raw);
      if (decoded is! Map) {
        lastError = '云盘播放地址响应无法解析';
        throw UpstreamChanged(lastError);
      }
      final map = Map<String, dynamic>.from(decoded);
      final status = _statusCode(map);
      if (status != 1) {
        lastError = _statusMessage(map, fallback: '获取云盘播放地址失败');
        _throwBusiness(lastError, map);
      }

      final data = map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : const <String, dynamic>{};
      final url = (data['url'] ?? '').toString().trim();
      if (url.isEmpty) {
        lastError = '云盘文件暂无播放地址';
        throw const NotFound('云盘文件暂无播放地址');
      }

      final backups = <String>[];
      final backupRaw = data['backup_url'] ?? data['backupUrl'];
      if (backupRaw is List) {
        for (final u in backupRaw) {
          final s = u?.toString().trim() ?? '';
          if (s.isNotEmpty && s != url && !backups.contains(s)) backups.add(s);
        }
      } else if (backupRaw is String && backupRaw.trim().isNotEmpty) {
        backups.add(backupRaw.trim());
      }

      return PlayUrlResult(
        url: url,
        backupUrls: backups,
        // 云盘 CDN 与曲库防盗链不同，但保留同源头更稳妥。
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Referer': 'http://www.kugou.com/',
        },
      );
    } on SourceFailure {
      rethrow;
    } on DioException catch (e) {
      lastError = _dioErrorText(e);
      throw NetworkFailure(lastError, filtered: lastError.contains('过滤'));
    }
  }

  /// 删除云盘文件。目标须有 `cloudFileId`（kv_id），否则跳过。
  ///
  /// 当前上游 `del_files` **不支持**仅 hash 删除；无 fileid 的目标会记入
  /// [lastError] 并在全部无效时抛 [NotFound]。
  Future<void> deleteCloudTracks(List<CloudDeleteTarget> targets) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    if (!auth.hasToken || auth.userId.isEmpty) {
      lastError = '未登录';
      throw const LoginRequired('请先登录后操作云盘');
    }

    final removable = targets
        .where((t) => t.canDelete && t.cloudFileId.trim().isNotEmpty)
        .toList(growable: false);
    final skipped = targets.length - removable.length;
    if (removable.isEmpty) {
      lastError = '缺少云盘文件标识（kv_id），无法删除';
      throw const NotFound('缺少云盘文件标识，无法删除');
    }

    final dataMap = <String, dynamic>{
      'data': [
        for (final t in removable)
          {
            'kv_id': _intOf(t.cloudFileId),
            'album_audio_id': _intOf(t.albumAudioId),
          },
      ],
    };

    try {
      final body = await _postMcloud(KugoEndpoints.cloudDelFiles, dataMap: dataMap);
      final status = _statusCode(body);
      if (status != 1) {
        lastError = _statusMessage(body, fallback: '删除云盘歌曲失败');
        _throwBusiness(lastError, body);
      }
      if (skipped > 0) {
        lastError = '已删除 ${removable.length} 首，$skipped 首缺少文件标识被跳过';
      }
    } on SourceFailure {
      rethrow;
    } on DioException catch (e) {
      lastError = _dioErrorText(e);
      throw NetworkFailure(lastError, filtered: lastError.contains('过滤'));
    }
  }

  // ── 上传 ─────────────────────────────────────────────────────────

  /// 上传前曲库匹配（按**文件内容 MD5** 查曲库，对齐 `user_cloud_match.js`）。
  ///
  /// 匹配失败返回 null，**不阻断上传**。
  Future<CloudUploadMatch?> matchByFileHash(String fileMd5) async {
    final auth = AuthTokenHolder.instance;
    final device = await DeviceIdentity.ensure();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dataMap = <String, dynamic>{
      'appid': int.parse(KugoSign.appId),
      'clienttime': clienttime,
      'clientver': int.parse(KugoSign.clientVer),
      'data': [
        {'hash': fileMd5.toLowerCase()},
      ],
      'dfid': device.dfid,
      'key': KugoSign.signParamsKey('$clienttime'),
      'mid': device.mid,
      'show_privilege': 0,
      'show_author_alias': 0,
      'show_rel_album_audio_info': 0,
      'show_remarks': 0,
    };

    try {
      final res = await _dio.post<dynamic>(
        '${KugoEndpoints.kmrService}${KugoEndpoints.albumAudioLookup}',
        data: jsonEncode(dataMap),
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'x-router': KugoEndpoints.kmrServiceRouter,
            'Cookie': _cookieHeader(device, auth),
          },
          responseType: ResponseType.plain,
        ),
      );
      final raw = res.data?.toString() ?? '';
      if (looksLikeUrlFilter(raw)) return null;
      final decoded = decodeKugoBody(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (_statusCode(map) != 1) return null;

      final list = map['data'] is List
          ? map['data'] as List
          : (map['match_list'] is List ? map['match_list'] as List : const []);
      if (list.isEmpty) return null;
      final first = list.first;
      if (first is! Map) return null;
      final item = Map<String, dynamic>.from(first);
      final audioInfo = item['audio_info'] is Map
          ? Map<String, dynamic>.from(item['audio_info'] as Map)
          : const <String, dynamic>{};
      final match = CloudUploadMatch(
        audioId: _normalizeId(
          audioInfo['audio_id'] ?? item['audio_id'] ?? '',
        ),
        albumAudioId: _normalizeId(
          item['album_audio_id'] ?? item['mixsongid'] ?? '',
        ),
        hashStd: (audioInfo['hash'] ?? item['hash'] ?? '')
            .toString()
            .toLowerCase(),
        authorName: (item['author_name'] ?? '').toString(),
        audioName: (item['ori_audio_name'] ??
                item['audio_name'] ??
                item['songname'] ??
                '')
            .toString(),
      );
      return match.hasIds || match.hashStd.isNotEmpty ? match : null;
    } catch (_) {
      return null;
    }
  }

  /// 上传单文件到云盘（授权 → 分片 → 完成 → 写入）。
  ///
  /// 流程对齐 KuGouMusicApi `user_cloud_upload.js`：
  /// 1. GET `upload/auth`（filename = 文件 MD5）
  /// 2. POST `multipart/initiate`（`upload_id` 空 = 秒传）
  /// 3. POST `{host}/multipart/upload` × N（1MB/片）
  /// 4. POST `{host}/multipart/complete`
  /// 5. POST `mcloud /v1/add_files`
  Future<CloudUploadResult> uploadCloudFile({
    required List<int> bytes,
    required String title,
    required String extendname,
    String? authorName,
    String? audioId,
    String? albumAudioId,
    void Function(int sent, int total)? onProgress,
  }) async {
    lastError = '';
    final auth = AuthTokenHolder.instance;
    if (!auth.hasToken || auth.userId.isEmpty) {
      lastError = '未登录';
      throw const LoginRequired('请先登录后上传云盘');
    }
    if (bytes.isEmpty) {
      lastError = '文件为空';
      throw const NotFound('文件为空，无法上传');
    }

    final device = await DeviceIdentity.ensure();
    final ext = extendname.replaceFirst('.', '').toLowerCase();
    final fileMd5 = md5.convert(bytes).toString();
    final size = bytes.length;

    // 曲库关联：调用方给了就用；否则按文件 MD5 匹配（失败不阻断）。
    CloudUploadMatch? match;
    var matched = false;
    var audioIdNum = int.tryParse(audioId ?? '') ?? 0;
    var albumAudioIdNum = int.tryParse(albumAudioId ?? '') ?? 0;
    var hashStd = fileMd5;
    if (audioIdNum <= 0 && albumAudioIdNum <= 0) {
      match = await matchByFileHash(fileMd5);
      if (match != null) {
        audioIdNum = int.tryParse(match.audioId) ?? 0;
        albumAudioIdNum = int.tryParse(match.albumAudioId) ?? 0;
        if (match.hashStd.isNotEmpty) hashStd = match.hashStd;
        matched = match.hasIds;
      }
    } else {
      matched = true;
    }

    final author = authorName?.trim() ?? match?.authorName ?? '';
    final trackName = title.trim().isEmpty ? fileMd5 : title.trim();
    final displayName = author.isEmpty
        ? '$trackName.$ext'
        : '$author - $trackName.$ext';

    try {
      // ── 1. 上传授权 ──
      final authorization = await _uploadAuth(
        device: device,
        auth: auth,
        filename: fileMd5,
      );

      // ── 2. 初始化分片 ──
      final init = await _multipartInit(
        device: device,
        auth: auth,
        filename: fileMd5,
        extendname: ext,
        authorization: authorization,
      );
      final uploadId = init.uploadId;
      final externalHost = init.externalHost;
      var bssFileHash = init.bssFilename.isNotEmpty ? init.bssFilename : fileMd5;

      // ── 3/4. 分片上传 + 完成（秒传时跳过）──
      if (uploadId.isNotEmpty) {
        if (externalHost.isEmpty) {
          lastError = '初始化上传失败';
          throw UpstreamChanged(lastError);
        }
        const partSize = 1024 * 1024;
        final partCount = (size + partSize - 1) ~/ partSize;
        for (var i = 0; i < partCount; i++) {
          final start = i * partSize;
          final end = (start + partSize > size) ? size : start + partSize;
          await _multipartUploadPart(
            device: device,
            auth: auth,
            host: externalHost,
            filename: fileMd5,
            authorization: authorization,
            uploadId: uploadId,
            partNumber: i + 1,
            part: bytes.sublist(start, end),
          );
          onProgress?.call(end, size);
        }
        final completeHash = await _multipartComplete(
          device: device,
          auth: auth,
          host: externalHost,
          filename: fileMd5,
          authorization: authorization,
          uploadId: uploadId,
          partCount: partCount,
        );
        if (completeHash.isNotEmpty) bssFileHash = completeHash;
      } else {
        onProgress?.call(size, size);
      }

      // ── 5. 写入云盘 ──
      await _postMcloud(
        KugoEndpoints.cloudAddFiles,
        dataMap: {
          'data': [
            {
              'name': displayName,
              'ext': ext,
              'author_name': author,
              'hash': bssFileHash,
              'hash_std': hashStd,
              'audio_id': audioIdNum,
              'bitrate': 4,
              'album_audio_id': albumAudioIdNum,
              'size': size,
              'timelen': 0,
            },
          ],
          'list_ver': 0,
        },
      );

      return CloudUploadResult(
        secondUpload: uploadId.isEmpty,
        matched: matched,
        hash: bssFileHash,
      );
    } on SourceFailure {
      rethrow;
    } on DioException catch (e) {
      lastError = _dioErrorText(e);
      throw NetworkFailure(lastError, filtered: lastError.contains('过滤'));
    }
  }

  /// `upload/auth` → authorization 字符串。
  Future<String> _uploadAuth({
    required DeviceIdentity device,
    required AuthTokenHolder auth,
    required String filename,
  }) async {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'bucket': KugoEndpoints.cloudBucket,
      'filename': filename,
      'method': 'POST',
      'loginType': 1,
      'buVerifyCode': KugoSign.md5Hex(
        '${KugoSign.appId}${KugoEndpoints.cloudBucket}8ae10344e9738dcb',
      ),
      'extranet': 1,
      'userid': auth.userId,
      'token': auth.token,
      'version': KugoSign.clientVer,
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params, data: '');

    final res = await _dio.get<dynamic>(
      '${KugoEndpoints.gateway}${KugoEndpoints.cloudUploadAuth}',
      queryParameters: params,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Cookie': _cookieHeader(device, auth),
        },
        responseType: ResponseType.plain,
      ),
    );
    final body = _asMap(res.data);
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final authorization = (data['authorization'] ?? '').toString().trim();
    if (authorization.isEmpty) {
      lastError = _statusMessage(body, fallback: '获取上传授权失败');
      throw UpstreamChanged(lastError);
    }
    return authorization;
  }

  Future<({String uploadId, String externalHost, String bssFilename})>
      _multipartInit({
    required DeviceIdentity device,
    required AuthTokenHolder auth,
    required String filename,
    required String extendname,
    required String authorization,
  }) async {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'bucket': KugoEndpoints.cloudBucket,
      'filename': filename,
      'ssl': 1,
      'extendname': extendname,
      'version': KugoSign.clientVer,
      'userid': auth.userId,
      'token': auth.token,
      'authorization': authorization,
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params, data: '');

    final res = await _dio.post<dynamic>(
      '${KugoEndpoints.bssulbig}${KugoEndpoints.cloudMultipartInit}',
      queryParameters: params,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Authorization': authorization,
          'Cookie': _cookieHeader(device, auth),
        },
        responseType: ResponseType.plain,
      ),
    );
    final body = _asMap(res.data);
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    final uploadId = (data['upload_id'] ?? '').toString().trim();
    final externalHost = (data['external_host'] ?? '').toString().trim();
    final bssFilename =
        (data['x-bss-filename'] ?? filename).toString().trim();
    // 秒传：upload_id 为空且带 x-bss-hash；有 upload_id 则必须有 host。
    if (uploadId.isNotEmpty && externalHost.isEmpty) {
      lastError = _statusMessage(body, fallback: '初始化分片上传失败');
      throw UpstreamChanged(lastError);
    }
    return (
      uploadId: uploadId,
      externalHost: externalHost,
      bssFilename: bssFilename,
    );
  }

  Future<void> _multipartUploadPart({
    required DeviceIdentity device,
    required AuthTokenHolder auth,
    required String host,
    required String filename,
    required String authorization,
    required String uploadId,
    required int partNumber,
    required List<int> part,
  }) async {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'bucket': KugoEndpoints.cloudBucket,
      'authorization': authorization,
      'filename': filename,
      'partnumber': partNumber,
      'upload_id': uploadId,
      'body_empty': 1,
      'version': KugoSign.clientVer,
      'userid': auth.userId,
      'token': auth.token,
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params, data: '');

    final base = host.startsWith('http') ? host : 'http://$host';
    final res = await _dio.post<dynamic>(
      '$base${KugoEndpoints.cloudMultipartUpload}',
      queryParameters: params,
      data: Uint8List.fromList(part),
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Authorization': authorization,
          'Content-Type': 'application/octet-stream',
          'Cookie': _cookieHeader(device, auth),
        },
        responseType: ResponseType.plain,
      ),
    );
    final body = _asMap(res.data);
    if (_statusCode(body) != 1) {
      lastError = _statusMessage(body, fallback: '分片上传失败');
      throw UpstreamChanged(lastError);
    }
  }

  Future<String> _multipartComplete({
    required DeviceIdentity device,
    required AuthTokenHolder auth,
    required String host,
    required String filename,
    required String authorization,
    required String uploadId,
    required int partCount,
  }) async {
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final params = <String, dynamic>{
      'bucket': KugoEndpoints.cloudBucket,
      'authorization': authorization,
      'filename': filename,
      'partnumber': partCount,
      'upload_id': uploadId,
      'md5': filename,
      'version': KugoSign.clientVer,
      'userid': auth.userId,
      'token': auth.token,
      'if_id3': 1,
      'dfid': device.dfid,
      'mid': device.mid,
      'uuid': '-',
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'clienttime': clienttime,
    };
    params['signature'] = KugoSign.signatureAndroidParams(params, data: '');

    final base = host.startsWith('http') ? host : 'http://$host';
    final res = await _dio.post<dynamic>(
      '$base${KugoEndpoints.cloudMultipartComplete}',
      queryParameters: params,
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Authorization': authorization,
          'Cookie': _cookieHeader(device, auth),
        },
        responseType: ResponseType.plain,
      ),
    );
    final body = _asMap(res.data);
    if (_statusCode(body) != 1) {
      lastError = _statusMessage(body, fallback: '完成上传失败');
      throw UpstreamChanged(lastError);
    }
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : const <String, dynamic>{};
    return (data['x-bss-filename'] ?? '').toString().trim();
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  String _normalizeId(Object? v) {
    final text = (v ?? '').toString().trim();
    if (!RegExp(r'^\d+$').hasMatch(text) || RegExp(r'^0+$').hasMatch(text)) {
      return '';
    }
    return text;
  }

  String _dioErrorText(DioException e) {
    final msg = (e.message ?? '').trim();
    if (msg.isNotEmpty) return msg;
    final err = e.error?.toString().trim() ?? '';
    if (err.isNotEmpty) return err;
    return '网络请求失败（${e.type.name}）';
  }

  // ── mcloud 信封 ───────────────────────────────────────────────────

  /// POST `mcloudservice` + AES body + RSA `p`，返回解密后的业务 body。
  Future<Map<String, dynamic>> _postMcloud(
    String path, {
    required Map<String, dynamic> dataMap,
  }) async {
    final auth = AuthTokenHolder.instance;
    final device = await DeviceIdentity.ensure();
    final aes = KugoCrypto.playlistAesEncrypt(jsonEncode(dataMap));
    // userid 在 p 里用字符串（user_cloud.js 从 cookie 读出即 string）。
    final p = KugoCrypto
        .rsaEncryptPkcs1(
          jsonEncode({
            'aes': aes.key,
            'uid': auth.userId,
            'token': auth.token,
          }),
        )
        .toUpperCase();
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final res = await _dio.post<dynamic>(
      '${KugoEndpoints.mcloudService}$path',
      queryParameters: {
        'clienttime': clienttime,
        'mid': device.mid,
        'key': KugoSign.signParamsKey('$clienttime'),
        'clientver': int.parse(KugoSign.clientVer),
        'appid': int.parse(KugoSign.appId),
        'p': p,
      },
      data: Uint8List.fromList(base64.decode(aes.str)),
      options: Options(
        headers: {
          'User-Agent': KugoSign.userAgent,
          'Content-Type': 'application/json',
          'Cookie': _cookieHeader(device, auth),
          'KG-RC': '1',
          'KG-THash': '5d816a0',
          'KG-Rec': '1',
        },
      ),
    );

    final dynamic raw = res.data;
    // Dio may hand back Map (JSON transformer), String, or raw bytes.
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    List<int> bytes;
    if (raw is List<int>) {
      bytes = raw;
    } else if (raw is String) {
      bytes = utf8.encode(raw);
    } else {
      bytes = const <int>[];
    }
    if (bytes.isEmpty) {
      lastError = '云盘服务响应为空';
      throw UpstreamChanged(lastError);
    }
    final rawText = utf8.decode(bytes, allowMalformed: true);
    if (looksLikeUrlFilter(rawText)) {
      lastError = '网络网关拦截（URL过滤），无法访问酷狗';
      throw NetworkFailure(lastError, filtered: true);
    }

    final decrypted = KugoCrypto.playlistAesDecrypt(base64.encode(bytes), aes.key);
    for (final candidate in [decrypted, rawText]) {
      if (candidate == null || candidate.isEmpty) continue;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    lastError = '云盘服务响应无法解析';
    throw UpstreamChanged(lastError);
  }

  String _cookieHeader(DeviceIdentity device, AuthTokenHolder auth) {
    return [
      'token=${auth.token}',
      'userid=${auth.userId}',
      if (auth.t1.isNotEmpty) 't1=${auth.t1}',
      'dfid=${device.dfid}',
      'KUGOU_API_MID=${device.mid}',
      'KUGOU_API_GUID=${device.guid}',
      'KUGOU_API_DEV=${device.dev}',
    ].join(';');
  }

  // ── 业务解析 ──────────────────────────────────────────────────────

  int _statusCode(Map<String, dynamic> body) {
    final v = body['status'];
    if (v == 1 || v == '1' || v == true) return 1;
    return _intOf(v);
  }

  String _statusMessage(Map<String, dynamic> body, {required String fallback}) {
    final msg = (body['msg'] ?? body['error'] ?? body['message'] ?? '').toString().trim();
    return msg.isNotEmpty ? msg : fallback;
  }

  void _throwBusiness(String message, Map<String, dynamic> body) {
    final code = _intOf(
      body['error_code'] ?? body['err_code'] ?? body['errcode'],
    );
    if (code == 20018 || message.contains('登录已过期') || message.contains('未登录')) {
      throw LoginRequired(message);
    }
    if (code == 20028 || message.contains('安全验证') || message.contains('SSA')) {
      throw LoginRequired(message);
    }
    if (message.contains('URL过滤') || message.contains('网络网关')) {
      throw NetworkFailure(message, filtered: true);
    }
    if (code != 0) {
      throw UpstreamChanged('$message（error_code=$code）');
    }
    throw UpstreamChanged(message);
  }

  List<dynamic> _pickList(Map<String, dynamic> data) {
    for (final key in ['list', 'info', 'songs']) {
      final v = data[key];
      if (v is List) return v;
      // `get_list` 把列表序列化成 JSON 字符串返回（空盘为 `""`），不是原生数组；
      // 只认 List 的话永远解析不出歌曲 —— 见 docs/api-notes.md「音乐云盘」。
      if (v is String) {
        final decoded = _decodeListString(v);
        if (decoded != null) return decoded;
      }
    }
    return const [];
  }

  /// 解析 `data.list` 的字符串形态；空串 = 空盘，非数组则视为无列表。
  List<dynamic>? _decodeListString(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    if (!text.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  int _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse((v ?? '').toString().trim()) ?? 0;
  }
}

/// 默认云盘仓库实例。
final cloudRepository = CloudRepository();
