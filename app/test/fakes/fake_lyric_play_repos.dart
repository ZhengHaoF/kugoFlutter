import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';

import 'fake_music_source.dart';

/// Compatibility shims for tests still on the old names.
class FakeLyricRepository {
  final FakeMusicSource _inner = FakeMusicSource();

  List<String> get requestedKeys => _inner.requestedLyricKeys;

  /// Tests assign `byKey[...] = lines`; mirror into [FakeMusicSource.lyricsByKey].
  late final Map<String, List<LyricLine>> byKey = _inner.lyricsByKey;

  set gate(Future<void>? g) => _inner.lyricGate = g;

  bool Function(Track track)? onFetch;

  Future<List<LyricLine>> fetchLyrics(Track track) async {
    final payload = await _inner.fetchLyric(track);
    return payload.lines;
  }
}

class FakePlayRepository {
  final FakeMusicSource _inner = FakeMusicSource();

  set nextResolved(ResolvedAudio? value) {
    if (value == null) {
      _inner.nextPlayUrl = null;
      _inner.playError = const UpstreamChanged('fake play fail');
    } else {
      _inner.playError = null;
      _inner.nextPlayUrl = PlayUrlResult(
        url: value.url,
        backupUrls: value.backupUrls,
        grantedQuality: value.qualityEnum,
      );
    }
  }

  set errorText(String value) => _inner.playError = UpstreamChanged(value);

  String get lastError => '';
  set lastError(String _) {}

  int get resolveCalls => _inner.resolveCalls;

  set gate(Future<void>? g) => _inner.playGate = g;

  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchRelateGoods(
    Track track,
  ) =>
      _inner.fetchQualityCatalog(track);

  Future<ResolvedAudio?> resolveUrlWithFallback(
    Track track, {
    required List<String> qualityCandidates,
    String? ppageId,
  }) async {
    try {
      final result = await _inner.resolvePlayUrl(track);
      return ResolvedAudio(
        url: result.url,
        backupUrls: result.backupUrls,
        quality: result.grantedQuality?.param ?? '128',
      );
    } catch (_) {
      return null;
    }
  }
}
