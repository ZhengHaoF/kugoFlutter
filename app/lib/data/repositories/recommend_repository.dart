import '../../core/models/track.dart';
import 'playlist_repository.dart';
import 'search_repository.dart';

/// Public-API daily mix (no personalization login).
/// Rotates by calendar day: prefer a rank board, pad with mood searches.
class RecommendRepository {
  RecommendRepository({
    PlaylistRepository? playlists,
    SearchRepository? search,
  })  : _playlists = playlists ?? playlistRepository,
        _search = search ?? searchRepository;

  final PlaylistRepository _playlists;
  final SearchRepository _search;

  static const moods = [
    '华语流行',
    '民谣精选',
    '轻音乐',
    '说唱热歌',
    '国风新声',
    '摇滚经典',
    '电子夜行',
    '治愈系',
  ];

  int dayOfYear([DateTime? date]) {
    final d = date ?? DateTime.now();
    return d.difference(DateTime(d.year)).inDays + 1;
  }

  String moodLabel([DateTime? date]) {
    return moods[dayOfYear(date) % moods.length];
  }

  String dateLabel([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.month}月${d.day}日';
  }

  Future<List<Track>> fetchDaily({DateTime? date, int limit = 30}) async {
    final seed = dayOfYear(date);
    final tracks = <Track>[];
    final seen = <String>{};

    void addAll(Iterable<Track> list) {
      for (final t in list) {
        if (tracks.length >= limit) return;
        final key = t.id.isNotEmpty ? t.id : t.hash;
        if (key.isEmpty || !seen.add(key)) continue;
        tracks.add(t);
      }
    }

    try {
      final ranks = await _playlists.fetchRankList();
      if (ranks.isNotEmpty) {
        final pick = ranks[seed % ranks.length];
        final detail = await _playlists.fetchPlaylist(pick.id, pageSize: limit);
        if (detail != null) addAll(detail.tracks);
      }
    } catch (_) {
      // fall through to keyword fill
    }

    if (tracks.length < 15) {
      final keywords = [
        moods[seed % moods.length],
        moods[(seed * 3 + 1) % moods.length],
      ];
      for (final kw in keywords) {
        if (tracks.length >= limit) break;
        try {
          addAll(await _search.searchSongs(kw, pageSize: 20));
        } catch (_) {
          // try next keyword
        }
      }
    }

    return tracks;
  }
}

final recommendRepository = RecommendRepository();
