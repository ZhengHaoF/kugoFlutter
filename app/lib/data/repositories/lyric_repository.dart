import 'dart:convert';

import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/models/track.dart';
import '../../core/utils/lrc_parser.dart';

class LyricRepository {
  LyricRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  Future<List<LyricLine>> fetchLyrics(Track track) async {
    final keyword = '${track.artist} ${track.name}'.trim();
    final hash = track.hash.toLowerCase();

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
          'timelength': track.durationMs,
        },
      );
      final raw = await _client.getText(searchUrl);
      final candidates = _parseCandidatesLoose(raw);
      if (candidates.isEmpty) {
        try {
          final searchJson = await _client.getJson(searchUrl);
          candidates.addAll(_parseCandidates(searchJson));
        } catch (_) {}
      }
      if (candidates.isEmpty) return const [];

      // Only try the best 1–2 candidates (EchoMusic uses proposal / first).
      final limited = candidates.take(2).toList();
      for (final c in limited) {
        final body = await _download(c.id, c.accessKey);
        if (body.trim().isEmpty) continue;
        final lrc = _extractLrcText(body);
        final lines = parseLrc(lrc);
        if (lines.isNotEmpty) return lines;
      }
    } catch (_) {}
    return const [];
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
      if (result.length >= 2) break;
    }
    if (result.isEmpty) {
      final ids = RegExp('id\\s*:\\s*"?([0-9]{4,})"')
          .allMatches(raw)
          .map((m) => m.group(1)!)
          .toSet();
      for (final id in ids.take(2)) {
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
        if (result.length >= 2) break;
      }
    }
    if (proposal.isNotEmpty && result.every((e) => e.id != proposal)) {
      result.insert(0, (id: proposal, accessKey: result.isEmpty ? '' : result.first.accessKey));
    }
    return result.take(2).toList();
  }

  /// Download returns JSON with base64 `content`, or plain LRC text.
  String _extractLrcText(String body) {
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

  Future<String> _download(String id, String accessKey) {
    final url = buildUrl(KugoEndpoints.lyrics, KugoEndpoints.lyricDownload, {
      'ver': 1,
      'client': 'pc',
      'id': id,
      'accesskey': accessKey,
      'fmt': 'lrc',
      'charset': 'utf8',
    });
    return _client.getText(url);
  }
}

final lyricRepository = LyricRepository();
