import 'package:dio/dio.dart';

import '../../core/api/kugo_sign.dart';
import '../../core/api/mappers.dart' show normalizeCoverUrl;
import '../../data/storage/device_identity.dart';
import '../../features/auth/auth_token_holder.dart';
import 'dart:convert';

class SongComment {
  const SongComment({
    required this.id,
    required this.user,
    required this.content,
    required this.likeCount,
    this.avatarUrl = '',
    this.timeLabel = '',
  });

  final String id;
  final String user;
  final String content;
  final int likeCount;
  final String avatarUrl;
  final String timeLabel;
}

class SongDetailRepository {
  SongDetailRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  String lastError = '';

  /// Song comments via gateway mcomment (KuGouMusicApi comment_music).
  Future<List<SongComment>> fetchComments({
    required String mixSongId,
    int page = 1,
    int pageSize = 20,
  }) async {
    lastError = '';
    if (mixSongId.isEmpty || mixSongId == '0') {
      lastError = '缺少歌曲 ID';
      return const [];
    }
    final device = await DeviceIdentity.ensure();
    final auth = AuthTokenHolder.instance;
    final clienttime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final query = <String, dynamic>{
      'mixsongid': int.tryParse(mixSongId) ?? mixSongId,
      'need_show_image': 1,
      'p': page,
      'pagesize': pageSize,
      'show_classify': 1,
      'show_hotword_list': 1,
      'extdata': '0',
      'code': 'fc4be23b4e972707f36b8a828a93ba8a',
      'kugouid': int.tryParse(auth.userId) ?? 0,
      'ver': 6,
      'clienttoken': auth.token,
      'appid': int.parse(KugoSign.appId),
      'clientver': int.parse(KugoSign.clientVer),
      'mid': device.mid,
      'clienttime': clienttime,
      'key': KugoSign.signParamsKey('$clienttime'),
      'uuid': '-',
      'dfid': device.dfid,
    };

    try {
      final res = await _dio.post<dynamic>(
        'https://gateway.kugou.com/mcomment/v1/cmtlist',
        queryParameters: query,
        data: const <String, dynamic>{},
        options: Options(
          headers: {
            'User-Agent': KugoSign.userAgent,
            'Content-Type': 'application/json',
            'x-router': 'm.comment.service.kugou.com',
            if (auth.hasToken) 'Authorization': auth.authorizationHeader,
            'dfid': device.dfid,
            'mid': device.mid,
          },
        ),
      );
      final raw = res.data?.toString() ?? '';
      Map<String, dynamic>? body;
      try {
        final decoded = raw.trim().startsWith('{')
            ? jsonDecode(raw)
            : raw; // Dio may return string
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (body == null) {
        lastError = '评论响应无法解析';
        return const [];
      }
      final status = body['status'];
      if (status != 1 && status != '1') {
        lastError =
            (body['error'] ?? body['msg'] ?? '评论加载失败').toString();
        return const [];
      }
      return _parseComments(body);
    } on DioException catch (e) {
      lastError = e.message ?? '网络错误';
      return const [];
    }
  }

  List<SongComment> _parseComments(Map<String, dynamic> body) {
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final list = data['info'] ??
        data['list'] ??
        data['comments'] ??
        body['info'] ??
        body['list'];
    if (list is! List) return const [];
    final out = <SongComment>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final content = (m['content'] ??
              m['comment'] ??
              m['body'] ??
              '')
          .toString()
          .trim();
      if (content.isEmpty) continue;
      final user = (m['uname'] ??
              m['username'] ??
              m['nickname'] ??
              m['user_name'] ??
              '用户')
          .toString();
      final avatarRaw = (m['pic'] ?? m['avatar'] ?? m['user_pic'] ?? '')
          .toString();
      final like = m['like_num'] ?? m['like'] ?? m['praise_num'] ?? 0;
      final likeCount = like is int
          ? like
          : int.tryParse('$like') ?? 0;
      final time = (m['addtime'] ??
              m['create_time'] ??
              m['time'] ??
              '')
          .toString();
      out.add(
        SongComment(
          id: (m['id'] ?? m['comment_id'] ?? out.length).toString(),
          user: user,
          content: content,
          likeCount: likeCount,
          avatarUrl: avatarRaw.isEmpty
              ? ''
              : normalizeCoverUrl(avatarRaw, size: '100'),
          timeLabel: _formatTime(time),
        ),
      );
    }
    return out;
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    final seconds = int.tryParse(raw);
    if (seconds == null) return raw;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      seconds > 2000000000 ? seconds : seconds * 1000,
    );
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

final songDetailRepository = SongDetailRepository();
