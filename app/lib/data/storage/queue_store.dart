import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';

/// Lightweight queue/history persistence (Phase 2; replace with Drift later).
class QueueStore {
  QueueStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kQueue = 'player.queue.v1';
  static const _kIndex = 'player.index.v1';
  static const _kMode = 'player.mode.v1';
  static const _kHistory = 'player.history.v1';

  static Future<QueueStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return QueueStore(prefs);
  }

  Future<void> saveQueue(List<Track> queue, int index, String mode) async {
    await _prefs.setString(_kQueue, jsonEncode(queue.map(_encode).toList()));
    await _prefs.setInt(_kIndex, index);
    await _prefs.setString(_kMode, mode);
  }

  ({List<Track> queue, int index, String mode})? loadQueue() {
    final raw = _prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => _decode(Map<String, dynamic>.from(e)))
          .toList();
      return (
        queue: list,
        index: _prefs.getInt(_kIndex) ?? 0,
        mode: _prefs.getString(_kMode) ?? 'listLoop',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> appendHistory(Track track) async {
    final raw = _prefs.getString(_kHistory);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        list.addAll(
          (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }
    list.removeWhere((e) => e['id'] == track.id);
    list.insert(0, _encode(track));
    if (list.length > 200) {
      list.removeRange(200, list.length);
    }
    await _prefs.setString(_kHistory, jsonEncode(list));
  }

  List<Track> loadHistory() {
    final raw = _prefs.getString(_kHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => _decode(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearAll() async {
    await _prefs.remove(_kQueue);
    await _prefs.remove(_kIndex);
    await _prefs.remove(_kMode);
    await _prefs.remove(_kHistory);
  }

  Map<String, dynamic> _encode(Track t) => {
        'id': t.id,
        'name': t.name,
        'artist': t.artist,
        'album': t.album,
        'coverUrl': t.coverUrl,
        'durationMs': t.durationMs,
        'hash': t.hash,
        'albumId': t.albumId,
        'mixSongId': t.mixSongId,
        'quality': t.quality,
        'isVip': t.isVip,
      };

  Track _decode(Map<String, dynamic> j) => Track(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        artist: j['artist']?.toString() ?? '',
        album: j['album']?.toString() ?? '',
        coverUrl: j['coverUrl']?.toString() ?? '',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        hash: j['hash']?.toString() ?? '',
        albumId: j['albumId']?.toString() ?? '',
        mixSongId: j['mixSongId']?.toString() ?? '',
        quality: j['quality']?.toString() ?? 'SQ',
        isVip: j['isVip'] == true,
      );
}
