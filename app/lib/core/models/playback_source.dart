/// Where the current playback queue came from.
///
/// The player itself stays source-agnostic — [PlaybackQueueSource] only lets
/// source-specific chrome (the personal-FM controls on the player page) know
/// when to show itself, and lets the transport apply source-specific rules.
enum PlaybackQueueSource {
  /// Plain queue: playlist / album / search / rank / …
  none,

  /// A live personal-FM stream.
  ///
  /// Rules that differ from a plain queue:
  /// - `next()` never wraps around to song #1 — the stream is topped up instead
  /// - `previous()` steps back **inside the session only** and is disabled at
  ///   the session's first track
  /// - shuffle is meaningless here (the order is the recommendation order)
  fm,
}
