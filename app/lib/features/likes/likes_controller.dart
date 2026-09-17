import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';

class LikesNotifier extends Notifier<List<Track>> {
  static const _kKey = 'likes.v1';
  SharedPreferences? _prefs;

  @override
  List<Track> build() {
    unawaitedLoad();
    return const [];
  }

  Future<void> unawaitedLoad() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => _decode(Map<String, dynamic>.from(e)))
          .toList();
      state = list;
    } catch (_) {}
  }

  bool isLiked(String id) => state.any((t) => t.id == id);

  Future<void> toggle(Track track) async {
    if (isLiked(track.id)) {
      state = state.where((t) => t.id != track.id).toList();
    } else {
      state = [track, ...state];
    }
    await _persist();
  }

  Future<void> like(Track track) async {
    if (isLiked(track.id)) return;
    state = [track, ...state];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((t) => t.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(
        _kKey,
        jsonEncode(state.map(_encode).toList()),
      );
    } catch (_) {}
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

final likesProvider =
    NotifierProvider<LikesNotifier, List<Track>>(LikesNotifier.new);
