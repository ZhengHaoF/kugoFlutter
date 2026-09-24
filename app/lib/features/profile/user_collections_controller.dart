import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search_result.dart';
import '../../core/models/track.dart';
import '../../data/repositories/user_repository.dart';
import '../auth/auth_controller.dart';

class UserCollectionsState {
  const UserCollectionsState({
    this.isLoadingPlaylists = false,
    this.isLoadingFollow = false,
    this.isLoadingFavoriteTracks = false,
    this.createdPlaylists = const [],
    this.collectedPlaylists = const [],
    this.favoritedAlbums = const [],
    this.followedSingers = const [],
    this.cloudFavoriteTracks = const [],
    this.playlistsError = '',
    this.followError = '',
    this.favoriteTracksError = '',
    this.loaded = false,
  });

  final bool isLoadingPlaylists;
  final bool isLoadingFollow;
  final bool isLoadingFavoriteTracks;
  final List<PlaylistBrief> createdPlaylists;
  final List<PlaylistBrief> collectedPlaylists;
  final List<AlbumBrief> favoritedAlbums;
  final List<ArtistBrief> followedSingers;
  final List<Track> cloudFavoriteTracks;
  final String playlistsError;
  final String followError;
  final String favoriteTracksError;
  final bool loaded;

  int get totalPlaylistsCount =>
      createdPlaylists.length + collectedPlaylists.length;
  bool get isLoading =>
      isLoadingPlaylists || isLoadingFollow || isLoadingFavoriteTracks;

  /// Multi-level 「我喜欢」 resolution aligned with EchoMusic `findLikedPlaylist`.
  ///
  /// Searches created + collected so a mis-bucketed default list is still found.
  PlaylistBrief? get defaultLikedPlaylist {
    final all = [...createdPlaylists, ...collectedPlaylists];
    PlaylistBrief? byName(String exact) {
      for (final p in all) {
        if (p.name.trim() == exact) return p;
      }
      return null;
    }

    PlaylistBrief? byNameContains(String part) {
      for (final p in all) {
        if (p.name.trim().contains(part)) return p;
      }
      return null;
    }

    return byName('我喜欢的音乐') ??
        byName('我喜欢') ??
        byNameContains('喜欢') ??
        _firstWhere(all, (p) => p.type == 1 || p.isDefault) ??
        byName('默认收藏');
  }

  static PlaylistBrief? _firstWhere(
    List<PlaylistBrief> items,
    bool Function(PlaylistBrief) test,
  ) {
    for (final p in items) {
      if (test(p)) return p;
    }
    return null;
  }

  UserCollectionsState copyWith({
    bool? isLoadingPlaylists,
    bool? isLoadingFollow,
    bool? isLoadingFavoriteTracks,
    List<PlaylistBrief>? createdPlaylists,
    List<PlaylistBrief>? collectedPlaylists,
    List<AlbumBrief>? favoritedAlbums,
    List<ArtistBrief>? followedSingers,
    List<Track>? cloudFavoriteTracks,
    String? playlistsError,
    String? followError,
    String? favoriteTracksError,
    bool? loaded,
  }) {
    return UserCollectionsState(
      isLoadingPlaylists: isLoadingPlaylists ?? this.isLoadingPlaylists,
      isLoadingFollow: isLoadingFollow ?? this.isLoadingFollow,
      isLoadingFavoriteTracks:
          isLoadingFavoriteTracks ?? this.isLoadingFavoriteTracks,
      createdPlaylists: createdPlaylists ?? this.createdPlaylists,
      collectedPlaylists: collectedPlaylists ?? this.collectedPlaylists,
      favoritedAlbums: favoritedAlbums ?? this.favoritedAlbums,
      followedSingers: followedSingers ?? this.followedSingers,
      cloudFavoriteTracks: cloudFavoriteTracks ?? this.cloudFavoriteTracks,
      playlistsError: playlistsError ?? this.playlistsError,
      followError: followError ?? this.followError,
      favoriteTracksError: favoriteTracksError ?? this.favoriteTracksError,
      loaded: loaded ?? this.loaded,
    );
  }
}

class UserCollectionsNotifier extends Notifier<UserCollectionsState> {
  UserCollectionsNotifier({
    this.repository,
    this.initialState,
  });

  final UserRepository? repository;
  final UserCollectionsState? initialState;
  UserRepository get _repo => repository ?? userRepository;

  @override
  UserCollectionsState build() {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.isLogged &&
          (!state.loaded || prev?.user?.userId != next.user?.userId)) {
        loadAll();
      } else if (!next.isLogged && state.loaded) {
        reset();
      }
    });

    final initial = initialState ?? const UserCollectionsState();
    final auth = ref.read(authControllerProvider);
    if (auth.isLogged && !initial.loaded) {
      Future.microtask(() => loadAll());
    }

    return initial;
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadPlaylists(),
      loadFollow(),
    ]);
  }

  Future<void> loadPlaylists() async {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (!auth.isLogged || user == null) {
      state = state.copyWith(
        isLoadingPlaylists: false,
        playlistsError: '需登录后查看',
      );
      return;
    }

    state = state.copyWith(isLoadingPlaylists: true, playlistsError: '');
    final res = await _repo.fetchUserPlaylists(
      userId: user.userId,
      token: user.token,
    );

    state = state.copyWith(
      isLoadingPlaylists: false,
      createdPlaylists: res.created,
      collectedPlaylists: res.collected,
      favoritedAlbums: res.albums,
      playlistsError: res.error,
      loaded: true,
    );

    // Always try to pull cloud favorite tracks after playlists arrive.
    await loadFavoriteTracks();
  }

  Future<void> loadFavoriteTracks({bool force = false}) async {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (!auth.isLogged || user == null) {
      state = state.copyWith(
        isLoadingFavoriteTracks: false,
        favoriteTracksError: '需登录后查看',
      );
      return;
    }

    final likedPlaylist = state.defaultLikedPlaylist;
    if (likedPlaylist == null) {
      state = state.copyWith(
        isLoadingFavoriteTracks: false,
        favoriteTracksError: '未找到云端「我喜欢」歌单',
      );
      return;
    }

    if (!force && state.cloudFavoriteTracks.isNotEmpty) {
      return;
    }

    state = state.copyWith(
      isLoadingFavoriteTracks: true,
      favoriteTracksError: '',
    );

    // Only pass /user/playlist listid — never the public specialid.
    final cloudListId = likedPlaylist.listId.isNotEmpty
        ? likedPlaylist.listId
        : likedPlaylist.id;
    final res = await _repo.fetchUserPlaylistTracks(
      listId: cloudListId,
      userId: user.userId,
      token: user.token,
      type: 0,
      page: 1,
      pageSize: 300,
    );

    var created = state.createdPlaylists;
    final firstCover = res.tracks
        .where((t) =>
            t.coverUrl.isNotEmpty &&
            !t.coverUrl.contains('mock://') &&
            (t.coverUrl.startsWith('http://') ||
                t.coverUrl.startsWith('https://')))
        .firstOrNull
        ?.coverUrl;
    if (firstCover != null && firstCover.isNotEmpty) {
      created = created.map((p) {
        if (p.id == likedPlaylist.id &&
            (p.coverUrl.isEmpty || p.coverUrl.contains('mock://'))) {
          return PlaylistBrief(
            id: p.id,
            name: p.name,
            coverUrl: firstCover,
            description: p.description,
            creator: p.creator,
            trackCount: p.trackCount,
            playCountLabel: p.playCountLabel,
            isRank: p.isRank,
            listKind: p.listKind,
            userId: p.userId,
            isDefault: p.isDefault,
            type: p.type,
            listId: p.listId,
          );
        }
        return p;
      }).toList();
    }

    state = state.copyWith(
      isLoadingFavoriteTracks: false,
      cloudFavoriteTracks: res.tracks,
      createdPlaylists: created,
      favoriteTracksError: res.error,
    );
  }

  Future<void> loadFollow() async {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (!auth.isLogged || user == null) {
      state = state.copyWith(
        isLoadingFollow: false,
        followError: '需登录后查看',
      );
      return;
    }

    state = state.copyWith(isLoadingFollow: true, followError: '');
    final res = await _repo.fetchUserFollow(
      userId: user.userId,
      token: user.token,
    );

    state = state.copyWith(
      isLoadingFollow: false,
      followedSingers: res.singers,
      followError: res.error,
      loaded: true,
    );
  }

  void reset() {
    state = const UserCollectionsState();
  }
}

final userCollectionsProvider =
    NotifierProvider<UserCollectionsNotifier, UserCollectionsState>(
  () => UserCollectionsNotifier(),
);
