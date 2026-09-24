import '../../../core/models/audio_quality.dart';
import '../../../core/models/fm_mode.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../../../core/source/capabilities.dart';
import '../../../core/source/music_platform.dart';
import '../../../core/source/music_source.dart';
import '../../../core/source/quality_map.dart';
import '../../../data/repositories/fm_repository.dart' as fm;
import '../../../data/repositories/lyric_repository.dart' as lyric;
import '../../../data/repositories/play_repository.dart' as play;
import '../../../data/repositories/playlist_repository.dart' as playlist;
import '../../../data/repositories/recommend_repository.dart' as rec;
import '../../../data/repositories/search_repository.dart' as search;
import '../../../data/repositories/user_repository.dart' as user;
import 'kugou_session.dart';

/// 酷狗音源适配器：把现有 Repository 收成 [MusicSource] 能力面。
/// UI / Player 只依赖本类与 `core/source` 契约，不直接碰 `PlayRepository` 等。
class KugouSource
    implements
        MusicSource,
        PersonalFmSource,
        HeartRadioSource,
        UserPlaylistWriteSource,
        QualityCatalogSource,
        DailyRecommendSource,
        RankSource,
        SearchHotSource {
  KugouSource({
    play.PlayRepository? playRepository,
    lyric.LyricRepository? lyricRepository,
    search.SearchRepository? searchRepository,
    fm.FmRepository? fmRepository,
    user.UserRepository? userRepository,
    rec.RecommendRepository? recommendRepository,
    playlist.PlaylistRepository? playlistRepository,
  })  : _play = playRepository ?? play.playRepository,
        _lyric = lyricRepository ?? lyric.lyricRepository,
        _search = searchRepository ?? search.searchRepository,
        _fm = fmRepository ?? fm.fmRepository,
        _users = userRepository ?? user.userRepository,
        _rec = recommendRepository ?? rec.recommendRepository,
        _playlists = playlistRepository ?? playlist.playlistRepository;

  final play.PlayRepository _play;
  final lyric.LyricRepository _lyric;
  final search.SearchRepository _search;
  final fm.FmRepository _fm;
  final user.UserRepository _users;
  final rec.RecommendRepository _rec;
  final playlist.PlaylistRepository _playlists;

  FmMode _fmMode = FmMode.heart;
  FmSongPool _fmPool = FmSongPool.taste;

  @override
  MusicPlatform get platform => MusicPlatform.kugou;

  /// 酷狗防盗链头；由 [resolvePlayUrl] 下发给播放引擎。
  static const Map<String, String> playbackHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'http://www.kugou.com/',
  };

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _search.searchSongsPage(keyword, page: page, pageSize: pageSize);
  }

  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _search.searchPlaylists(keyword, page: page, pageSize: pageSize);
  }

  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _search.searchAlbums(keyword, page: page, pageSize: pageSize);
  }

  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) {
    return _search.searchArtists(keyword, page: page, pageSize: pageSize);
  }

  @override
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  }) async {
    final quality = preferred ?? AppQuality.sq;
    final candidates = SourceQualityMap.kugouCandidates(quality);
    final resolved = await _play.resolveUrlWithFallback(
      track,
      qualityCandidates: candidates,
    );
    if (resolved == null) {
      throw mapKugouFailure(_play.lastError);
    }
    return PlayUrlResult(
      url: resolved.url,
      backupUrls: resolved.backupUrls,
      headers: playbackHeaders,
      grantedQuality: resolved.qualityEnum,
      isPreviewClip: false,
    );
  }

  @override
  Future<LyricPayload> fetchLyric(Track track) async {
    final lines = await _lyric.fetchLyrics(track);
    return LyricPayload(lines: lines, sourceTag: 'kugou-krc');
  }

  @override
  Future<({List<RelateGood> goods, bool catalogComplete})?> fetchQualityCatalog(
    Track track,
  ) {
    return _play.fetchRelateGoods(track);
  }

  @override
  Future<List<Track>> dailyRecommendedSongs() async {
    final result = await _rec.fetchDaily();
    return result.tracks;
  }

  @override
  Future<List<({String id, String name, String coverUrl})>> rankBoards() async {
    final boards = await _playlists.fetchRankList();
    return [
      for (final b in boards)
        (id: b.id, name: b.name, coverUrl: b.coverUrl),
    ];
  }

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async {
    final detail = await _playlists.fetchRankDetail(boardId, page: page);
    return detail?.tracks ?? const [];
  }

  @override
  Future<List<String>> hotKeywords({int count = 20}) {
    return _search.hotKeywords(count: count);
  }

  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async {
    // 上游：remain_songcnt > 4 时服务端只回元数据，取歌需 0–4。
    final remainClamped = remain.clamp(0, 4);
    final page = await _fm.fetch(
      mode: _fmMode,
      pool: _fmPool,
      remainSongcnt: remainClamped,
    );
    return page.tracks;
  }

  @override
  Future<void> reportFmFeedback(
    Track track, {
    required FmFeedback feedback,
  }) async {
    switch (feedback) {
      case FmFeedback.trash:
        await _fm.reportGarbage(track: track, mode: _fmMode, pool: _fmPool);
      case FmFeedback.like:
      case FmFeedback.skip:
        await _fm.reportPlay(
          track: track,
          playtime: 0,
          mode: _fmMode,
          pool: _fmPool,
        );
    }
  }

  @override
  Future<void> setHeartMode({FmMode? mode, FmSongPool? pool}) async {
    if (mode != null) _fmMode = mode;
    if (pool != null) _fmPool = pool;
  }

  @override
  Future<void> addPlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  }) async {
    final auth = kugouSession;
    for (final t in tracks) {
      final result = await _users.addPlaylistTrack(
        listId: playlistId,
        userId: auth.userId,
        token: auth.token,
        name: t.name,
        hash: t.hash,
        albumId: t.albumId,
        mixSongId: t.mixSongId.isNotEmpty ? t.mixSongId : t.id,
      );
      if (!result.ok) {
        throw mapKugouFailure(result.error);
      }
    }
  }

  @override
  Future<void> removePlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  }) async {
    final auth = kugouSession;
    final fileIds = [
      for (final t in tracks)
        if (t.mixSongId.isNotEmpty) t.mixSongId else t.id,
    ];
    if (fileIds.isEmpty) return;
    final result = await _users.deletePlaylistTracks(
      listId: playlistId,
      userId: auth.userId,
      token: auth.token,
      fileIds: fileIds,
    );
    if (!result.ok) {
      throw mapKugouFailure(result.error);
    }
  }
}

/// 酷狗业务失败文案 → [SourceFailure]（无结构化码时按文案启发式）。
SourceFailure mapKugouFailure(String message) {
  final msg = message.trim();
  if (msg.isEmpty) return const UpstreamChanged('无法获取播放地址');
  if (msg.contains('20028') ||
      msg.contains('安全验证') ||
      msg.contains('SSA') ||
      msg.contains('未登录')) {
    return LoginRequired(msg);
  }
  if (msg.contains('20006') ||
      msg.contains('VIP') ||
      msg.contains('版权') ||
      msg.contains('无权限')) {
    return NoPermission(msg);
  }
  if (msg.contains('URL过滤') ||
      msg.contains('网络网关') ||
      msg.contains('网络请求失败')) {
    return NetworkFailure(
      msg,
      filtered: msg.contains('过滤') || msg.contains('网关'),
    );
  }
  if (msg.contains('缺少 hash') || msg.contains('未找到')) {
    return NotFound(msg);
  }
  return UpstreamChanged(msg);
}

/// 默认酷狗音源实例。
final kugouSource = KugouSource();
