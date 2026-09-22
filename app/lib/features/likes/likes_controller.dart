import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';
import '../../data/repositories/user_repository.dart';
import '../auth/auth_controller.dart';
import '../profile/user_collections_controller.dart';

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
    if (isLiked(track.id)) return;
    state = [track, ...state];
    await _persist();
    await _syncAddToCloud(track);
  }

  Future<void> remove(String id) async {
    final track = state.where((t) => t.id == id).firstOrNull;
    state = state.where((t) => t.id != id).toList();
    await _persist();
    if (track != null) {
      await _syncRemoveFromCloud(track);
    }
  }

  /// Removes by track so cloud fileid is available even when only cloud has it.
  Future<void> removeTrack(Track track) async {
    state = state.where((t) => t.id != track.id).toList();
    await _persist();
    await _syncRemoveFromCloud(track);
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

  ({String listId, String userId, String token})? _cloudContext() {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (!auth.isLogged || user == null) return null;
    final liked = ref.read(userCollectionsProvider).defaultLikedPlaylist;
    if (liked == null) return null;
    final listId = liked.listId.isNotEmpty ? liked.listId : liked.id;
    if (listId.isEmpty) return null;
    return (listId: listId, userId: user.userId, token: user.token);
  }

  Future<void> _syncAddToCloud(Track track) async {
    final ctx = _cloudContext();
    if (ctx == null) return;
    await userRepository.addPlaylistTrack(
      listId: ctx.listId,
      userId: ctx.userId,
      token: ctx.token,
      name: track.name,
      hash: track.hash,
      albumId: track.albumId,
      mixSongId: track.mixSongId,
    );
  }

  Future<void> _syncRemoveFromCloud(Track track) async {
    final ctx = _cloudContext();
    if (ctx == null) return;
    final fileId = track.mixSongId.isNotEmpty ? track.mixSongId : track.id;
    if (fileId.isEmpty) return;
    await userRepository.deletePlaylistTracks(
      listId: ctx.listId,
      userId: ctx.userId,
      token: ctx.token,
      fileIds: [fileId],
    );
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
