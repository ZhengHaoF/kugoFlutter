import '../../../core/api/netease/netease_client.dart';
import '../../../core/api/netease/netease_mappers.dart';
import '../../../core/models/audio_quality.dart';
import '../../../core/models/catalog_models.dart';
import '../../../core/models/daily_recommend.dart';
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
        UserPlaylistReadSource,
        UserLibrarySource,
        DeviceLoginSource {
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
    final songId = _songId(track);
    if (songId <= 0) return LyricPayload.empty;
    final raw = await _client.songLyricRaw(songId);
    return mapNeteaseLyric(raw);
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
  @override
  Future<({PlaylistBrief brief, List<Track> tracks})?> fetchPlaylistDetail(
    String id,
  ) async {
    final pid = int.tryParse(id.trim()) ?? 0;
    if (pid <= 0) return null;
    return mapNeteasePlaylistDetail(await _client.playlistDetailRaw(pid));
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

  /// 网易 FM 是「一次一换」：每次 `radio/get` 返回下一批（通常 1 首），
  /// 与酷狗的 `remain` 语义不同，故不循环补足。
  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async {
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

  // ── 内部 ─────────────────────────────────────────────────

  int _songId(Track track) => int.tryParse(track.id.trim()) ?? 0;

  List<int> _songIds(List<Track> tracks) => [
    for (final t in tracks)
      if (_songId(t) > 0) _songId(t),
  ];
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
