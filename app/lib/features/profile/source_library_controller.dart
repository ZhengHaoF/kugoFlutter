import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../core/source/capabilities.dart';
import '../../core/source/music_platform.dart';
import '../../core/source/music_source.dart';
import '../../core/source/registry.dart';
import '../settings/settings_controller.dart';

/// 某一音源的云端资料库（我喜欢 / 歌单 / 收藏专辑 / 关注歌手）。
///
/// 取数一律经 [UserPlaylistReadSource] + [UserLibrarySource]，
/// UI 不再区分 `userCollectionsProvider` / `neteaseLikesProvider` 双栈。
class SourceLibraryState {
  const SourceLibraryState({
    this.likedTracks = const [],
    this.createdPlaylists = const [],
    this.collectedPlaylists = const [],
    this.favoritedAlbums = const [],
    this.followedArtists = const [],
    this.loading = false,
    this.loaded = false,
    this.loadingLiked = false,
    this.error = '',
    this.likedError = '',
  });

  final List<Track> likedTracks;
  final List<PlaylistBrief> createdPlaylists;
  final List<PlaylistBrief> collectedPlaylists;
  final List<AlbumBrief> favoritedAlbums;
  final List<ArtistBrief> followedArtists;
  final bool loading;
  final bool loaded;
  final bool loadingLiked;
  final String error;
  final String likedError;

  int get totalPlaylistsCount => createdPlaylists.length + collectedPlaylists.length;

  /// 云端「我喜欢」歌单（与 [UserPlaylistsPage.likedPlaylist] 同一口径）。
  PlaylistBrief? get likedPlaylist =>
      findLikedPlaylist([...createdPlaylists, ...collectedPlaylists]);

  SourceLibraryState copyWith({
    List<Track>? likedTracks,
    List<PlaylistBrief>? createdPlaylists,
    List<PlaylistBrief>? collectedPlaylists,
    List<AlbumBrief>? favoritedAlbums,
    List<ArtistBrief>? followedArtists,
    bool? loading,
    bool? loaded,
    bool? loadingLiked,
    String? error,
    String? likedError,
  }) {
    return SourceLibraryState(
      likedTracks: likedTracks ?? this.likedTracks,
      createdPlaylists: createdPlaylists ?? this.createdPlaylists,
      collectedPlaylists: collectedPlaylists ?? this.collectedPlaylists,
      favoritedAlbums: favoritedAlbums ?? this.favoritedAlbums,
      followedArtists: followedArtists ?? this.followedArtists,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      loadingLiked: loadingLiked ?? this.loadingLiked,
      error: error ?? this.error,
      likedError: likedError ?? this.likedError,
    );
  }
}

/// 按源拉取云端资料库。能力缺失（源未实现）→ 空态，不抛到 UI。
class SourceLibraryNotifier
    extends FamilyNotifier<SourceLibraryState, MusicPlatform> {
  @override
  SourceLibraryState build(MusicPlatform arg) {
    // 首次构建后自动拉一次（与旧 userCollections 时序一致）。
    Future.microtask(() {
      if (!state.loaded && !state.loading) {
        unawaited(loadPlaylists());
      }
    });
    return const SourceLibraryState();
  }

  UserPlaylistReadSource? _playlists(MusicPlatform platform) {
    final registry = musicSourceRegistry;
    return registry?.capability<UserPlaylistReadSource>(platform);
  }

  UserLibrarySource? _library(MusicPlatform platform) {
    final registry = musicSourceRegistry;
    return registry?.capability<UserLibrarySource>(platform);
  }

  /// 拉歌单 + 收藏专辑 + 关注歌手。
  Future<void> loadPlaylists({bool force = false}) async {
    if (state.loading) return;
    if (!force && state.loaded) return;
    final src = _playlists(arg);
    if (src == null) {
      state = state.copyWith(loading: false, loaded: true);
      return;
    }
    state = state.copyWith(loading: true, error: '');
    try {
      final page = await src.userPlaylists();
      state = state.copyWith(
        loading: false,
        loaded: true,
        createdPlaylists: page.created,
        collectedPlaylists: page.collected,
        favoritedAlbums: page.favoritedAlbums,
        followedArtists: page.followedArtists,
        error: '',
      );
    } catch (e) {
      // 歌单 / 关注失败只记在 [error]（歌手·专辑 Tab 用），不阻断下面的
      // 「我喜欢」：酷狗侧两者本就会各自重取，不能让歌单失败把红心也
      // 悄悄变成空列表。
      state = state.copyWith(loading: false, loaded: true, error: _msg(e));
    }
    // 「我喜欢」独立取数：成功与否都跑一次，失败会落在 `likedError`，
    // 由歌曲 Tab 明确报错，而不是显示成「还没有红心歌曲」。
    await loadLikedTracks(force: force);
  }

  /// 拉云端「我喜欢」全量曲目。
  Future<void> loadLikedTracks({bool force = false}) async {
    if (state.loadingLiked) return;
    if (!force && state.likedTracks.isNotEmpty && state.likedError.isEmpty) {
      return;
    }
    final src = _library(arg);
    if (src == null) {
      state = state.copyWith(loadingLiked: false);
      return;
    }
    state = state.copyWith(loadingLiked: true, likedError: '');
    try {
      final tracks = await src.likedTracks();
      state = state.copyWith(
        loadingLiked: false,
        likedTracks: tracks,
        likedError: '',
      );
    } catch (e) {
      state = state.copyWith(loadingLiked: false, likedError: _msg(e));
    }
  }

  Future<void> loadAll({bool force = false}) async {
    await Future.wait([
      loadPlaylists(force: force),
      loadLikedTracks(force: force),
    ]);
  }

  void reset() {
    state = const SourceLibraryState();
  }

  static String _msg(Object e) {
    if (e is SourceFailure) return e.message;
    final s = e.toString().split('\n').first.trim();
    return s.isEmpty ? '网络异常' : s;
  }
}

/// 该源是否已登录（经 [UserLikedWriteSource]；无写能力/空平台时 false）。
bool isSourceLoggedIn(MusicPlatform? platform) {
  if (platform == null) return false;
  return musicSourceRegistry
          ?.capability<UserLikedWriteSource>(platform)
          ?.isLoggedIn ??
      false;
}

/// 单源资料库。
final sourceLibraryProvider = NotifierProvider.family<SourceLibraryNotifier,
    SourceLibraryState, MusicPlatform>(SourceLibraryNotifier.new);

/// 合并视图：`null` = 已启用源全量（酷狗在前）；指定源 = 只取该源。
///
/// UI 用它替代「`switch (platform)` 拼两套状态」。
final mergedSourceLibraryProvider =
    Provider.family<SourceLibraryState, MusicPlatform?>((ref, filter) {
  if (filter != null) {
    return ref.watch(sourceLibraryProvider(filter));
  }
  final enabled =
      ref.watch(settingsControllerProvider.select((s) => s.enabledSources));
  final registry = musicSourceRegistry;
  if (registry == null) return const SourceLibraryState();

  final parts = [
    for (final p in registry.platforms)
      if (enabled.contains(p)) ref.watch(sourceLibraryProvider(p)),
  ];
  if (parts.isEmpty) return const SourceLibraryState();
  if (parts.length == 1) return parts.first;

  return SourceLibraryState(
    likedTracks: [for (final p in parts) ...p.likedTracks],
    createdPlaylists: [for (final p in parts) ...p.createdPlaylists],
    collectedPlaylists: [for (final p in parts) ...p.collectedPlaylists],
    favoritedAlbums: [for (final p in parts) ...p.favoritedAlbums],
    followedArtists: [for (final p in parts) ...p.followedArtists],
    loading: parts.any((p) => p.loading),
    loaded: parts.every((p) => p.loaded),
    loadingLiked: parts.any((p) => p.loadingLiked),
    error: parts.map((p) => p.error).where((e) => e.isNotEmpty).join('；'),
    likedError:
        parts.map((p) => p.likedError).where((e) => e.isNotEmpty).join('；'),
  );
});
