import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/registry.dart';

/// 本地红心缓存（离线可用）。云端同步一律经 [UserLikedWriteSource]。
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
      await remove(track.id);
    } else {
      await like(track);
    }
  }

  Future<void> like(Track track) async {
    await likeLocal(track);
    await _syncCloud(track, liked: true);
  }

  /// 只写本地「我喜欢」，不碰云端曲库（无登录 / 无写能力时用）。
  Future<void> likeLocal(Track track) async {
    if (isLiked(track.id)) return;
    state = [track, ...state];
    await _persist();
  }

  Future<void> remove(String id) async {
    final track = state.where((t) => t.id == id).firstOrNull;
    state = state.where((t) => t.id != id).toList();
    await _persist();
    if (track != null) {
      await _syncCloud(track, liked: false);
    }
  }

  /// Removes by track so cloud identity is available even when only cloud has it.
  Future<void> removeTrack(Track track) async {
    state = state.where((t) => t.id != track.id).toList();
    await _persist();
    await _syncCloud(track, liked: false);
  }

  /// Merges cloud favorite tracks into the local heart set (offline cache).
  void absorbCloudTracks(List<Track> cloudTracks) {
    if (cloudTracks.isEmpty) return;
    final existing = state.map((t) => t.id).toSet();
    final incoming = cloudTracks.where((t) => !existing.contains(t.id)).toList();
    if (incoming.isEmpty) return;
    state = [...incoming, ...state];
    unawaited(_persist());
  }

  /// 云端红心：按 `track.platform` 取 [UserLikedWriteSource]。
  /// 未登录 / 无写能力时静默跳过（本地红心仍生效）。
  Future<void> _syncCloud(Track track, {required bool liked}) async {
    final src = musicSourceRegistry
        ?.capability<UserLikedWriteSource>(track.platform);
    if (src == null || !src.isLoggedIn) return;
    try {
      await src.setTrackLiked(track, liked: liked);
    } catch (_) {
      // 写失败不回滚本地红心：离线/风控时保底可听可标。
    }
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
