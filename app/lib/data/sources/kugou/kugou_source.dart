import '../../../core/models/audio_quality.dart';
import '../../../core/models/catalog_models.dart';
import '../../../core/models/comment.dart';
import '../../../core/models/daily_recommend.dart';
import '../../../core/models/fm_mode.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../../../core/source/capabilities.dart';
import '../../../core/source/music_platform.dart';
import '../../../core/source/music_source.dart';
import '../../../core/source/quality_map.dart';
import '../../../data/repositories/catalog_repository.dart' as catalog;
import '../../../data/repositories/comment_repository.dart' as comment;
import '../../../data/repositories/discovery_repository.dart' as discovery;
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
        PlaylistCatalogSource,
        NewSongFeedSource,
        NewAlbumFeedSource,
        ArtistListSource,
        RecommendFeedSource,
        SearchHotSource,
        PlaylistDetailSource,
        AlbumDetailSource,
        ArtistDetailSource,
        CommentReadSource,
        CommentWriteSource {
  KugouSource({
    play.PlayRepository? playRepository,
    lyric.LyricRepository? lyricRepository,
    search.SearchRepository? searchRepository,
    fm.FmRepository? fmRepository,
    user.UserRepository? userRepository,
    rec.RecommendRepository? recommendRepository,
    playlist.PlaylistRepository? playlistRepository,
    catalog.CatalogRepository? catalogRepository,
    discovery.DiscoveryRepository? discoveryRepository,
    comment.CommentRepository? commentRepository,
  }) : _play = playRepository ?? play.playRepository,
       _lyric = lyricRepository ?? lyric.lyricRepository,
       _search = searchRepository ?? search.searchRepository,
       _fm = fmRepository ?? fm.fmRepository,
       _users = userRepository ?? user.userRepository,
       _rec = recommendRepository ?? rec.recommendRepository,
       _playlists = playlistRepository ?? playlist.playlistRepository,
       _catalog = catalogRepository ?? catalog.catalogRepository,
       _discovery = discoveryRepository ?? discovery.discoveryRepository,
       _comments = commentRepository ?? comment.commentRepository;

  final play.PlayRepository _play;
  final lyric.LyricRepository _lyric;
  final search.SearchRepository _search;
  final fm.FmRepository _fm;
  final user.UserRepository _users;
  final rec.RecommendRepository _rec;
  final playlist.PlaylistRepository _playlists;
  final catalog.CatalogRepository _catalog;
  final discovery.DiscoveryRepository _discovery;
  final comment.CommentRepository _comments;

  FmMode _fmMode = FmMode.heart;
  FmSongPool _fmPool = FmSongPool.taste;

  @override
  MusicPlatform get platform => MusicPlatform.kugou;

  // ── 详情（歌单/专辑/歌手，路由 `?src=` 按源分发到此） ────────

  @override
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylistDetail(
    String id,
  ) => _playlists.fetchPlaylist(id);

  @override
  Future<AlbumDetail?> fetchAlbumDetail(String albumId) =>
      _catalog.fetchAlbum(albumId);

  @override
  Future<ArtistDetail?> fetchArtistDetail(String artistId) =>
      _catalog.fetchArtist(artistId);

  @override
  Future<ArtistSongsPage> fetchArtistSongsPage(
    String artistId, {
    int page = 1,
    int pageSize = 30,
    ArtistSongSort sort = ArtistSongSort.hot,
  }) => _catalog.fetchArtistSongs(
    artistId,
    page: page,
    pageSize: pageSize,
    sort: sort,
  );

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

  // ── 评论（读侧） ────────────────────────────────────────

  @override
  String get lastError => _comments.lastError;

  @override
  Future<CommentPage> songComments(
    String mixSongId, {
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  }) => _comments.fetchSongComments(
    mixSongId: mixSongId,
    page: page,
    pageSize: pageSize,
    sort: sort,
  );

  @override
  Future<List<Comment>> floorReplies({
    required String childrenId,
    required String rootCommentId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 20,
  }) => _comments.fetchFloorReplies(
    childrenId: childrenId,
    rootCommentId: rootCommentId,
    mixSongId: mixSongId,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<int?> commentCount(String hash) =>
      _comments.fetchCommentCount(hash: hash);

  @override
  Future<CommentPage> classifyComments(
    String mixSongId, {
    required String typeId,
    int page = 1,
    int pageSize = 20,
  }) => _comments.fetchClassifyComments(
    mixSongId: mixSongId,
    typeId: typeId,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<CommentPage> hotwordComments(
    String mixSongId, {
    required String hotWord,
    int page = 1,
    int pageSize = 20,
  }) => _comments.fetchHotwordComments(
    mixSongId: mixSongId,
    hotWord: hotWord,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<List<Comment>> featuredComments({
    required String childrenId,
    String mixSongId = '',
    int page = 1,
    int pageSize = 10,
  }) => _comments.fetchFeaturedComments(
    childrenId: childrenId,
    mixSongId: mixSongId,
    page: page,
    pageSize: pageSize,
  );

  @override
  Future<void> sendSongComment({
    required String childrenId,
    required String content,
    String songName = '',
    String mixSongId = '',
  }) => _comments.sendSongComment(
    childrenId: childrenId,
    content: content,
    songName: songName,
    mixSongId: mixSongId,
  );

  @override
  Future<void> sendFloorReply({
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
    String songName = '',
    String mixSongId = '',
  }) => _comments.sendFloorReply(
    childrenId: childrenId,
    rootCommentId: rootCommentId,
    content: content,
    replyToUser: replyToUser,
    replyToContent: replyToContent,
    songName: songName,
    mixSongId: mixSongId,
  );

  @override
  Future<DailyRecommendResult> dailyRecommend() => _rec.fetchDaily();

  @override
  Future<List<PlaylistBrief>> rankBoards() => _playlists.fetchRankList();

  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async {
    final detail = await _playlists.fetchRankDetail(boardId, page: page);
    return detail?.tracks ?? const [];
  }

  // ── PlaylistCatalogSource（探索发现「歌单」Tab） ───────────

  /// 二级 group 原样返回；分类接口失败时退回推荐分类，保证「歌单」Tab 仍可用。
  @override
  Future<List<PlaylistTagGroup>> playlistTagGroups() async {
    final tags = await _discovery.fetchPlaylistTags();
    if (tags.items.isNotEmpty) return tags.items;
    return [
      PlaylistTagGroup(
        name: '推荐',
        child: [
          for (final c in rec.RecommendRepository.recommendPlaylistCategories)
            PlaylistTag(id: c.id, name: c.label, group: '推荐'),
        ],
      ),
    ];
  }

  /// 复用 `special_recommend`（`categoryid`）；空串回退「推荐」（id=0）。
  @override
  Future<List<PlaylistBrief>> categoryPlaylists({
    required String cat,
    int pageSize = 30,
  }) async {
    final c = cat.trim();
    final result = await _rec.fetchRecommendPlaylists(
      categoryId: c.isEmpty ? '0' : c,
      pageSize: pageSize,
    );
    if (result.playlists.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    return result.playlists;
  }

  // ── NewSongFeedSource（探索发现「新歌速递」Tab） ───────────

  @override
  Future<List<Track>> newSongs({int pageSize = 30}) async {
    final result = await _discovery.fetchNewSongs(pageSize: pageSize);
    if (result.items.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    return result.items;
  }

  // ── NewAlbumFeedSource（探索发现「新碟上架」Tab） ──────────

  /// 酷狗 `/top/album` 的地区分片（`chn/eur/jpn/kor`）。
  @override
  List<({String id, String label})> get albumRegions =>
      discovery.DiscoveryRepository.albumTypes;

  @override
  Future<List<AlbumBrief>> newAlbums({
    required String region,
    int pageSize = 30,
  }) async {
    final result = await _discovery.fetchNewAlbums(
      type: region,
      pageSize: pageSize,
    );
    if (result.items.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    return result.items;
  }

  // ── ArtistListSource（探索发现「歌手」Tab） ────────────────

  /// 上次 `singer/list` 的原始结果。
  ///
  /// 酷狗接口没有字母入参：字母是**响应自带的分组标题**（`热门`/`A`/`B`…），
  /// 故 [_artistCache] 既供字母分片取值，也供本地按字母过滤。
  List<discovery.DiscoveryArtist> _artistCache = const [];

  @override
  List<({String id, String label})> get artistGenderOptions =>
      discovery.DiscoveryRepository.artistSexTypes;

  @override
  List<({String id, String label})> get artistStyleOptions =>
      discovery.DiscoveryRepository.artistTypes;

  /// 字母分片来自上次响应（首次渲染时为空 → UI 隐藏该行，取数后出现）。
  @override
  List<({String id, String label})> get artistInitialOptions {
    final letters = <String>[
      for (final a in _artistCache)
        if (a.letter.isNotEmpty) a.letter,
    ];
    if (letters.isEmpty) return const [];
    final seen = <String>{};
    return [
      (id: '', label: '全部'),
      for (final l in letters)
        if (seen.add(l)) (id: l, label: l),
    ];
  }

  @override
  Future<List<ArtistBrief>> artistList({
    required String gender,
    required String style,
    required String initial,
    int pageSize = 30,
  }) async {
    final parts = style.split(':');
    final result = await _discovery.fetchArtists(
      sextype: int.tryParse(gender) ?? 0,
      type: int.tryParse(parts.first) ?? 0,
      musician: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      hotsize: pageSize,
    );
    if (result.items.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    _artistCache = result.items;
    final picked = initial.isEmpty
        ? result.items
        : result.items.where((a) => a.letter == initial).toList();
    // 字母是响应自带分组：切性别/流派后旧字母可能整个消失，此时按「不筛」处理
    // （页面取数后会把 chips 回退到首项），否则会闪一下空列表。
    final shown = picked.isEmpty && initial.isNotEmpty ? result.items : picked;
    return [
      for (final a in shown)
        ArtistBrief(
          id: a.id,
          name: a.name,
          avatarUrl: a.avatarUrl,
          songCount: a.songCount,
          fansCount: a.fansCount,
          platform: MusicPlatform.kugou,
        ),
    ];
  }

  // ── RecommendFeedSource（推荐歌单 / 编辑精选） ─────────────

  /// 复用 `special_recommend`（`categoryid`；空串 = 推荐 id 0）。
  @override
  Future<List<PlaylistBrief>> recommendPlaylists({
    String cat = '',
    int pageSize = 12,
  }) async {
    final c = cat.trim();
    final result = await _rec.fetchRecommendPlaylists(
      categoryId: c.isEmpty ? '0' : c,
      pageSize: pageSize,
    );
    if (result.playlists.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    return result.playlists;
  }

  /// 复用 `musicadservice/top_ip`（编辑精选）。
  @override
  Future<List<PlaylistBrief>> editorialPlaylists({int pageSize = 12}) async {
    final result = await _rec.fetchEditorialPicks(limit: pageSize);
    if (result.playlists.isEmpty && result.error.isNotEmpty) {
      throw NetworkFailure(result.error, filtered: result.error.contains('拦截'));
    }
    return result.playlists;
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
  if (msg.contains('URL过滤') || msg.contains('网络网关') || msg.contains('网络请求失败')) {
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
