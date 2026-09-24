import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/search_result.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';

/// 测试用离线音源：实现基类 + 常用能力，不碰网络。
class FakeMusicSource
    implements
        MusicSource,
        QualityCatalogSource,
        PersonalFmSource,
        DailyRecommendSource,
        SearchHotSource {
  FakeMusicSource({this.platform = MusicPlatform.kugou});

  @override
  final MusicPlatform platform;

  final List<String> requestedLyricKeys = [];
  final List<String> requestedPlayKeys = [];

  /// `identityKey` → 歌词行。
  final Map<String, List<LyricLine>> lyricsByKey = {};

  PlayUrlResult? nextPlayUrl = const PlayUrlResult(
    url: 'https://example.com/fake.mp3',
    headers: {'Referer': 'https://example.com'},
  );

  /// 非空时 resolve 抛出该错误。
  Object? playError;

  /// 播放 resolve 闸门（竞态测试）。
  Future<void>? playGate;

  /// 歌词 fetch 闸门。
  Future<void>? lyricGate;

  ({List<RelateGood> goods, bool catalogComplete})? qualityCatalog;

  List<Track> fmTracks = const [];
  List<Track> dailyTracks = const [];

  int resolveCalls = 0;

  String keyOf(Track t) => t.identityKey;

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      const SearchPageResult.empty();

  @override
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  }) async {
    resolveCalls += 1;
    requestedPlayKeys.add(keyOf(track));
    final g = playGate;
    if (g != null) await g;
    final err = playError;
    if (err != null) throw err;
    final url = nextPlayUrl;
    if (url == null) {
      throw const UpstreamChanged('fake play fail');
    }
    return url;
  }

  @override
  Future<LyricPayload> fetchLyric(Track track) async {
    final key = keyOf(track);
    requestedLyricKeys.add(key);
    final g = lyricGate;
    if (g != null) await g;
    final lines = lyricsByKey[key] ?? const <LyricLine>[];
    return LyricPayload(lines: lines, sourceTag: 'fake');
  }

  @override
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchQualityCatalog(
    Track track,
  ) async {
    return qualityCatalog;
  }

  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async => fmTracks;

  @override
  Future<void> reportFmFeedback(
    Track track, {
    required FmFeedback feedback,
  }) async {}

  @override
  Future<List<Track>> dailyRecommendedSongs() async => dailyTracks;

  @override
  Future<List<String>> hotKeywords({int count = 20}) async => const [];
}

/// 测试引导：把 [FakeMusicSource] 装进全局 registry。
FakeMusicSource bootstrapFakeMusicSources({
  MusicPlatform platform = MusicPlatform.kugou,
}) {
  final source = FakeMusicSource(platform: platform);
  musicSourceRegistry = MusicSourceRegistry([source]);
  return source;
}
