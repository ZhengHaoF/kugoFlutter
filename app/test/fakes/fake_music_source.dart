import 'dart:async';

import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/daily_recommend.dart';
import 'package:kugo/core/models/fm_mode.dart';
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
  DailyRecommendResult dailyResult = const DailyRecommendResult(tracks: []);

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
  Future<DailyRecommendResult> dailyRecommend() async => dailyResult;

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

/// 脚本化私人 FM 源：关键词检索 + 真接口两条路径都可控，并记录调用。
///
/// 实现 [HeartRadioSource] 即「带档位轴」的源（酷狗语义）：控制器在未登录时
/// 会直接走关键词兜底、不请求 FM 接口；不实现它（网易语义）则必须请求才知道
/// 「需要登录」。两条路径各由一个测试覆盖。
class ScriptedFmSource extends FakeMusicSource implements HeartRadioSource {
  ScriptedFmSource({
    super.platform,
    this.perKeyword = 4,
    this.durations = const [],
    this.serverTracks = const [],
    this.serverFailure,
  });

  /// 每个关键词返回的曲目数（关键词池）。
  final int perKeyword;

  /// 返回曲目的时长轮转表；空 = 统一 10 秒。
  final List<int> durations;

  /// 真接口返回的曲目（一次一批，模拟酷狗）。
  final List<Track> serverTracks;

  /// 非空时 `nextFmTracks` 抛出它。
  final SourceFailure? serverFailure;

  /// 关键词检索闸门：非 null 时一直挂着（验证入口不等取歌）。
  Completer<void>? gate;

  final List<String> searchCalls = [];
  final Map<String, int> _round = {};

  int fetchCalls = 0;
  final List<int> remainSongcnts = [];

  FmMode? lastMode;
  FmSongPool? lastPool;

  final List<FmFeedback> feedbacks = [];

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    searchCalls.add(keyword);
    final g = gate;
    if (g != null) await g.future;
    final round = (_round[keyword] ?? 0) + 1;
    _round[keyword] = round;
    return SearchPageResult(
      items: List.generate(
        perKeyword,
        (i) => Track(
          id: '$keyword-$round-$i',
          name: '$keyword-$round-$i',
          artist: 'artist',
          album: 'album',
          coverUrl: 'http://cover/$keyword',
          durationMs:
              durations.isEmpty ? 10000 : durations[i % durations.length],
        ),
      ),
    );
  }

  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async {
    fetchCalls++;
    remainSongcnts.add(remain);
    final f = serverFailure;
    if (f != null) throw f;
    return serverTracks;
  }

  @override
  Future<void> setHeartMode({FmMode? mode, FmSongPool? pool}) async {
    lastMode = mode ?? lastMode;
    lastPool = pool ?? lastPool;
  }

  @override
  Future<void> reportFmFeedback(
    Track track, {
    required FmFeedback feedback,
  }) async {
    feedbacks.add(feedback);
  }
}
