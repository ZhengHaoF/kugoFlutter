import 'dart:convert';
import 'dart:typed_data';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/models/track.dart';
import '../../core/utils/krc_parser.dart';
import '../../core/utils/lrc_parser.dart';

class LyricRepository {
  LyricRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  /// 拉取当前曲歌词。
  ///
  /// 优先 `fmt=krc`（逐字 + 可能的 `[language:]` 翻译/音译）；失败或无
  /// 行时回退 `fmt=lrc`。与是否播放解耦。
  Future<List<LyricLine>> fetchLyrics(Track track) async {
    final keyword = '${track.artist} ${track.name}'.trim();
    final hash = track.hash.toLowerCase();

    final candidates = await _searchCandidates(keyword, hash, track.durationMs);
    if (candidates.isEmpty) return const [];

    // 官方推荐优先（search 已把 proposal 插到前）；每条先试 KRC。
    final limited = candidates.take(3).toList();
    for (final c in limited) {
      final krc = await _tryDownload(c.id, c.accessKey, fmt: 'krc');
      if (krc != null) {
        final result = parseKrc(krc);
        if (result.lines.isNotEmpty) return result.lines;
      }
    }
    // KRC 全失败 → LRC 兜底。
    for (final c in limited) {
      final lrc = await _tryDownload(c.id, c.accessKey, fmt: 'lrc');
      if (lrc != null) {
        final lines = parseLrc(lrc);
        if (lines.isNotEmpty) return lines;
      }
    }
    return const [];
  }

  Future<List<({String id, String accessKey})>> _searchCandidates(
    String keyword,
    String hash,
    int durationMs,
  ) async {
    try {
      final searchUrl = buildUrl(
        KugoEndpoints.lyrics,
        KugoEndpoints.lyricSearch,
        {
          'ver': 1,
          'man': 'yes',
          'client': 'pc',
          'keyword': keyword,
          'hash': hash,
          'timelength': durationMs,
        },
      );
      final raw = await _client.getText(searchUrl);
      final candidates = _parseCandidatesLoose(raw);
      if (candidates.isNotEmpty) return candidates;
      try {
        final searchJson = await _client.getJson(searchUrl);
        return _parseCandidates(searchJson);
      } catch (_) {
        return candidates;
      }
    } catch (_) {
      return const [];
    }
  }

  /// Prefer highest-score candidate (first in list from kugou).
  List<({String id, String accessKey})> _parseCandidatesLoose(String raw) {
    final result = <({String id, String accessKey})>[];
    final block = RegExp(
      'id\\s*:\\s*"?([0-9]+)"?[\\s\\S]{0,400}?accesskey\\s*:\\s*"?([0-9A-Fa-f]+)"?',
      caseSensitive: false,
    );
    for (final m in block.allMatches(raw)) {
      result.add((id: m.group(1)!, accessKey: m.group(2)!));
      if (result.length >= 3) break;
    }
    if (result.isEmpty) {
      final ids = RegExp('id\\s*:\\s*"?([0-9]{4,})"')
          .allMatches(raw)
          .map((m) => m.group(1)!)
          .toSet();
      for (final id in ids.take(3)) {
        result.add((id: id, accessKey: ''));
      }
    }
    return result;
  }

  List<({String id, String accessKey})> _parseCandidates(dynamic data) {
    if (data is! Map) return const [];
    final map = Map<String, dynamic>.from(data);
    // Prefer official proposal when present.
    final proposal = (map['proposal'] ?? '').toString();
    final list = map['candidates'];
    final result = <({String id, String accessKey})>[];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final id = (item['id'] ?? item['download_id'] ?? '').toString();
        final key =
            (item['accesskey'] ?? item['access_key'] ?? '').toString();
        if (id.isNotEmpty) {
          result.add((id: id, accessKey: key));
        }
        if (result.length >= 3) break;
      }
    }
    if (proposal.isNotEmpty && proposal != '0' && result.every((e) => e.id != proposal)) {
      result.insert(0, (id: proposal, accessKey: result.isEmpty ? '' : result.first.accessKey));
    }
    return result.take(3).toList();
  }

  /// 下载并解出歌词正文；KRC 走解密，LRC 走 base64/纯文本。
  Future<String?> _tryDownload(
    String id,
    String accessKey, {
    required String fmt,
  }) async {
    try {
      final url = buildUrl(KugoEndpoints.lyrics, KugoEndpoints.lyricDownload, {
        'ver': 1,
        'client': 'pc',
        'id': id,
        'accesskey': accessKey,
        'fmt': fmt,
        'charset': 'utf8',
      });
      final body = await _client.getText(url);
      return fmt == 'krc' ? _extractKrcText(body) : _extractLrcText(body);
    } catch (_) {
      return null;
    }
  }

  String? _extractKrcText(String body) {
    final bytes = _extractContentBytes(body);
    if (bytes == null) return null;
    return decryptKrc(bytes);
  }

  /// Download returns JSON with base64 `content`, or plain LRC text.
  String? _extractLrcText(String body) {
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map) {
          final content = map['content'];
          if (content is String && content.isNotEmpty) {
            try {
              return utf8.decode(base64.decode(content));
            } catch (_) {
              return content;
            }
          }
        }
      } catch (_) {}
    }
    // Already plain LRC (or base64 blob without JSON wrapper).
    if (trimmed.contains('[00:') || trimmed.contains('[ti:') || trimmed.contains('[ar:')) {
      return trimmed;
    }
    try {
      final decoded = utf8.decode(base64.decode(trimmed));
      if (decoded.contains('[')) return decoded;
    } catch (_) {}
    return trimmed;
  }

  Uint8List? _extractContentBytes(String body) {
    final trimmed = body.trim();
    try {
      if (trimmed.startsWith('{')) {
        final map = jsonDecode(trimmed);
        if (map is Map) {
          final content = map['content'];
          if (content is String && content.isNotEmpty) {
            try {
              return base64.decode(content);
            } catch (_) {
              return Uint8List.fromList(utf8.encode(content));
            }
          }
        }
      }
      return base64.decode(trimmed);
    } catch (_) {
      return null;
    }
  }
}

final lyricRepository = LyricRepository();
