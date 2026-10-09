import '../../../core/api/netease/netease_account_models.dart';
import '../../../core/api/netease/netease_account_source.dart';
import '../../../core/api/netease/netease_client.dart';
import '../../../core/api/netease/netease_failures.dart';
import '../../../core/api/netease/netease_mappers.dart';
import '../../../core/models/audio_quality.dart';
import '../../../core/models/catalog_models.dart';
import '../../../core/models/cloud_models.dart';
import '../../../core/models/comment.dart';
import '../../../core/models/daily_recommend.dart';
import '../../../core/models/mv_models.dart';
import '../../../core/models/search_result.dart';
import '../../../core/models/track.dart';
import '../../../core/source/capabilities.dart';
import '../../../core/source/music_platform.dart';
import '../../../core/source/music_source.dart';
import '../../../core/source/quality_map.dart';

/// 网易云音源适配器：把 [NeteaseClient] 的原始响应收成 [MusicSource] 能力面。
///
/// 边界约定（多音源接入方案 §1.2）：加密 / Cookie / 字段差异只出现在
/// `core/api/netease` 与本类内，UI 只认统一模型与 [SourceFailure]。
class NeteaseSource
    implements
        MusicSource,
        DailyRecommendSource,
        RankSource,
        PlaylistCatalogSource,
        NewSongFeedSource,
        NewAlbumFeedSource,
        ArtistListSource,
        RecommendFeedSource,
        PersonalFmSource,
        PlaylistDetailSource,
        AlbumDetailSource,
        ArtistDetailSource,
        UserPlaylistWriteSource,
        UserLikedWriteSource,
        UserPlaylistReadSource,
        UserLibrarySource,
        DeviceLoginSource,
        CommentReadSource,
        CommentWriteSource,
        CommentLikeSource,
        ResourceCommentSource,
        SearchHotSource,
        MvDetailSource,
        NeteaseAccountSource,
        CloudDiskSource {
  NeteaseSource({NeteaseClient? client}) : _client = client ?? neteaseClient;

  final NeteaseClient _client;

  @override
  MusicPlatform get platform => MusicPlatform.netease;

  /// 榜单**精选白名单**（数组顺序即首页「排行榜」横排的优先级）。
  ///
  /// G11 `toplist/detail` 实测（2026-09-26）返回 **63 张**官方榜，其中大量是
  /// 活动/品牌/车友榜（音乐合伙人 ×5、车友榜 ×8、`星云榜VOL.31…`、`喜力®…`），
  /// 原样全铺噪音过大，故只取主流榜。`name` 仅在 G11 失败或该榜下架时作兜底显示名
  /// （正常以接口返回名为准）。
  static const List<({String id, String name})> boardWhitelist = [
    (id: '19723756', name: '飙升榜'),
    (id: '3779629', name: '新歌榜'),
    (id: '2884035', name: '原创榜'),
    (id: '3778678', name: '热歌榜'),
    (id: '991319590', name: '网易云中文说唱榜'),
    (id: '5059642708', name: '网易云国风榜'),
    (id: '5059661515', name: '网易云民谣榜'),
    (id: '5059633707', name: '网易云摇滚榜'),
    (id: '1978921795', name: '网易云电音榜'),
    (id: '71384707', name: '网易云古典榜'),
    (id: '71385702', name: '网易云ACG榜'),
    (id: '2809513713', name: '网易云欧美热歌榜'),
    (id: '2809577409', name: '网易云欧美新歌榜'),
    (id: '12225155968', name: '欧美R&B榜'),
    (id: '5059644681', name: '网易云日语榜'),
    (id: '745956260', name: '网易云韩语榜'),
    (id: '60198', name: '美国Billboard榜'),
    (id: '180106', name: 'UK排行榜周榜'),
    (id: '60131', name: '日本Oricon榜'),
    (id: '3812895', name: 'Beatport全球电子舞曲榜'),
  ];

  /// G11 结果缓存（**仅在命中白名单时**写入）。
  ///
  /// G11 一次返回 63 张榜（每条另带 `tracks`），体积不小；首页「排行榜」、
  /// `/ranks`、歌单详情页的「更换榜单」弹窗都会调 [rankBoards]，缓存一份避免重复拉。
  List<PlaylistBrief>? _boardsCache;

  /// 「我喜欢」详情单批 id 数：一次 `song/detail` 带 100 个 id（实测形态安全）。
  static const int _likedDetailBatch = 100;

  /// 当前登录 uid 缓存（[NeteaseClient.currentAccount] 一次请求换来的）。
  int? _cachedUid;

  // ── MusicSource ──────────────────────────────────────────

  @override
  Future<SearchPageResult<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final raw = await _search(keyword, page, pageSize, _NeteaseSearchKind.song);
    return mapNeteaseSearchSongs(raw);
  }

  @override
  Future<SearchPageResult<PlaylistBrief>> searchPlaylists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final raw =
        await _search(keyword, page, pageSize, _NeteaseSearchKind.playlist);
    return mapNeteaseSearchPlaylists(raw);
  }

  @override
  Future<SearchPageResult<AlbumBrief>> searchAlbums(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final raw =
        await _search(keyword, page, pageSize, _NeteaseSearchKind.album);
    return mapNeteaseSearchAlbums(raw);
  }

  @override
  Future<SearchPageResult<ArtistBrief>> searchArtists(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final raw =
        await _search(keyword, page, pageSize, _NeteaseSearchKind.artist);
    return mapNeteaseSearchArtists(raw);
  }

  /// A1c：四类共用一个端点，靠 `type` 区分（1/10/1000/100）。
  Future<String> _search(
    String keyword,
    int page,
    int pageSize,
    _NeteaseSearchKind kind,
  ) {
    return _client.searchRaw(
      keyword: keyword,
      limit: pageSize,
      offset: page <= 1 ? 0 : (page - 1) * pageSize,
      type: kind.wire,
    );
  }

  /// 单次请求即可：网易**服务端按权限下发最高可用档**，请求 `exhigh`/`lossless`
  /// 在游客态一律降级为 `standard`（实测），故不需要酷狗式候选降档循环。
  @override
  Future<PlayUrlResult> resolvePlayUrl(
    Track track, {
    AppQuality? preferred,
  }) async {
    // 云盘曲目走云盘取流（拿原始上传文件），不进曲库 player/url 链
    // （同酷狗口径，见 KugouSource.resolvePlayUrl 的 isCloudTrack 分支）。
    if (track.isCloudTrack) {
      return resolveCloudPlayUrl(track);
    }
    final songId = _songId(track);
    if (songId <= 0) throw const NotFound('曲目缺少网易云 songId');
    final raw = await _client.songPlayUrlRaw(
      songId,
      level: SourceQualityMap.neteaseLevel(preferred ?? AppQuality.sq),
    );
    return mapNeteasePlayUrl(raw);
  }

  @override
  Future<LyricPayload> fetchLyric(Track track) async {
    // 云盘歌词在文件 `LYRICS` 标签里，和曲库歌词口不是一套（J5）。
    if (track.isCloudTrack) return _fetchCloudLyric(track);
    final songId = _songId(track);
    if (songId <= 0) return LyricPayload.empty;
    final raw = await _client.songLyricRaw(songId);
    return mapNeteaseLyric(raw);
  }

  // ── CloudDiskSource（J 组，需登录） ─────────────────────────

  /// 网易的登录态看 `MUSIC_U` cookie（与 [isLoggedIn] 同源）。
  @override
  bool get isCloudDiskLoggedIn => _client.hasLogin;

  /// J1 云盘列表。
  ///
  /// `limit`/`offset` 是否生效待二轮探针确认，故 [CloudDiskPage.hasMore] 以响应
  /// 自带字段为准：limit 被忽略时首屏即返回全量、`hasMore=false`，两种形态都正确。
  @override
  Future<CloudDiskPage> fetchCloudDiskPage({
    int page = 1,
    int pageSize = 30,
  }) async {
    if (!_client.hasLogin) {
      throw const LoginRequired('请先登录网易云后查看云盘');
    }
    final offset = page > 1 ? (page - 1) * pageSize : 0;
    return mapNeteaseCloudPage(
      await _client.cloudDiskListRaw(limit: pageSize, offset: offset),
    );
  }

  /// J4 云盘取流：原始文件直链（平铺响应，见 [mapNeteaseCloudPlayUrl]）。
  @override
  Future<PlayUrlResult> resolveCloudPlayUrl(Track track) async {
    final songId = _songId(track);
    if (songId <= 0) throw const NotFound('云盘曲目缺少 songId');
    return mapNeteaseCloudPlayUrl(await _client.cloudDownloadRaw(songId));
  }

  /// J3 删除云盘文件。目标用 `cloudFileId`（列表项的 songId）。
  @override
  Future<void> deleteCloudTracks(List<CloudDeleteTarget> targets) async {
    final ids = <String>[];
    for (final t in targets) {
      final id = t.cloudFileId.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) throw const NotFound('云盘文件 id 缺失');
    if (!_client.hasLogin) {
      throw const LoginRequired('请先登录网易云后操作云盘');
    }
    throwIfNeteaseWriteFailed(
      await _client.cloudDiskDeleteRaw(ids),
      '云盘删除',
    );
  }

  /// J5 云盘歌词。uid 走 [currentAccount]（与歌单/我喜欢同源）并缓存——
  /// 云盘曲目逐首播放时不该每首都打一次 `account/get`。
  /// 取不到就返回空：没内嵌歌词的文件同样是空，UI 无需区分。
  Future<LyricPayload> _fetchCloudLyric(Track track) async {
    final songId = _songId(track);
    if (songId <= 0 || !_client.hasLogin) return LyricPayload.empty;
    final uid = await _uid();
    if (uid <= 0) return LyricPayload.empty;
    return mapNeteaseCloudLyric(
      await _client.cloudLyricRaw(uid: uid, songId: songId),
    );
  }

  /// 当前登录 uid（缓存；失败不缓存，下次再试）。
  Future<int> _uid() async {
    final cached = _cachedUid;
    if (cached != null && cached > 0) return cached;
    final account = await currentAccount();
    final uid = int.tryParse(account?.userId ?? '') ?? 0;
    if (uid > 0) _cachedUid = uid;
    return uid;
  }

  // ── DailyRecommendSource（G3） ────────────────────────────

  /// G3 游客态即可用（实测 24 曲）；G2「每日推荐歌单」才强制登录。
  ///
  /// 网易日推本身即个性化歌单，故 `personalized: true`、无需登录、无错误态。
  @override
  Future<DailyRecommendResult> dailyRecommend() async {
    final raw = await _client.dailyRecommendSongsRaw();
    return DailyRecommendResult(
      tracks: mapNeteaseDailySongs(raw),
      personalized: true,
    );
  }

  // ── 详情（D2/D3/D4/D6，路由 `?src=` 按源分发到此） ────────

  /// D2 歌单详情。网易榜单也是歌单（G10），榜单/歌单共用本口。
  ///
  /// [briefHint] 网易无用户歌单登录态路径，忽略；
  /// 榜单形态按 [preferRank] 回写 brief.isRank（与酷狗交叉 fallback 同口径）。
  /// 空曲目视为无数据（返回 null），与酷狗「空用户歌单」区分。
  @override
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylistDetail(
    String id, {
    PlaylistBrief? briefHint,
    bool preferRank = false,
  }) async {
    final pid = int.tryParse(id.trim()) ?? 0;
    if (pid <= 0) return null;
    final detail = mapNeteasePlaylistDetail(await _client.playlistDetailRaw(pid));
    if (detail == null || detail.tracks.isEmpty) return null;
    final brief =
        preferRank && !detail.brief.isRank
            ? detail.brief.copyWith(isRank: true)
            : detail.brief;
    return (brief: brief, tracks: detail.tracks);
  }

  /// D3 专辑详情：`album` 头 + `songs[]`。
  @override
  Future<AlbumDetail?> fetchAlbumDetail(String albumId) async {
    final aid = int.tryParse(albumId.trim()) ?? 0;
    if (aid <= 0) return null;
    return mapNeteaseAlbumDetail(await _client.albumDetailRaw(aid));
  }

  /// D4 歌手头部信息（歌曲数 musicSize / 专辑数 albumSize）。
  @override
  Future<ArtistDetail?> fetchArtistDetail(String artistId) async {
    final aid = int.tryParse(artistId.trim()) ?? 0;
    if (aid <= 0) return null;
    return mapNeteaseArtistDetail(await _client.artistDetailRaw(aid));
  }

  /// D6 歌手歌曲分页：`offset = (page-1)*pageSize`；`more` → hasMore。
  @override
  Future<ArtistSongsPage> fetchArtistSongsPage(
    String artistId, {
    int page = 1,
    int pageSize = 30,
    ArtistSongSort sort = ArtistSongSort.hot,
  }) async {
    final aid = int.tryParse(artistId.trim()) ?? 0;
    if (aid <= 0) return const ArtistSongsPage();
    final raw = await _client.artistSongsRaw(
      aid,
      order: sort == ArtistSongSort.newest ? 'new' : 'hot',
      offset: (page - 1) * pageSize,
      limit: pageSize,
    );
    return mapNeteaseArtistSongs(raw);
  }

  // ── RankSource（G11 榜单列表 / G10 曲目） ────────────────

  /// G11 一次拿全部官方榜元数据 → 按 [boardWhitelist] 顺序挑出主流榜。
  ///
  /// 失败或白名单一条都没命中（接口改版/风控）时**不重试、不抛错**，直接用
  /// 白名单内置名兜底（封面留空，由 UI 出占位图），保证榜单入口始终可用；
  /// 这种情况不写缓存，下次进页面会重新试。
  @override
  Future<List<PlaylistBrief>> rankBoards() async {
    final cached = _boardsCache;
    if (cached != null) return cached;
    List<({String id, String name, String coverUrl})> metas;
    try {
      metas = mapNeteaseToplistBoards(await _client.toplistDetailRaw());
    } catch (_) {
      metas = const [];
    }
    final boards = boardsFromWhitelist(metas);
    if (metas.isNotEmpty) _boardsCache = boards;
    return boards;
  }

  /// 白名单过滤 + 排序：只保留白名单内的榜，顺序以白名单为准。
  ///
  /// 纯函数（不碰网络），便于单测；[metas] 为空即「G11 不可用」的兜底分支。
  static List<PlaylistBrief> boardsFromWhitelist(
    List<({String id, String name, String coverUrl})> metas,
  ) {
    final byId = {for (final m in metas) m.id: m};
    final boards = <PlaylistBrief>[];
    for (final b in boardWhitelist) {
      final meta = byId[b.id];
      final name = meta?.name.trim() ?? '';
      boards.add(
        PlaylistBrief(
          id: b.id,
          name: name.isEmpty ? b.name : name,
          coverUrl: meta?.coverUrl ?? '',
          isRank: true,
          platform: MusicPlatform.netease,
          rankTypeName: '网易官方榜',
        ),
      );
    }
    return boards;
  }

  /// 复用歌单详情（G10）。歌单曲目**上限 1000 首**（实测），故 [page] 不生效。
  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async {
    final id = int.tryParse(boardId.trim()) ?? 0;
    if (id <= 0) throw const NotFound('榜单 id 无效');
    final raw = await _client.playlistDetailRaw(id);
    return mapNeteasePlaylistTracks(raw);
  }

  // ── PlaylistCatalogSource（G6 分类歌单 / G7b 标签） ────────

  /// 网易标签是**一级扁平**（无酷狗式二级 group），故拍成单组返回。
  @override
  Future<List<PlaylistTagGroup>> playlistTagGroups() async {
    return mapNeteasePlaylistTags(await _client.highQualityTagsRaw());
  }

  /// [cat] 即标签名（实测 `cat=华语`）；空串回退「全部」。
  @override
  Future<List<PlaylistBrief>> categoryPlaylists({
    required String cat,
    int pageSize = 30,
  }) async {
    final c = cat.trim();
    final raw = await _client.topPlaylistsRaw(
      cat: c.isEmpty ? '全部' : c,
      limit: pageSize,
    );
    return mapNeteaseTopPlaylists(raw);
  }

  // ── NewSongFeedSource（G5 推荐新歌） ─────────────────────

  /// 网易是「推荐新歌」口径：无地区分类，游客态也有数据。
  @override
  Future<List<Track>> newSongs({int pageSize = 30}) async {
    return mapNeteasePersonalizedNewSongs(
      await _client.personalizedNewSongsRaw(limit: pageSize),
    );
  }

  // ── NewAlbumFeedSource（G12 新碟上架） ───────────────────

  /// G12 地区分片：网易用 `ALL/ZH/EA/KR/JP`（与酷狗的 `all/chn/eur/jpn/kor` 同义，
  /// 顺序对齐为「全部 / 华语 / 欧美 / 日本 / 韩国」）。
  static const _albumRegions = <({String id, String label})>[
    (id: 'ALL', label: '全部'),
    (id: 'ZH', label: '华语'),
    (id: 'EA', label: '欧美'),
    (id: 'JP', label: '日本'),
    (id: 'KR', label: '韩国'),
  ];

  @override
  List<({String id, String label})> get albumRegions => _albumRegions;

  /// G12 明文即通（免登录，5 区实测 `code=200`、`total=500`），故不需要预热。
  @override
  Future<List<AlbumBrief>> newAlbums({
    required String region,
    int pageSize = 30,
  }) async {
    final r = region.trim();
    return mapNeteaseNewAlbums(
      await _client.albumNewRaw(
        area: r.isEmpty ? 'ALL' : r,
        limit: pageSize,
      ),
    );
  }

  // ── ArtistListSource（G13 歌手列表） ─────────────────────

  /// G13 性别分片＝`type`（-1 全部 / 1 男 / 2 女 / 3 组合），与酷狗 `sextypes` 同义。
  static const _artistGenders = <({String id, String label})>[
    (id: '-1', label: '全部'),
    (id: '1', label: '男'),
    (id: '2', label: '女'),
    (id: '3', label: '组合'),
  ];

  /// G13 第二分片＝`area`（网易是**地区**，酷狗那行是**流派**，故各行取值互不通用）。
  static const _artistAreas = <({String id, String label})>[
    (id: '-1', label: '全部'),
    (id: '7', label: '华语'),
    (id: '96', label: '欧美'),
    (id: '8', label: '日本'),
    (id: '16', label: '韩国'),
    (id: '0', label: '其他'),
  ];

  /// G13 首字母＝`initial`（须转大写 ASCII 码，见 [NeteaseClient.artistListParams]）。
  /// 空串 = 不筛；实测 `a`/`z` 均生效，其余字母同参数形态。
  static final _artistInitials = <({String id, String label})>[
    (id: '', label: '全部'),
    for (var c = 0x41; c <= 0x5A; c++)
      (id: String.fromCharCode(c), label: String.fromCharCode(c)),
  ];

  @override
  List<({String id, String label})> get artistGenderOptions => _artistGenders;

  @override
  List<({String id, String label})> get artistStyleOptions => _artistAreas;

  @override
  List<({String id, String label})> get artistInitialOptions => _artistInitials;

  /// G13 明文即通（免登录）；三个筛选全部生效（实测 2026-09-26）。
  @override
  Future<List<ArtistBrief>> artistList({
    required String gender,
    required String style,
    required String initial,
    int pageSize = 30,
  }) async {
    final t = gender.trim();
    final a = style.trim();
    return mapNeteaseArtistList(
      await _client.artistListRaw(
        type: t.isEmpty ? '-1' : t,
        area: a.isEmpty ? '-1' : a,
        initial: initial.trim(),
        limit: pageSize,
      ),
    );
  }

  // ── RecommendFeedSource（G1 个性推荐 / G7a 精品歌单） ──────

  /// G1 个性推荐歌单：`result[]`（游客态实测 5 单）。
  ///
  /// 网易个性推荐无分类维度，[cat] 忽略（分类歌单走 G6 / [categoryPlaylists]）。
  @override
  Future<List<PlaylistBrief>> recommendPlaylists({
    String cat = '',
    int pageSize = 12,
  }) async {
    return mapNeteaseTopPlaylists(
      await _client.personalizedPlaylistsRaw(limit: pageSize),
    );
  }

  /// G7a 精品歌单：`playlists[]`（与 G1 同节点形态，复用同一 mapper）。
  @override
  Future<List<PlaylistBrief>> editorialPlaylists({int pageSize = 12}) async {
    return mapNeteaseTopPlaylists(
      await _client.highQualityPlaylistsRaw(limit: pageSize),
    );
  }

  // ── PersonalFmSource（G4） ───────────────────────────────

  /// 网易 FM 是「一次一换」：每次 `radio/get` 返回下一批（通常 1 首）。
  /// [unplayed] / [fresh] 为跨源语义参数，网易协议不使用。
  @override
  Future<List<Track>> nextFmTracks({
    int unplayed = 0,
    bool fresh = false,
  }) async {
    final raw = await _client.personalFmRaw();
    return mapNeteaseFmSongs(raw);
  }

  @override
  Future<void> reportFmFeedback(
    Track track, {
    required FmFeedback feedback,
  }) async {
    switch (feedback) {
      case FmFeedback.like:
        final songId = _songId(track);
        if (songId <= 0) return;
        throwIfNeteaseWriteFailed(
          await _client.likeSongRaw(songId, like: true),
          'FM 喜欢',
        );
      case FmFeedback.skip:
      case FmFeedback.trash:
        // 网易 skip/trash 上报端点未实测（参考实现未覆盖），
        // 暂只做本地行为（队列跳过），不上报云端。
        break;
    }
  }

  // ── UserPlaylistWriteSource（F5，需登录） ─────────────────

  @override
  Future<void> addPlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  }) async {
    final pid = int.tryParse(playlistId.trim()) ?? 0;
    if (pid <= 0) throw const NotFound('歌单 id 无效');
    final songIds = _songIds(tracks);
    if (songIds.isEmpty) return;
    throwIfNeteaseWriteFailed(
      await _client.addSongsToPlaylistRaw(pid, songIds),
      '歌单加曲',
    );
  }

  @override
  Future<void> removePlaylistTracks({
    required String playlistId,
    required List<Track> tracks,
  }) async {
    final pid = int.tryParse(playlistId.trim()) ?? 0;
    if (pid <= 0) throw const NotFound('歌单 id 无效');
    final songIds = _songIds(tracks);
    if (songIds.isEmpty) return;
    throwIfNeteaseWriteFailed(
      await _client.removeSongsFromPlaylistRaw(pid, songIds),
      '歌单删曲',
    );
  }

  // ── UserPlaylistReadSource（F2，需登录） ──────────────────

  /// F2 用户歌单：一次给全量（`limit` 给足，歌单数极少过千）。
  @override
  Future<UserPlaylistsPage> userPlaylists({
    int offset = 0,
    int limit = 1000,
  }) async {
    final account = await currentAccount();
    final uid = int.tryParse(account?.userId ?? '') ?? 0;
    if (uid <= 0) throw const LoginRequired('网易云未登录，无法读取歌单');
    return mapNeteaseUserPlaylists(
      await _client.userPlaylistsRaw(uid, offset: offset, limit: limit),
    );
  }

  // ── UserLibrarySource（F3 + A4，需登录） ──────────────────

  /// F3 取「我喜欢」id 列表 → A4 分批取详情。
  ///
  /// F3 只回 id（实测 1009 首），必须再打详情口才有歌名/歌手/封面；
  /// 批次大小取 [_likedDetailBatch]，避免单请求 `c` 数组过长。
  @override
  Future<List<Track>> likedTracks() async {
    final account = await currentAccount();
    final uid = int.tryParse(account?.userId ?? '') ?? 0;
    if (uid <= 0) throw const LoginRequired('网易云未登录，无法读取「我喜欢」');
    final ids = mapNeteaseLikedSongIds(await _client.likedSongIdsRaw(uid));
    final out = <Track>[];
    for (var i = 0; i < ids.length; i += _likedDetailBatch) {
      final end = i + _likedDetailBatch > ids.length
          ? ids.length
          : i + _likedDetailBatch;
      out.addAll(
        mapNeteaseSongDetails(await _client.songDetailRaw(ids.sublist(i, end))),
      );
    }
    return out;
  }

  // ── UserLikedWriteSource（F4，需登录） ────────────────────

  @override
  Future<void> setTrackLiked(Track track, {required bool liked}) async {
    final songId = _songId(track);
    if (songId <= 0) throw const NotFound('曲目 id 无效');
    throwIfNeteaseWriteFailed(
      await _client.likeSongRaw(songId, like: liked),
      liked ? '红心' : '取消红心',
    );
  }

  // ── DeviceLoginSource（E2/E3 扫码登录） ───────────────────

  /// 二维码内容不是裸 unikey，而是 scanlogin URL（构造在 [NeteaseClient]）。
  @override
  Future<LoginQrSession> createLoginQr() async {
    final session = await _client.createQrSession();
    return LoginQrSession(
      id: session.key,
      qrContent: session.qrContent,
      payload: session,
    );
  }

  /// 状态码 → [LoginQrStatus]；803 时顺带确认登录态并落 cookie。
  @override
  Future<LoginQrPoll> pollLoginQr(LoginQrSession session) async {
    final payload = session.payload;
    if (payload is! NeteaseQrSession) {
      throw const UpstreamChanged('扫码会话已失效，请重新获取二维码');
    }
    final res = await _client.pollQrLogin(payload);
    final status = mapNeteaseQrStatus(res.code);
    if (status == LoginQrStatus.confirmed) {
      await _client.confirmQrLogin(refreshToken: res.refreshToken);
    }
    return LoginQrPoll(status: status, message: res.message);
  }

  @override
  Future<LoginAccount?> currentAccount() async {
    if (!_client.hasLogin) return null;
    return mapNeteaseAccount(await _client.accountRaw());
  }

  @override
  Future<void> logout() async {
    _client.clearLogin();
  }

  // ── H 组：账号档案 / 会员（NeteaseAccountSource，需登录） ───

  /// H6 用户详情。uid 由调用方从 [currentAccount] 取（避免本方法再打一次
  /// `account/get`——[currentAccount] 每次都是真网络请求）。
  @override
  Future<NeteaseUserDetail> userDetail(int uid) async {
    if (uid <= 0) throw const LoginRequired('网易云未登录，无法读取账号档案');
    return mapNeteaseUserDetail(await _client.userDetailRaw(uid));
  }

  @override
  Future<NeteaseVipInfo> vipInfo({required int userId}) async {
    if (userId <= 0) throw const LoginRequired('网易云未登录，无法读取会员信息');
    return mapNeteaseVipInfo(await _client.vipInfoRaw(userId: userId));
  }

  @override
  Future<NeteaseLevelInfo> userLevel() async {
    return mapNeteaseUserLevel(await _client.userLevelRaw());
  }

  // ── 内部 ─────────────────────────────────────────────────

  int _songId(Track track) => int.tryParse(track.id.trim()) ?? 0;

  List<int> _songIds(List<Track> tracks) => [
    for (final t in tracks)
      if (_songId(t) > 0) _songId(t),
  ];

  // ── N1 评论（读侧；写侧要登录，留到 N2） ────────────────────

  /// 能力面自己的失败文案（读侧契约是「返回空 + 原因」，不抛异常）。
  String _commentError = '';

  /// 歌曲评论档位：首屏前用实测默认值，拿到响应后用服务端 `sortTypeList` 覆盖。
  List<({String id, String label})> _songSorts = neteaseDefaultCommentSorts;

  /// E1 拉一页评论的公共部分（歌曲 / 歌单 / 专辑只是 threadId 前缀不同）。
  ///
  /// [cursor] 是上一页服务端给的 `data.cursor`（原样回传，不自己拼）。
  Future<CommentPage> _fetchCommentPage(
    String threadId, {
    required int page,
    required int pageSize,
    required String cursor,
    required int sortType,
  }) async {
    final raw = await _client.commentListRaw(
      threadId: threadId,
      pageNo: page,
      pageSize: pageSize,
      cursor: cursor,
      sortType: sortType,
    );
    return mapNeteaseComments(raw, threadId: threadId).page;
  }

  /// 档位 id → `sortType`。空串（默认档）取首项。
  ///
  /// 服务端给的 `1`（推荐）与发出去的 `99` 是同一个档位的两套编码，
  /// 这里发的全是**请求侧编码**（99 / 2 / 3）。
  int _sortTypeOf(String sort) {
    final id = sort.isEmpty ? _songSorts.first.id : sort;
    return int.tryParse(id) ?? 99;
  }

  /// 楼层：E2 一次给 `limit` 条。
  ///
  /// 网易楼层端点**没有分页参数**（`time` 游标翻页未实测），所以只取第一页 ——
  /// 与酷狗「按 page 翻楼层」不同，这里不假装有分页。
  Future<List<Comment>> _fetchFloor(
    String threadId, {
    required String rootCommentId,
    required int pageSize,
  }) async {
    final raw = await _client.commentFloorRaw(
      threadId: threadId,
      parentCommentId: rootCommentId,
      limit: pageSize,
    );
    return mapNeteaseFloorComments(raw);
  }

  @override
  String get lastError => _commentError;

  @override
  String get resourceCommentError => _commentError;

  @override
  List<({String id, String label})> get commentSortOptions => _songSorts;

  @override
  Future<CommentPage> songComments(
    Track track, {
    int page = 1,
    int pageSize = 20,
    String sort = '',
    String cursor = '',
  }) async {
    _commentError = '';
    final id = _songId(track);
    if (id <= 0) {
      _commentError = '缺少歌曲 ID';
      return CommentPage.empty;
    }
    try {
      final result = mapNeteaseComments(
        await _client.commentListRaw(
          threadId: 'R_SO_4_$id',
          pageNo: page,
          pageSize: pageSize,
          cursor: cursor,
          sortType: _sortTypeOf(sort),
        ),
        threadId: 'R_SO_4_$id',
      );
      // 档位以服务端给的为准（首屏前用的是实测默认值）。
      _songSorts = result.sorts;
      return result.page;
    } catch (_) {
      _commentError = '评论加载失败';
      return CommentPage.empty;
    }
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
    final threadId = childrenId.isNotEmpty ? childrenId : 'R_SO_4_${_songId(track)}';
    try {
      return await _fetchFloor(
        threadId,
        rootCommentId: rootCommentId,
        pageSize: pageSize,
      );
    } catch (_) {
      _commentError = '楼层加载失败';
      return const [];
    }
  }

  @override
  Future<int?> commentCount(Track track) async => null;

  @override
  Future<CommentPage> resourceComments(
    CommentResourceKind kind, {
    required String resourceId,
    int page = 1,
    int pageSize = 20,
    String cursor = '',
  }) async {
    _commentError = '';
    final threadId = _resourceThreadId(kind, resourceId);
    if (threadId == null) {
      _commentError = '缺少资源 ID';
      return CommentPage.empty;
    }
    try {
      // 歌单 / 专辑档位固定用推荐档（该口没有 sort 参数的概念，
      // 与歌曲共用同一端点，实测三档都能出，但 UI 不给档位切换）。
      const sortType = 99;
      return await _fetchCommentPage(
        threadId,
        page: page,
        pageSize: pageSize,
        cursor: cursor,
        sortType: sortType,
      );
    } catch (_) {
      _commentError = '评论加载失败';
      return CommentPage.empty;
    }
  }

  @override
  Future<List<Comment>> resourceFloorReplies(
    CommentResourceKind kind, {
    required String childrenId,
    required String rootCommentId,
    int page = 1,
    int pageSize = 20,
  }) async {
    _commentError = '';
    if (childrenId.isEmpty) {
      _commentError = '评论池未知，无法加载楼层';
      return const [];
    }
    try {
      return await _fetchFloor(
        childrenId,
        rootCommentId: rootCommentId,
        pageSize: pageSize,
      );
    } catch (_) {
      _commentError = '楼层加载失败';
      return const [];
    }
  }

  @override
  Future<int?> resourceCommentCount(CommentResourceKind kind, String id) async =>
      null;

  // ── N2 写侧（发评论 / 回复 / 点赞） ────────────────────────

  /// 网易的登录凭据是 `MUSIC_U` cookie（**不是**酷狗的 `AuthTokenHolder`）。
  @override
  bool get isLoggedIn => _client.hasLogin;

  /// 写口的统一收口：非 200 一律抛 [SourceFailure]（写侧契约如此）。
  Future<void> _requireOk(Future<String> Function() call) async {
    final raw = await call();
    final code = NeteaseClient.bodyCode(raw) ?? 0;
    if (code == 200) return;
    throw mapNeteaseCode(code, message: _writeFailText(code));
  }

  /// 业务码 → 用户可读文案（301 最常见：登录态失效）。
  static String _writeFailText(int code) => switch (code) {
        301 || 302 || 800 || 801 || 802 || 803 => '登录状态已失效，请重新登录',
        -460 || -462 || 405 => '操作太频繁，请稍后再试',
        403 => '没有权限执行该操作',
        _ => '操作失败（code=$code）',
      };

  /// E3 / E4 的 threadId：优先用评论池（它对网易就是 threadId），
  /// 没有则从 track 拼 —— 与读侧同一个口径。
  String _writeThreadId(Track track, String childrenId) {
    if (childrenId.isNotEmpty) return childrenId;
    final id = _songId(track);
    return id > 0 ? 'R_SO_4_$id' : '';
  }

  @override
  Future<void> sendSongComment({
    required Track track,
    required String childrenId,
    required String content,
  }) async {
    final threadId = _writeThreadId(track, childrenId);
    if (threadId.isEmpty) throw const NotFound('歌曲 ID 未知，无法发表评论');
    await _requireOk(
      () => _client.commentAddRaw(threadId: threadId, content: content),
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
  }) async {
    final threadId = _writeThreadId(track, childrenId);
    if (threadId.isEmpty) throw const NotFound('歌曲 ID 未知，无法回复');
    // 网易靠 `commentId` 表达层级，**不拼** `//@昵称:内容` 的引用文本
    // （那是酷狗的约定），故 [replyToUser] / [replyToContent] 在此不使用。
    await _requireOk(
      () => _client.commentReplyRaw(
        threadId: threadId,
        commentId: rootCommentId,
        content: content,
      ),
    );
  }

  @override
  Future<void> setCommentLiked({
    required String childrenId,
    required String commentId,
    required bool like,
  }) async {
    if (childrenId.isEmpty) throw const NotFound('评论池未知，请刷新评论后再试');
    await _requireOk(
      () => _client.commentLikeRaw(
        threadId: childrenId,
        commentId: commentId,
        like: like,
      ),
    );
  }

  // ── N3 热搜 ─────────────────────────────────────────────

  /// 网易热搜实测**只有 10 条、无分页**，故 [count] 只是在更长时截断；
  /// 取不到（风控 / 网络）时给空列表，UI 自行收起该区块。
  @override
  Future<List<String>> hotKeywords({int count = 20}) async {
    try {
      final words = mapNeteaseSearchHot(await _client.searchHotRaw());
      if (count <= 0 || words.length <= count) return words;
      return words.take(count).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 资源 threadId 前缀（见 `网易云接口文档.md` §三-B）：
  /// 歌单 `A_PL_0_` / 专辑 `R_AL_3_`。
  String? _resourceThreadId(CommentResourceKind kind, String resourceId) {
    final id = int.tryParse(resourceId.trim()) ?? 0;
    if (id <= 0) return null;
    return switch (kind) {
      CommentResourceKind.playlist => 'A_PL_0_$id',
      CommentResourceKind.album => 'R_AL_3_$id',
    };
  }

  // ── A1-MV 详情 / 取流 ─────────────────────────────────────

  /// MV 详情 + 多档片源。`brief.id` 必须是 **mvid**（数字）。
  ///
  /// 档位从 `data.brs[].br` 枚举（`mp.pl` 封顶），每档
  /// [MvPlaySource.hash] 编码为 `mvid@r` —— 酷狗 hash 无 `@`，空间不冲突。
  @override
  Future<MvDetail?> fetchMvDetail(MvBrief brief) async {
    final mvid = brief.id.trim();
    if (mvid.isEmpty || int.tryParse(mvid) == null) return null;
    final raw = await _client.mvDetailRaw(mvid);
    return mapNeteaseMvDetail(raw, fallbackBrief: brief);
  }

  /// 取流：`hash` 形如 `mvid@r`（见 [parseNeteaseMvSourceHash]）。
  ///
  /// 网易直链**无防盗链头**（带 `wsSecret`/`wsTime` 签名），故 headers 为空；
  /// 时效约 `expi` 秒，跨会话不要缓存 url。
  @override
  Future<MvPlayUrlResult> resolveMvPlayUrl(String hash) async {
    final parsed = parseNeteaseMvSourceHash(hash);
    if (parsed.mvid.isEmpty || int.tryParse(parsed.mvid) == null) {
      throw const NotFound('无效的 MV 来源标识');
    }
    final raw = await _client.mvUrlRaw(parsed.mvid, r: parsed.r);
    return mapNeteaseMvUrl(raw);
  }
}

/// 默认网易云音源实例（与 [neteaseClient] 共享会话）。
final neteaseSource = NeteaseSource();

/// E3 状态码 → [LoginQrStatus]（800 过期 / 801 待扫 / 802 待确认 / 803 成功）。
LoginQrStatus mapNeteaseQrStatus(int code) => switch (code) {
      800 => LoginQrStatus.expired,
      801 => LoginQrStatus.waiting,
      802 => LoginQrStatus.scanned,
      803 => LoginQrStatus.confirmed,
      _ => LoginQrStatus.unknown,
    };

/// A1c 分类搜索的 `type` 取值（实测：1 单曲 / 10 专辑 / 100 歌手 / 1000 歌单）。
enum _NeteaseSearchKind {
  song(1),
  album(10),
  artist(100),
  playlist(1000);

  const _NeteaseSearchKind(this.wire);

  final int wire;
}
