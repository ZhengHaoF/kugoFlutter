/// Search result models for the multi-tab search page.
///
/// Each tab hits a different kugou endpoint, so the shapes differ — notably
/// [ArtistBrief] is deliberately thin because `search/singer` returns only
/// `singername` + `singerid` (no avatar, no counts).
///
/// [PlaylistBrief] lives in `track.dart` and is reused here rather than
/// duplicated, since `/playlist/:id` already consumes that exact type.
library;

import '../source/music_platform.dart';
import 'track.dart';

export 'track.dart' show PlaylistBrief;

/// One page of results for a single search tab.
class SearchPageResult<T> {
  const SearchPageResult({
    required this.items,
    this.total,
  });

  const SearchPageResult.empty()
      : items = const [],
        total = null;

  final List<T> items;

  /// Server-reported total; `null` when the endpoint omits it
  /// (`search/singer` does). Never invent a number here.
  final int? total;

  bool get isEmpty => items.isEmpty;
}

/// An album as returned by `search/album`.
class AlbumBrief {
  const AlbumBrief({
    required this.id,
    required this.name,
    required this.coverUrl,
    this.artist = '',
    this.trackCount = 0,
    this.publishDate = '',
    this.platform = MusicPlatform.kugou,
  });

  /// Numeric `albumid` — what `/album/:id` expects.
  final String id;
  final String name;
  final String coverUrl;
  final String artist;
  final int trackCount;
  final String publishDate;

  /// 归属音源；混排结果里据此出「来源角标」。
  final MusicPlatform platform;
}

/// An artist as returned by `search/singer` or `user/follow`.
///
/// `search/singer` itself only carries id + name; [avatarUrl] is backfilled
/// from `singer/info` (see [SearchRepository.searchArtists]).
class ArtistBrief {
  const ArtistBrief({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.songCount = 0,
    this.fansCount = 0,
    this.sourceDesc = '',
    this.platform = MusicPlatform.kugou,
  });

  /// Numeric `singerid` — what `/artist/:id` expects.
  final String id;
  final String name;
  final String avatarUrl;
  final int songCount;
  final int fansCount;
  final String sourceDesc;

  /// 归属音源；混排结果里据此出「来源角标」。
  final MusicPlatform platform;

  ArtistBrief copyWith({
    String? avatarUrl,
    int? songCount,
    int? fansCount,
    String? sourceDesc,
    MusicPlatform? platform,
  }) {
    return ArtistBrief(
      id: id,
      name: name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      songCount: songCount ?? this.songCount,
      fansCount: fansCount ?? this.fansCount,
      sourceDesc: sourceDesc ?? this.sourceDesc,
      platform: platform ?? this.platform,
    );
  }
}

