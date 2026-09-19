/// Search result models for the multi-tab search page.
///
/// Each tab hits a different kugou endpoint, so the shapes differ — notably
/// [ArtistBrief] is deliberately thin because `search/singer` returns only
/// `singername` + `singerid` (no avatar, no counts).
///
/// [PlaylistBrief] lives in `track.dart` and is reused here rather than
/// duplicated, since `/playlist/:id` already consumes that exact type.
library;

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
  });

  /// Numeric `albumid` — what `/album/:id` expects.
  final String id;
  final String name;
  final String coverUrl;
  final String artist;
  final int trackCount;
  final String publishDate;
}

/// An artist as returned by `search/singer`.
///
/// The endpoint gives **only** these two fields; do not try to backfill
/// artwork or counts per row (that would be an N+1 request storm).
class ArtistBrief {
  const ArtistBrief({required this.id, required this.name});

  /// Numeric `singerid` — what `/artist/:id` expects.
  final String id;
  final String name;
}
