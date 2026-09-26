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

  // ── 评论（Track → 酷狗 id 的翻译都在这里，UI 不参与） ──────

  /// mixsongid 解析缓存：key = [Track.identityKey]。
  ///
  /// 酷狗评论族要的是 `album_audio_id`，而队列 / 历史里的老数据存的是 `audio_id`
  /// （拿它查评论会得到空），所以拿到 track 后可能要回搜一次。解析结果缓存下来，
  /// 翻页 / 楼层 / 写侧都不必重搜。
  final Map<String, String> _mixSongIdCache = {};

  /// 能力面自己的失败文案（如「定位不到歌曲」）；空则透传 repository 的。
  String _commentError = '';

  /// 缓存上限。解析结果丢了可以重算，所以用最朴素的 FIFO 淘汰即可。
  static const int _mixSongIdCacheLimit = 64;

  @override
  String get lastError =>
      _commentError.isNotEmpty ? _commentError : _comments.lastError;

  @override
  Future<CommentPage> songComments(
    Track track, {
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  }) async {
    _commentError = '';
    final cached = _mixSongIdCache[track.identityKey] ?? '';
    if (cached.isNotEmpty) {
      return _comments.fetchSongComments(
        mixSongId: cached,
        page: page,
        pageSize: pageSize,
        sort: sort,
      );
    }
    // 没解析过 id 却要第 N 页：说明首屏没跑过（正常情况下不会），无可取。
    if (page > 1) return CommentPage.empty;

    // 首屏：逐个候选试。酷狗没有「按 track 直查评论」的路径，只能这样。
    //
    // **空列表也要继续试下一个候选**：候选里既有「同名翻唱确实没评论」，也有
    // 「id 形态不对（老数据的 audio_id）」，只有全试完才敢说这首歌没评论。
    final candidates = await _mixSongIdCandidates(track);
    if (candidates.isEmpty) {
      _commentError = '无法定位该歌曲（缺少歌曲 ID / 歌名）';
      return CommentPage.empty;
    }

    var emptyResult = CommentPage.empty;
    String? firstUsableId;
    for (final id in candidates) {
      final result = await _comments.fetchSongComments(
        mixSongId: id,
        page: page,
        pageSize: pageSize,
        sort: sort,
      );
      if (result.items.isNotEmpty) {
        _rememberMixSongId(track, id);
        return result;
      }
      if (_comments.lastError.isEmpty) {
        // 接口成功却无数据 → 这个 id 至少是「能被服务端接受」的，记作兜底缓存，
        // 免得下次刷新又把候选全试一遍。
        firstUsableId ??= id;
        if (emptyResult.items.isEmpty && result.childrenId.isNotEmpty) {
          emptyResult = result;
        }
      }
    }
    if (firstUsableId != null) _rememberMixSongId(track, firstUsableId);
    return emptyResult;
  }

  @override
  Future<List<Comment>> floorReplies({
    required Track track,
    required String childrenId,
    required String rootCommentId,
    int page = 1,
    int pageSize = 20,
  }) async {
    _commentError = '';
    return _comments.fetchFloorReplies(
      childrenId: childrenId,
      rootCommentId: rootCommentId,
      mixSongId: _mixSongIdOf(track),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<int?> commentCount(Track track) =>
      _comments.fetchCommentCount(hash: track.hash);

  @override
  Future<CommentPage> classifyComments(
    Track track, {
    required String typeId,
    int page = 1,
    int pageSize = 20,
  }) async {
    _commentError = '';
    return _comments.fetchClassifyComments(
      mixSongId: _mixSongIdOf(track),
      typeId: typeId,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<CommentPage> hotwordComments(
    Track track, {
    required String hotWord,
    int page = 1,
    int pageSize = 20,
  }) async {
    _commentError = '';
    return _comments.fetchHotwordComments(
      mixSongId: _mixSongIdOf(track),
      hotWord: hotWord,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<Comment>> featuredComments({
    required Track track,
    required String childrenId,
    int page = 1,
    int pageSize = 10,
  }) async {
    _commentError = '';
    return _comments.fetchFeaturedComments(
      childrenId: childrenId,
      mixSongId: _mixSongIdOf(track),
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<void> sendSongComment({
    required Track track,
    required String childrenId,
    required String content,
  }) {
    _commentError = '';
    return _comments.sendSongComment(
      childrenId: childrenId,
      content: content,
      songName: track.name.trim(),
      mixSongId: _mixSongIdOf(track),
    );
  }

  @override
  Future<void> sendFloorReply({
    required Track track,
    required String childrenId,
    required String rootCommentId,
    required String content,
    String replyToUser = '',
    String replyToContent = '',
  }) {
    _commentError = '';
    return _comments.sendFloorReply(
      childrenId: childrenId,
      rootCommentId: rootCommentId,
      content: content,
      replyToUser: replyToUser,
      replyToContent: replyToContent,
      songName: track.name.trim(),
      mixSongId: _mixSongIdOf(track),
    );
  }

  /// 已知的 mixsongid：优先用解析缓存，退回 track 自带字段。
  ///
  /// 分类 / 热词 / 楼层 / 写口的前置都是「列表已加载」，所以缓存通常已命中；
  /// 真取不到时交给 repository 报「缺少歌曲 ID」，不在这里编一个。
  String _mixSongIdOf(Track track) =>
      _mixSongIdCache[track.identityKey] ?? track.mixSongId.trim();

  void _rememberMixSongId(Track track, String mixSongId) {
    final key = track.identityKey;
    if (key.isEmpty || mixSongId.isEmpty) return;
    if (_mixSongIdCache.length >= _mixSongIdCacheLimit) {
      _mixSongIdCache.remove(_mixSongIdCache.keys.first);
    }
    _mixSongIdCache[key] = mixSongId;
  }

  /// 解析该曲在酷狗评论侧的 `mixsongid`（= `album_audio_id`）候选。
  ///
  /// 顺序与旧 UI 版一致：**先回搜**（老数据里的 mixSongId 字段可能是 `audio_id`，
  /// 搜索结果才可靠），再退回 track 自带字段。hash 形态（≥32 位 hex）不是合法
  /// mixsongid，直接排除。
  Future<List<String>> _mixSongIdCandidates(Track track) async {
    final out = <String>[];
    void add(String? v) {
      if (v == null) return;
      final s = v.trim();
      if (s.isEmpty || s == '0' || s.toLowerCase() == 'null') return;
      if (s.length >= 32 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return;
      if (!out.contains(s)) out.add(s);
    }

    final name = track.name.trim();
    final artist = track.artist.trim();
    final hash = track.hash.trim().toLowerCase();

    Future<void> searchOnce(String keyword) async {
      if (keyword.isEmpty) return;
      try {
        final hits = await _search.searchSongs(keyword, pageSize: 10);
        Track? byHash;
        Track? byNameArtist;
        Track? byName;
        for (final t in hits) {
          if (hash.isNotEmpty &&
              t.hash.isNotEmpty &&
              t.hash.toLowerCase() == hash) {
            byHash = t;
            break;
          }
        }
        for (final t in hits) {
          final nOk = name.isEmpty || t.name == name;
          final aOk =
              artist.isEmpty ||
              t.artist.contains(artist) ||
              artist.contains(t.artist);
          if (nOk && aOk) {
            byNameArtist = t;
            break;
          }
        }
        for (final t in hits) {
          if (name.isNotEmpty && t.name == name) {
            byName = t;
            break;
          }
        }
        final match =
            byHash ??
            byNameArtist ??
            byName ??
            (hits.isNotEmpty ? hits.first : null);
        if (match != null) add(match.mixSongId);
        // 同名其他版本（翻唱 / Live）也一并作为候选。
        for (final t in hits) {
          if (name.isNotEmpty && t.name.startsWith(name)) add(t.mixSongId);
        }
      } catch (_) {
        // 搜索失败不是致命错误：后面还有 track 自带字段兜底。
      }
    }

    await searchOnce(
      [
        if (name.isNotEmpty) name,
        if (artist.isNotEmpty) artist,
      ].join(' ').trim(),
    );
    if (out.isEmpty) await searchOnce(name);
    if (out.isEmpty && hash.isNotEmpty) await searchOnce(hash);

    add(track.mixSongId);
    add(track.id);
    return out;
  }

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
