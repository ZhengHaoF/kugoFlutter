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
      // lyrics.kugou.com may return JSON with unquoted keys — read as text.
      final raw = await _client.getText(searchUrl);
      final candidates = <({String id, String accessKey})>[
        ..._parseCandidatesLoose(raw),
      ];
      if (candidates.isEmpty) {
        try {
          final searchJson = await _client.getJson(searchUrl);
          candidates.addAll(_parseCandidates(searchJson));
        } catch (_) {}
      }
      if (candidates.isEmpty) return const [];

      for (final c in candidates) {
        final raw = await _download(c.id, c.accessKey);
        if (raw.trim().isEmpty) continue;
        final lines = parseLrc(raw);
        if (lines.isNotEmpty) return lines;
      }
    } catch (_) {}
    return const [];
  }

  List<({String id, String accessKey})> _parseCandidatesLoose(String raw) {
    final result = <({String id, String accessKey})>[];
    // Matches both quoted and unquoted JSON-ish fields.
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
      final limited = ids.take(3);
      for (final id in limited) {
        result.add((id: id, accessKey: ''));
      }
    }
    return result;
  }

  List<({String id, String accessKey})> _parseCandidates(dynamic data) {
    if (data is! Map) return const [];
    final map = Map<String, dynamic>.from(data);
    final list = map['candidates'];
    if (list is! List) return const [];
    final result = <({String id, String accessKey})>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString();
      final key = (item['accesskey'] ?? item['access_key'] ?? '').toString();
      if (id.isNotEmpty) {
        result.add((id: id, accessKey: key));
      }
    }
    return result;
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
