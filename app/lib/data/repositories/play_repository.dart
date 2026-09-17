import '../../core/api/endpoints.dart';
import '../../core/api/kugo_client.dart';
import '../../core/models/track.dart';

/// Resolves playable audio URLs for a track hash.
class PlayRepository {
  PlayRepository({KugoClient? client}) : _client = client ?? kugoClient;

  final KugoClient _client;

  static const _mid = 'kugo_flutter_mid';
  static const _guid = 'kugo_flutter_guid';

  Future<ResolvedAudio?> resolveUrl(
    Track track, {
    String quality = '',
  }) async {
    final hash = track.hash.trim().toLowerCase();
    if (hash.isEmpty) return null;

    final urls = <String>[];
    final usedQuality = quality.isEmpty ? '128k' : quality;

    // 1) wwwapi play/getdata
    try {
      final url = buildUrl(KugoEndpoints.wwwApi, KugoEndpoints.playData, {
        'r': 'play/getdata',
        'hash': hash,
        'album_id': track.albumId,
        'album_audio_id': track.mixSongId,
        'mid': _mid,
        'guid': _guid,
        'platid': 4,
        'appid': 1014,
        if (quality.isNotEmpty) 'extname': quality,
      });
      final data = await _client.getJson(url);
      urls.addAll(_parsePlayData(data));
    } catch (_) {}

    // 2) tracker fallback
    if (urls.isEmpty) {
      try {
        final url = buildUrl(KugoEndpoints.tracker, KugoEndpoints.trackerPlay, {
          'cmd': 23,
          'pid': 1,
          'behavior': 'play',
          'hash': hash,
          'album_id': track.albumId,
        });
        final data = await _client.getJson(url);
        urls.addAll(_parseTracker(data));
      } catch (_) {}
    }

    if (urls.isEmpty) return null;
    return ResolvedAudio(
      url: urls.first,
      backupUrls: urls.skip(1).toList(),
      quality: usedQuality,
    );
  }

  List<String> _parsePlayData(dynamic data) {
    if (data is! Map) return const [];
    final map = Map<String, dynamic>.from(data);
    Map<String, dynamic> payload;
    if (map['data'] is Map) {
      payload = Map<String, dynamic>.from(map['data'] as Map);
    } else {
      payload = map;
    }
    final urls = <String>[];
    void add(Object? v) {
      final s = v == null ? '' : v.toString().trim();
      if (s.startsWith('http')) urls.add(s);
    }

    add(payload['url']);
    add(payload['play_url']);
    final backup = payload['backup_url'] ?? payload['backupUrl'];
    if (backup is List) {
      for (final b in backup) {
        add(b);
      }
    } else {
      add(backup);
    }
    return urls;
  }

  List<String> _parseTracker(dynamic data) {
    if (data is! Map) return const [];
    final map = Map<String, dynamic>.from(data);
    final urls = <String>[];
    void walk(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k == 'url' || k == 'urls' || k == 'play_url') {
            final v = entry.value;
            if (v is String && v.startsWith('http')) {
              urls.add(v);
            } else if (v is List) {
              for (final item in v) {
                if (item is String && item.startsWith('http')) {
                  urls.add(item);
                }
              }
            }
          } else {
            walk(entry.value);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(map);
    return urls.toSet().toList();
  }
}

final playRepository = PlayRepository();
