import '../../../core/api/netease/netease_client.dart';
import '../../../core/api/netease/netease_mappers.dart';
import '../../../core/models/audio_quality.dart';
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
        PersonalFmSource,
        UserPlaylistWriteSource,
        UserLibrarySource,
        DeviceLoginSource {
  NeteaseSource({NeteaseClient? client}) : _client = client ?? neteaseClient;

  final NeteaseClient _client;

  @override
  MusicPlatform get platform => MusicPlatform.netease;

  /// 网易官方榜单 id（实测 G10：飙升 / 新歌 / 热歌）。
  static const List<({String id, String name})> officialBoards = [
    (id: '19723756', name: '飙升榜'),
    (id: '3779629', name: '新歌榜'),
    (id: '3778678', name: '热歌榜'),
  ];

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
  @override
  Future<List<Track>> dailyRecommendedSongs() async {
    final raw = await _client.dailyRecommendSongsRaw();
    return mapNeteaseDailySongs(raw);
  }

  // ── RankSource（G10） ────────────────────────────────────

  /// 网易没有「榜单列表」接口，官方榜是固定三个 id；这里并行补一次封面/名称，
  /// 失败则退回内置名称（封面留空，由 UI 出占位图）。
  @override
  Future<List<({String id, String name, String coverUrl})>> rankBoards() async {
    final metas = await Future.wait([
      for (final board in officialBoards) _boardMeta(board.id),
    ]);
    return [
      for (var i = 0; i < officialBoards.length; i++)
        (
          id: officialBoards[i].id,
          name: metas[i].name.isEmpty ? officialBoards[i].name : metas[i].name,
          coverUrl: metas[i].coverUrl,
        ),
    ];
  }

  /// 复用歌单详情（G10）。歌单曲目**上限 1000 首**（实测），故 [page] 不生效。
  @override
  Future<List<Track>> rankTracks(String boardId, {int page = 1}) async {
    final id = int.tryParse(boardId.trim()) ?? 0;
    if (id <= 0) throw const NotFound('榜单 id 无效');
    final raw = await _client.playlistDetailRaw(id);
    return mapNeteasePlaylistTracks(raw);
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

  Future<({String name, String coverUrl, int trackCount})> _boardMeta(
    String boardId,
  ) async {
    try {
      final raw = await _client.playlistDetailRaw(
        int.parse(boardId),
        n: 1,
        s: 0,
      );
      return mapNeteasePlaylistMeta(raw);
    } catch (_) {
      return (name: '', coverUrl: '', trackCount: 0);
    }
  }

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
