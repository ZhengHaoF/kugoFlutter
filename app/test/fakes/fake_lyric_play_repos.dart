import 'package:dio/dio.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/lyric_repository.dart';
import 'package:kugo/data/repositories/play_repository.dart';

/// Test double for [LyricRepository] — only `fetchLyrics` is public API.
class FakeLyricRepository implements LyricRepository {
  final List<String> requestedKeys = [];
  final Map<String, List<LyricLine>> byKey = {};
  bool Function(Track track)? onFetch;

  /// When set, fetch awaits this future (for in-flight / race tests).
  Future<void>? gate;

  String keyOf(Track t) => '${t.id}|${t.hash}';

  @override
  Future<List<LyricLine>> fetchLyrics(Track track) async {
    final key = keyOf(track);
    requestedKeys.add(key);
    onFetch?.call(track);
    final g = gate;
    if (g != null) await g;
    return byKey[key] ?? const [];
  }
}

/// Offline stand-in for [PlayRepository] so hash-track tests never hit network.
class FakePlayRepository extends PlayRepository {
  FakePlayRepository() : super(dio: Dio()) {
    // Default success so multi-track tests don't trip play-error auto-next.
    nextResolved = ResolvedAudio(
      url: 'https://example.com/fake.mp3',
      quality: '128',
    );
  }

  ResolvedAudio? nextResolved;
  String errorText = 'fake play fail';
  String _err = '';
  int resolveCalls = 0;

  /// When set, resolve awaits this future (for track-switch race tests).
  Future<void>? gate;

  @override
  String get lastError => _err;

  @override
  set lastError(String value) => _err = value;

  @override
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchRelateGoods(
    Track track,
  ) async {
    return null;
  }

  @override
  Future<ResolvedAudio?> resolveUrlWithFallback(
    Track track, {
    required List<String> qualityCandidates,
    String? ppageId,
  }) async {
    resolveCalls += 1;
    final g = gate;
    if (g != null) await g;
    final resolved = nextResolved;
    if (resolved == null) {
      lastError = errorText;
      return null;
    }
    lastError = '';
    return resolved;
  }
}
