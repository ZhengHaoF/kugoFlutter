import 'dart:convert';

import '../../models/audio_quality.dart';
import '../../models/catalog_models.dart';
import '../../models/cloud_models.dart';
import '../../models/comment.dart';
import '../../models/mv_models.dart';
import '../../models/search_result.dart';
import '../../models/track.dart';
import '../../source/capabilities.dart';
import '../../source/music_platform.dart';
import '../../source/music_source.dart';
import '../../utils/lrc_parser.dart';
import 'netease_account_models.dart';
import 'netease_crypto.dart';
import 'netease_failures.dart';

/// 网易云 JSON → 统一模型。字段差异（`ar`/`artists`、`al`/`album`、
/// `dt`/`duration`、`song` 嵌套）全部在这里收口，UI 只见 [Track]。
///
/// 对齐依据见 [网易云接口文档.md] §五 A1/A2/C1/D5/G3/G4/G10。

// ── 播放防盗链 ───────────────────────────────────────────────

/// 网易播放防盗链头。**由 Source 下发**，播放器不得写死（见 多音源接入方案 §3.4）。
const Map<String, String> neteasePlaybackHeaders = {
  'Referer': 'https://music.163.com',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10; kugo-netease-probe) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
};

// ── 搜索 / 曲目列表 ──────────────────────────────────────────

/// A1 搜索单曲：`result.songs`（cloudsearch 同形，实测走旧口 `search/get`）。
SearchPageResult<Track> mapNeteaseSearchSongs(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '搜索');
  final result = _asMap(root['result']);
  return SearchPageResult(
    items: mapNeteaseSongs(result['songs'] ?? root['songs']),
    total: _searchTotal(result, 'songCount'),
  );
}

/// A1c 搜索歌单：`result.playlists`。
///
/// ⚠️ 字段名**未实测**（探针只确认 `type=1000` 有返回），故多键回退。
SearchPageResult<PlaylistBrief> mapNeteaseSearchPlaylists(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌单搜索');
  final result = _asMap(root['result']);
  return SearchPageResult(
    items: _mapNodes(
      result['playlists'] ?? root['playlists'],
      mapNeteasePlaylistBrief,
    ),
    total: _searchTotal(result, 'playlistCount'),
  );
}

/// A1c 搜索专辑：`result.albums`。⚠️ 字段名未实测，多键回退。
SearchPageResult<AlbumBrief> mapNeteaseSearchAlbums(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '专辑搜索');
  final result = _asMap(root['result']);
  return SearchPageResult(
    items: _mapNodes(result['albums'] ?? root['albums'], mapNeteaseAlbumBrief),
    total: _searchTotal(result, 'albumCount'),
  );
}

/// A1c 搜索歌手：`result.artists`。⚠️ 字段名未实测，多键回退。
SearchPageResult<ArtistBrief> mapNeteaseSearchArtists(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌手搜索');
  final result = _asMap(root['result']);
  return SearchPageResult(
    items: _mapNodes(
      result['artists'] ?? root['artists'],
      mapNeteaseArtistBrief,
    ),
    total: _searchTotal(result, 'artistCount'),
  );
}

/// 搜索歌单节点 → [PlaylistBrief]；`id` 非数字视为无效。
PlaylistBrief? mapNeteasePlaylistBrief(Object? node) {
  if (node is! Map) return null;
  final m = Map<String, dynamic>.from(node);
  final id = _int(m['id']);
  if (id <= 0) return null;
  final creator = _asMap(m['creator']);
  final play = _int(m['playCount'] ?? m['playcount']);
  return PlaylistBrief(
    id: '$id',
    name: _str(m['name'] ?? m['title']),
    coverUrl: _pic(_str(
      m['coverImgUrl'] ?? m['picUrl'] ?? m['img1v1Url'] ?? m['cover'],
    )),
    description: _str(m['description'] ?? m['desc']),
    creator: _str(creator['nickname'] ?? creator['name'] ?? m['creatorName']),
    trackCount: _int(m['trackCount'] ?? m['songCount']),
    playCountLabel: play > 0 ? _countLabel(play) : '',
    platform: MusicPlatform.netease,
  );
}

/// 搜索 / 新碟专辑节点 → [AlbumBrief]；`id` 非数字视为无效。
///
/// 封面走 [_albumCover]：**G12 新碟节点只给 `picId`**（实测 2026-09-26，
/// `ALL`/`KR`/`JP` 分区节点键为 `songs,paid,…,artists,copyrightId,picId`，无 `picUrl`），
/// 故必须带 `picId` → CDN 直链回退，否则新碟列表整列灰块。
AlbumBrief? mapNeteaseAlbumBrief(Object? node) {
  if (node is! Map) return null;
  final m = Map<String, dynamic>.from(node);
  final id = _int(m['id']);
  if (id <= 0) return null;
  final artists = _artists(m);
  return AlbumBrief(
    id: '$id',
    name: _str(m['name'] ?? m['albumName']),
    coverUrl: _albumCover(m),
    artist: artists.names.isEmpty
        ? _str(_asMap(m['artist'])['name'] ?? m['artistName'])
        : artists.names.join('/'),
    trackCount: _int(m['size'] ?? m['trackCount'] ?? m['songCount']),
    publishDate: _dateLabel(_int(m['publishTime'] ?? m['publishTimeMs'])),
    platform: MusicPlatform.netease,
  );
}

/// 搜索歌手节点 → [ArtistBrief]；`id` 非数字视为无效。
ArtistBrief? mapNeteaseArtistBrief(Object? node) {
  if (node is! Map) return null;
  final m = Map<String, dynamic>.from(node);
  final id = _int(m['id']);
  if (id <= 0) return null;
  final alias = m['alias'];
  return ArtistBrief(
    id: '$id',
    name: _str(m['name'] ?? m['artistName']),
    avatarUrl: _pic(_str(
      m['picUrl'] ?? m['img1v1Url'] ?? m['avatar'] ?? m['cover'],
    )),
    songCount: _int(m['musicSize'] ?? m['songSize']),
    fansCount: _int(m['fansCount'] ?? m['fansSize']),
    sourceDesc: alias is List
        ? alias.where((e) => _str(e).isNotEmpty).join(' / ')
        : _str(alias),
    platform: MusicPlatform.netease,
  );
}

/// 网易搜索用 `result.<key>Count` 报总数；缺失返回 `null`（不猜）。
int? _searchTotal(Map<String, dynamic> result, String key) {
  final v = result[key];
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}'.trim());
}

List<T> _mapNodes<T>(Object? list, T? Function(Object?) map) {
  if (list is! List) return const [];
  final out = <T>[];
  for (final node in list) {
    final v = map(node);
    if (v != null) out.add(v);
  }
  return out;
}

/// 播放量展示：与酷狗 `formatCount` 同口径（万/亿）。
String _countLabel(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return '$n';
}

/// epoch 毫秒 → `yyyy-MM-dd`（酷狗 `publishtime` 也是这个形状）。
String _dateLabel(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$mm-$dd';
}

/// D5 歌单详情：`playlist.tracks`（**上限 1000 首**，实测）。
List<Track> mapNeteasePlaylistTracks(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌单详情');
  final playlist = _asMap(root['playlist']);
  return mapNeteaseSongs(playlist['tracks']);
}

// ── D 详情页（歌单 / 专辑 / 歌手） ────────────────────────────

/// D2 歌单详情（完整）：`playlist` 头 + `tracks`（上限 1000 首，实测）。
///
/// 网易榜单也复用歌单详情（G10），故 [PlaylistDetailSource] 的网易实现
/// 榜单/歌单共用本映射。
({PlaylistBrief brief, List<Track> tracks})? mapNeteasePlaylistDetail(
  String raw,
) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌单详情');
  final playlist = _asMap(root['playlist']);
  final brief = mapNeteasePlaylistBrief(playlist);
  if (brief == null) return null;
  return (brief: brief, tracks: mapNeteaseSongs(playlist['tracks']));
}

/// D3 专辑详情：`album`（头）+ 顶层 `songs[]`（实测张悬《神的游戏》9 首）。
AlbumDetail? mapNeteaseAlbumDetail(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '专辑详情');
  final al = _asMap(root['album']);
  final id = _int(al['id']);
  if (id <= 0) return null;
  final artist = _asMap(al['artist']);
  return AlbumDetail(
    id: '$id',
    name: _str(al['name'] ?? al['albumName']),
    coverUrl: _pic(_str(
      al['picUrl'] ?? al['blurPicUrl'] ?? al['coverImgUrl'] ?? al['cover'],
    )),
    artist: _str(artist['name'] ?? al['artistName'] ?? artist['name']),
    publishTime: _dateLabel(_int(al['publishTime'] ?? al['publishTimeMs'])),
    intro: _str(al['description'] ?? al['intro'] ?? al['briefDesc']),
    songs: mapNeteaseSongs(root['songs'] ?? al['songs']),
  );
}

/// D4 歌手头部信息：`data.artist`（实测周杰伦 568 曲 / 44 专）。
ArtistDetail? mapNeteaseArtistDetail(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌手详情');
  final data = _asMap(root['data']);
  final artist = _asMap(data['artist'] ?? root['artist']);
  final id = _int(artist['id']);
  if (id <= 0) return null;
  return ArtistDetail(
    id: '$id',
    name: _str(artist['name'] ?? artist['artistName']),
    avatarUrl: _pic(_str(
      artist['avatar'] ??
          artist['img1v1Url'] ??
          artist['picUrl'] ??
          artist['cover'],
    )),
    intro: _str(artist['briefDesc'] ?? artist['description']),
    songCount: _int(artist['musicSize'] ?? artist['songSize']),
    albumCount: _int(artist['albumSize']),
    mvCount: _int(artist['mvSize'] ?? artist['videoSize']),
  );
}

/// D6 歌手歌曲分页：`songs[]` + `more`（hasMore）+ `total`。
ArtistSongsPage mapNeteaseArtistSongs(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌手歌曲');
  return ArtistSongsPage(
    songs: mapNeteaseSongs(root['songs']),
    total: _int(root['total']),
    hasMore: root['more'] == true,
  );
}

/// G3 每日推荐：`data.dailySongs`。
List<Track> mapNeteaseDailySongs(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '每日推荐');
  final data = _asMap(root['data']);
  return mapNeteaseSongs(
    data['dailySongs'] ?? data['recommend'] ?? root['recommend'],
  );
}

/// G4 私人 FM：`data[]`（一次一批，通常 1 首）。
List<Track> mapNeteaseFmSongs(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '私人 FM');
  return mapNeteaseSongs(root['data'] ?? root['result']);
}

/// G5 新歌推荐：`result[]`，曲目嵌在节点 `song` 里（由 [mapNeteaseSong] 解包）。
List<Track> mapNeteasePersonalizedNewSongs(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '新歌速递');
  return mapNeteaseSongs(root['result'] ?? root['data']);
}

/// G6 分类/热门歌单：`playlists[]`（节点同搜索歌单，复用 brief 映射）。
List<PlaylistBrief> mapNeteaseTopPlaylists(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '分类歌单');
  final data = _asMap(root['data']);
  return _mapNodes(
    root['playlists'] ?? data['playlists'] ?? root['result'],
    mapNeteasePlaylistBrief,
  );
}

/// G12 新碟上架：`albums[]`（顶层或 `result` 下）→ [AlbumBrief]。
///
/// 节点形态同搜索专辑（复用 [mapNeteaseAlbumBrief]），但**只给 `picId` 不给 `picUrl`**，
/// 封面由 [_albumCover] 拼 CDN 直链。
List<AlbumBrief> mapNeteaseNewAlbums(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '新碟上架');
  final data = _asMap(root['data']);
  return _mapNodes(
    root['albums'] ?? data['albums'] ?? root['result'],
    mapNeteaseAlbumBrief,
  );
}

/// G13 歌手列表：`artists[]`（顶层或 `result` 下）→ [ArtistBrief]。
///
/// 节点形态同搜索歌手（复用 [mapNeteaseArtistBrief]，头像走 `img1v1Url`）。
List<ArtistBrief> mapNeteaseArtistList(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌手列表');
  final data = _asMap(root['data']);
  return _mapNodes(
    root['artists'] ?? data['artists'] ?? root['result'],
    mapNeteaseArtistBrief,
  );
}

/// G7b 精品标签：`tags[]` → **单组扁平**标签（网易无二级分类）。
///
/// 网易分类歌单接口 `cat` 收的是**标签名**（实测 `cat=华语`），故 [PlaylistTag.id]
/// 直接用标签名，UI 原样回传；接口未给「全部」时前置一个，保证默认分类可用。
List<PlaylistTagGroup> mapNeteasePlaylistTags(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌单标签');
  final data = _asMap(root['data']);
  final tags = root['tags'] ?? data['tags'];
  final out = <PlaylistTag>[];
  final seen = <String>{};
  if (tags is List) {
    for (final node in tags) {
      if (node is! Map) continue;
      final m = Map<String, dynamic>.from(node);
      final name = _str(m['name'] ?? m['tagName'] ?? m['id']);
      if (name.isEmpty || !seen.add(name)) continue;
      out.add(PlaylistTag(id: name, name: name, group: '推荐'));
    }
  }
  if (!seen.contains('全部')) {
    out.insert(0, const PlaylistTag(id: '全部', name: '全部', group: '推荐'));
  }
  return [PlaylistTagGroup(name: '推荐', child: out)];
}

/// G11 榜单列表 → 榜单元数据（`id` 为空的节点跳过）。
///
/// 响应里每张榜另带的整榜 `tracks` **不解析**（曲目走 G10 `playlistDetailRaw`）；
/// 这里只取 `id / name / coverImgUrl`，即「有哪些榜 + 榜名 + 封面」。
List<({String id, String name, String coverUrl})> mapNeteaseToplistBoards(
  String raw,
) {
  final root = _decode(raw);
  final list = root['list'];
  if (list is! List) return const [];
  final out = <({String id, String name, String coverUrl})>[];
  for (final item in list) {
    final m = _asMap(item);
    final id = _str(m['id']);
    if (id.isEmpty) continue;
    out.add((
      id: id,
      name: _str(m['name']),
      coverUrl: _pic(_str(m['coverImgUrl'])),
    ));
  }
  return out;
}

/// 任意曲目节点列表 → [Track]。无法识别的节点跳过（不抛）。
List<Track> mapNeteaseSongs(Object? list) {
  if (list is! List) return const [];
  final out = <Track>[];
  for (final item in list) {
    final t = mapNeteaseSong(item);
    if (t != null) out.add(t);
  }
  return out;
}

/// 单曲节点 → [Track]。`id` 非数字视为无效，返回 null。
///
/// 嵌套拆包：G5 新歌把曲目塞 `song` 里；**云盘列表 / 详情把曲目塞 `simpleSong` 里**
/// （2026-10-09 实测，见 `mapNeteaseCloudPage`）。不拆这层会每一项都取不到
/// `id` 而被静默丢弃——云盘页「有容量无歌曲」就是这么来的。
Track? mapNeteaseSong(Object? node) {
  if (node is! Map) return null;
  var m = Map<String, dynamic>.from(node);
  // G5 新歌等把曲目塞在 `song` 里；云盘两口塞在 `simpleSong` 里。
  final nested = m['song'] ?? m['simpleSong'];
  if (nested is Map) m = Map<String, dynamic>.from(nested);

  final id = _int(m['id']);
  if (id <= 0) return null;

  final artists = _artists(m);
  final album = _asMap(m['al'] ?? m['album'] ?? m['albumInfo']);
  final privilege = _asMap(m['privilege']);
  final fee = _int(m['fee']) != 0 ? _int(m['fee']) : _int(privilege['fee']);
  final qualities = _qualitiesFromPrivilege(privilege);
  final durationMs = _int(m['dt']) != 0 ? _int(m['dt']) : _int(m['duration']);

  return Track(
    id: '$id',
    name: _str(m['name'] ?? m['title']),
    artist: artists.names.isEmpty ? '未知歌手' : artists.names.join('/'),
    album: _str(album['name']),
    coverUrl: _albumCover(album),
    durationMs: durationMs > 0 ? durationMs : 0,
    platform: MusicPlatform.netease,
    artistId: artists.firstId,
    quality: _qualityToken(qualities),
    isVip: fee == 1 || fee == 4,
    availableQualities: qualities,
    // 网易不给「完整音质目录」，hi-res 视为未知 → 播放时向下 resolve。
    qualityCatalogComplete: false,
    recDesc: _str(m['reason'] ?? m['recommendReason'] ?? m['recReason']),
  );
}

// ── F. 我喜欢 / 用户曲库 ─────────────────────────────────────

/// F3 云端「我喜欢」song id 列表：顶层 `ids`（纯数字数组，实测 1009 首）。
///
/// ⚠️ 这里只给 id，曲目详情需再走 [mapNeteaseSongDetails]（见 [NeteaseSource.likedTracks]）。
List<int> mapNeteaseLikedSongIds(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '我喜欢');
  final ids = root['ids'] ?? root['data'];
  if (ids is! List) return const [];
  final out = <int>[];
  for (final e in ids) {
    final id = _int(e);
    if (id > 0) out.add(id);
  }
  return out;
}

/// A4 批量歌曲详情：`songs[]` → [Track]。
///
/// 详情是**新结构**（实测 F3b）：歌手 `ar`、专辑封面 `al.picUrl`、时长 `dt`，
/// 全部由 [mapNeteaseSong] 收口，这里只负责校验 code 与取数组。
List<Track> mapNeteaseSongDetails(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '歌曲详情');
  return mapNeteaseSongs(root['songs'] ?? root['data']);
}

/// F2 用户歌单列表：`playlist[]` + `more`。
///
/// 分类口径对齐 NeriPlayer：`subscribed == true` = 收藏（他人歌单）；
/// 其余（含 `specialType == 5` 的「我喜欢的音乐」）归自建。默认单会打上
/// `isDefault`，供 UI 出红心封面与「我喜欢」统计。
UserPlaylistsPage mapNeteaseUserPlaylists(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '用户歌单');
  final created = <PlaylistBrief>[];
  final collected = <PlaylistBrief>[];
  final list = root['playlist'];
  if (list is List) {
    for (final node in list) {
      var brief = mapNeteasePlaylistBrief(node);
      if (brief == null) continue;
      final m = _asMap(node);
      final specialType = _int(m['specialType']);
      final isLiked = specialType == 5;
      if (isLiked) brief = brief.copyWith(isDefault: true);
      if (m['subscribed'] == true && !isLiked) {
        collected.add(brief);
      } else {
        created.add(brief);
      }
    }
  }
  return UserPlaylistsPage(
    created: created,
    collected: collected,
    more: root['more'] == true,
  );
}

// ── A2 播放地址 ──────────────────────────────────────────────

/// A2：`data[0]` → [PlayUrlResult]。
///
/// 实测：游客态请求 `exhigh`/`lossless` 一律下发 `standard`；
/// 付费曲 `fee=1` + `freeTrialInfo` 试听片段。
PlayUrlResult mapNeteasePlayUrl(
  String raw, {
  Map<String, String> headers = neteasePlaybackHeaders,
}) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code == 301) throw const LoginRequired('网易云会话失效 code=301');
  if (code != 200) throw mapNeteaseCode(code, message: '播放地址 code=$code');

  final data = root['data'];
  final item = data is List && data.isNotEmpty
      ? data.first
      : (data is Map ? data : null);
  if (item is! Map) throw const NotFound('播放地址为空');
  final m = Map<String, dynamic>.from(item);

  final url = _str(m['url']);
  final fee = _int(m['fee']);
  final rawCode = _int(m['code']);
  final trial = m['freeTrialInfo'];

  if (url.isEmpty || url == 'null') {
    final privilege = _asMap(m['freeTrialPrivilege']);
    throw mapNeteasePlayFailure(
      dataCode: rawCode == 0 ? 200 : rawCode,
      fee: fee,
      cannotListenReason: privilege['cannotListenReason'] is num
          ? (privilege['cannotListenReason'] as num).toInt()
          : null,
    );
  }

  return PlayUrlResult(
    url: url,
    headers: headers,
    grantedQuality: neteaseLevelToQuality(_str(m['level'])),
    isPreviewClip: trial != null && trial != false,
  );
}

/// 响应 `level` → 抽象档。
///
/// `higher`（192k）在抽象档里无对应，按 `standard` 保守展示；
/// `jyeffect`/`sky` 是无损基底环绕 → `sq`；`jymaster` 母带 → `hiRes`。
AppQuality? neteaseLevelToQuality(String level) => switch (level
    .trim()
    .toLowerCase()) {
  'standard' => AppQuality.standard,
  'higher' => AppQuality.standard,
  'exhigh' => AppQuality.hq,
  'lossless' || 'jyeffect' || 'sky' => AppQuality.sq,
  'hires' || 'jymaster' => AppQuality.hiRes,
  _ => AudioQualityUtil.parseQualityToken(level),
};

// ── A1-MV 详情 / 取流 ─────────────────────────────────────
//
// 实测依据：docs/api-notes.md「网易云 MV」节（2026-09-28 A0 探针）。
// hash 语义：`mvid@r`（如 `14514682@1080`），与酷狗 hash（无 `@`）不冲突。

/// MV 详情：`data` + 平级 `mp`（特权）→ [MvDetail]。
///
/// `data.brs` 实测是 **List**（`[{size, br, point}]`）**不含 url**，
/// 只枚举档位；每档的 [MvPlaySource.hash] 存 `mvid@br`，取流时拆用。
/// `mp.pl` = 可播最高码率，档位以 `brs[].br` 为准并用 `mp.pl` 封顶。
MvDetail mapNeteaseMvDetail(String raw, {MvBrief? fallbackBrief}) {
  final root = _decode(raw);
  _throwIfBadCode(root, 'MV 详情');
  final data = _asMap(root['data']);
  final id = _int(data['id']);
  if (id <= 0) {
    throw const NotFound('MV 详情为空');
  }

  final artists = <String>{
    if (_str(data['artistName']).isNotEmpty) _str(data['artistName']),
    ..._mapNodes(data['artists'], (node) {
      final m = _asMap(node);
      final name = _str(m['name'] ?? m['artistName']);
      return name.isEmpty ? null : name;
    }),
  }.toList();

  final brief = MvBrief(
    id: '$id',
    hash: '$id', // 网易主键是 mvid；hash 字段兼容统一模型
    name: _str(data['name']),
    coverUrl: _pic(_str(data['cover'] ?? data['imgurl'])),
    artist: artists.join(' / '),
    artistId: '${_int(data['artistId'])}',
    userName: _str(data['artistName']),
    durationMs: _int(data['duration']),
    publishDate: _str(data['publishTime']).isNotEmpty
        ? _str(data['publishTime'])
        : _dateLabel(_int(data['publishTime'])),
    mixSongId: fallbackBrief?.mixSongId ?? '',
  );

  // 档位：brs[] 的 br，按 mp.pl 封顶后从清到糊排。
  final mp = _asMap(root['mp']);
  final maxBr = _int(mp['pl']) > 0 ? _int(mp['pl']) : 1080;
  final sources = <MvPlaySource>[];
  final brs = data['brs'];
  if (brs is List) {
    for (final node in brs) {
      final m = _asMap(node);
      final br = _int(m['br']);
      if (br <= 0 || br > maxBr) continue;
      sources.add(
        MvPlaySource(
          hash: _mvSourceHash('$id', br),
          label: _mvBrLabel(br),
          codec: 'h264',
          height: br,
          filesize: _int(m['size']),
          bitrate: br * 1000,
        ),
      );
    }
  }
  sources.sort((a, b) => b.isClearerThan(a) ? 1 : -1);
  if (sources.isEmpty) {
    // brs 缺失时兜底单档（仍走 mv/url，r 取 mp.pl 或 1080）。
    final br = maxBr > 0 ? maxBr : 1080;
    sources.add(
      MvPlaySource(
        hash: _mvSourceHash('$id', br),
        label: _mvBrLabel(br),
        codec: 'h264',
        height: br,
      ),
    );
  }

  final desc = _str(data['desc']).isNotEmpty
      ? _str(data['desc'])
      : _str(data['briefDesc']);
  return MvDetail(
    brief: brief,
    sources: sources,
    description: desc,
    playCountLabel: _int(data['playCount']) > 0
        ? _countLabel(_int(data['playCount']))
        : '',
    collectionCountLabel: _int(data['subCount']) > 0
        ? _countLabel(_int(data['subCount']))
        : '',
    authors: artists,
  );
}

/// MV 取流：`data.url` → [MvPlayUrlResult]。
///
/// 实测：`r` 会被服务端钳到实际档（低权限 1080 可能只回 480）；
/// 时效字段是 **`expi`（秒）**，不是 `validity`。无 backupUrls。
MvPlayUrlResult mapNeteaseMvUrl(
  String raw, {
  Map<String, String> headers = const {},
}) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code == 301) throw const LoginRequired('网易云会话失效 code=301');
  if (code != 200) throw mapNeteaseCode(code, message: 'MV 取流 code=$code');

  final data = _asMap(root['data']);
  final url = _str(data['url']);
  final dataCode = _int(data['code']);
  if (url.isEmpty || url == 'null') {
    if (dataCode != 0 && dataCode != 200) {
      throw mapNeteaseCode(dataCode, message: 'MV 取流 data.code=$dataCode');
    }
    throw const NotFound('MV 播放地址为空');
  }
  return MvPlayUrlResult(
    url: url,
    headers: headers,
    filesize: _int(data['size']),
  );
}

/// `MvPlaySource.hash` 编码：`mvid@r`。酷狗 hash 是 `[0-9a-f]{32}`，无 `@`。
String _mvSourceHash(String mvid, int r) => '$mvid@$r';

/// 拆 `mvid@r`；无 `@` 时整体当 mvid、r 取默认 1080。
({String mvid, int r}) parseNeteaseMvSourceHash(String hash) {
  final i = hash.indexOf('@');
  if (i < 0) return (mvid: hash.trim(), r: 1080);
  final mvid = hash.substring(0, i).trim();
  final r = int.tryParse(hash.substring(i + 1).trim()) ?? 1080;
  return (mvid: mvid, r: r);
}

String _mvBrLabel(int br) => switch (br) {
  >= 1080 => '${br}P',
  >= 720 => '${br}P',
  >= 480 => '${br}P',
  _ => '${br}P',
};

// ── C1 歌词 ─────────────────────────────────────────────────

/// C1：`lrc/yrc/tlyric/romalrc` → [LyricPayload]。
///
/// 有 `yrc`（逐字）优先；否则用 `lrc`。译文取 `tlyric`、音译取 `romalrc`，
/// 按时间戳对齐到主行（网易不保证与 yrc 同行序）。
LyricPayload mapNeteaseLyric(String raw) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code != 0 && code != 200) {
    throw mapNeteaseCode(code, message: '歌词 code=$code');
  }

  final lrc = _lyricText(root['lrc']);
  final yrc = _lyricText(root['yrc']);
  var lines = yrc.isEmpty ? const <LyricLine>[] : parseYrc(yrc);
  if (lines.isEmpty && lrc.isNotEmpty) lines = parseLrc(lrc);
  if (lines.isEmpty) return LyricPayload.empty;

  final translated = _timedTexts(_lyricText(root['tlyric']));
  final romanized = _timedTexts(_lyricText(root['romalrc']));

  return LyricPayload(
    lines: [
      for (final line in lines)
        LyricLine(
          timeMs: line.timeMs,
          endMs: line.endMs,
          text: line.text,
          chars: line.chars,
          translated: _nearestText(translated, line.timeMs),
          romanized: _nearestText(romanized, line.timeMs),
        ),
    ],
    sourceTag: yrc.isEmpty ? 'netease-lrc' : 'netease-yrc',
  );
}

/// 网易 YRC 逐字行：`[行起点,行时长](字偏移,字时长,0)字…`
///
/// 注意与酷狗 KRC 的 `<偏移,时长,0>` **不同**，这里是圆括号。
List<LyricLine> parseYrc(String raw) {
  final lineRe = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final charRe = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
  final out = <LyricLine>[];

  for (final sourceLine in raw.split(RegExp(r'\r?\n'))) {
    final lineMatch = lineRe.firstMatch(sourceLine.trim());
    if (lineMatch == null) continue;
    final lineStart = int.parse(lineMatch.group(1)!);
    final lineDur = int.parse(lineMatch.group(2)!);
    final content = lineMatch.group(3) ?? '';

    final chars = <LyricChar>[];
    for (final m in charRe.allMatches(content)) {
      final text = m.group(3) ?? '';
      if (text.isEmpty) continue;
      final start = lineStart + int.parse(m.group(1)!);
      final dur = int.parse(m.group(2)!);
      chars.add(LyricChar(
        text: text,
        startMs: start,
        endMs: start + (dur > 0 ? dur : 1),
      ));
    }

    // 无逐字标签时按整行兜底，保证 timeMs 可用。
    if (chars.isEmpty) {
      final plain = content.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
      if (plain.isEmpty) continue;
      chars.add(LyricChar(
        text: plain,
        startMs: lineStart,
        endMs: lineStart + (lineDur > 0 ? lineDur : 1),
      ));
    }

    out.add(LyricLine(
      timeMs: chars.first.startMs,
      endMs: chars.last.endMs,
      text: chars.map((c) => c.text).join(),
      chars: chars,
    ));
  }

  out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return out;
}

// ── 登录 / 账号（E1） ───────────────────────────────────────

/// E1：`/weapi/w/nuser/account/get` → [LoginAccount]。
///
/// 游客态 `code` 可能非 200、`profile` 可能为空，此时返回 null（不抛）。
///
/// 除 4 个基础字段外，还把档案字段（乐龄 / 性别 / 省市 / 签名 / 背景图）
/// 一并搬进 [neteaseUserDetailFromProfile]，供 H6 之外的场景兜底——
/// 实测 `profile` 有 39 个键，此前只读 4 个，其余全丢了。
LoginAccount? mapNeteaseAccount(String raw) {
  final Map<String, dynamic> root;
  try {
    root = _decode(raw);
  } catch (_) {
    return null;
  }
  if (_int(root['code']) != 200) return null;
  final profile = _asMap(root['profile']);
  final account = _asMap(root['account']);
  final userId = _int(profile['userId'] ?? account['id']);
  if (userId <= 0) return null;
  final nickname = _str(profile['nickname']);
  return LoginAccount(
    userId: '$userId',
    nickname: nickname.isEmpty ? '网易云用户' : nickname,
    avatarUrl: _pic(_str(profile['avatarUrl'])),
    isVip: _int(profile['vipType']) > 0,
  );
}

// ── H 组：账号档案 / 会员（2026-10-08 探针实测） ─────────────

/// H6：`/api/v1/user/detail/{uid}` → [NeteaseUserDetail]。
///
/// 响应结构：顶层 `level` / `listenSongs` / `userPoint` / `mobileSign` /
/// `pcSign`，`profile` 里是身份与社交数。`profile` 缺失时退化成只有
/// 顶层字段（游客/异常态），不抛。
NeteaseUserDetail mapNeteaseUserDetail(String raw) {
  final root = _decode(raw);
  if (_int(root['code']) != 200) {
    throw mapNeteaseCode(_int(root['code']), message: '用户详情 code 异常');
  }
  final profile = _asMap(root['profile']);
  final point = _asMap(root['userPoint']);
  return NeteaseUserDetail(
    // 用 _str 而非 _int：缺键时得空串而不是 '0'。
    userId: _str(profile['userId']),
    nickname: _str(profile['nickname']),
    avatarUrl: _pic(_str(profile['avatarUrl'])),
    backgroundUrl: _pic(_str(profile['backgroundUrl'])),
    signature: _str(profile['signature']),
    description: _str(profile['description']),
    level: _int(root['level']) != 0
        ? _int(root['level'])
        : _int(profile['level']),
    listenSongs: _int(root['listenSongs']),
    follows: _int(profile['follows']),
    followeds: _int(profile['followeds']),
    playlistCount: _int(profile['playlistCount']),
    cloudBeanBalance: _int(point['balance']),
    createTime: _positiveOrNull(_int(profile['createTime'])),
    gender: _int(profile['gender']),
    provinceCode: _str(profile['province']),
    cityCode: _str(profile['city']),
  );
}

/// H1：`/api/music-vip-membership/front/vip/info` → [NeteaseVipInfo]。
///
/// 四条会员都是同名结构（`vipCode` / `expireTime` / `vipLevel` / `isSign*`），
/// 用 [_vipMembership] 统一解；缺键或 `vipCode==0` 返回 null（未开通）。
NeteaseVipInfo mapNeteaseVipInfo(String raw) {
  final root = _decode(raw);
  if (_int(root['code']) != 200) {
    throw mapNeteaseCode(_int(root['code']), message: 'VIP 信息 code 异常');
  }
  final data = _asMap(root['data']);
  return NeteaseVipInfo(
    level: _int(data['redVipLevel']),
    levelIconUrl: _str(data['redVipLevelIcon']),
    annualCount: _int(data['redVipAnnualCount']),
    heijiao: _vipMembership(data['associator']),
    musicPackage: _vipMembership(data['musicPackage']),
    redplus: _vipMembership(data['redplus']),
    familyVip: _vipMembership(data['familyVip']),
  );
}

/// H2：`/api/user/level` → [NeteaseLevelInfo]。
///
/// `progress` 服务端已算成 0–1 比值，钳到 [0,1] 防脏值；
/// `info` 是 `$` 分隔的权益串，拆成列表（空段丢弃）。
NeteaseLevelInfo mapNeteaseUserLevel(String raw) {
  final root = _decode(raw);
  if (_int(root['code']) != 200) {
    throw mapNeteaseCode(_int(root['code']), message: '用户等级 code 异常');
  }
  final data = _asMap(root['data']);
  final progress = _double(data['progress']).clamp(0.0, 1.0);
  return NeteaseLevelInfo(
    level: _int(data['level']),
    progress: progress.isFinite ? progress : 0,
    nowPlayCount: _int(data['nowPlayCount']),
    nextPlayCount: _int(data['nextPlayCount']),
    nowLoginCount: _int(data['nowLoginCount']),
    nextLoginCount: _int(data['nextLoginCount']),
    privileges: _str(data['info'])
        .split('\$')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(),
  );
}

/// 一条会员记录；非 Map 或 `vipCode==0`（未开通）返回 null。
NeteaseVipMembership? _vipMembership(Object? node) {
  if (node is! Map) return null;
  final m = _asMap(node);
  final code = _int(m['vipCode']);
  if (code <= 0) return null;
  return NeteaseVipMembership(
    vipCode: code,
    expireTime: _positiveOrNull(_int(m['expireTime'])),
    vipLevel: _int(m['vipLevel']),
    // isSign / isSignIap / isSignDeduct / isSignIapDeduct 任一为真即续费中。
    isAutoRenew: m['isSign'] == true ||
        m['isSignIap'] == true ||
        m['isSignDeduct'] == true ||
        m['isSignIapDeduct'] == true,
  );
}

/// 非正数 → null（网易用 `0` / 负值表示「无此项」，如 `birthday=-2209017600000`）。
int? _positiveOrNull(int v) => v > 0 ? v : null;

// ── J. 音乐云盘 ──────────────────────────────────────────────
//
// 协议面来自 api-enhanced `module/user_cloud*.js` / `cloud*.js`（2026-10-09 接）。
// 字段形态来自 2026-10-09 真机探针（uid=1593114455：460 个文件 / 19.3G of 60G）。

/// J1 云盘列表 → [CloudDiskPage]。
///
/// 实测两点关键形态：
/// 1. **`data[]` 是 `{simpleSong: {...}}` 包裹**（2026-10-09 实测，与详情口同形），
///    由 [mapNeteaseSong] 拆包后与曲库歌曲同构——云盘页能显示正规歌名/歌手/专辑/
///    时长/封面，不必为了展示先打详情。未匹配曲库的文件（`ar`/`al` 为空）也有
///    `name`（= 文件名），不会出现空白行。
/// 2. **容量在顶层**：`size`（已用字节）/ `maxSize`（总额字节），故容量条可直接做。
///
/// 云盘文件自己的字段（`fileName`/`fileSize`/`addTime`/`cover`/`lyricId`/
/// `matchType`）**不在列表口**，只在 J2 详情口；产品侧当前不消费，故本 mapper
/// 不解析详情（要显示「上传时间/文件大小」时再补批量详情）。
///
/// 分页：`limit`/`offset` 是否生效待二轮探针确认，故 [CloudDiskPage.hasMore]
/// 以响应自带的 `hasMore` 为准——limit 被忽略时首屏即返回全量、`hasMore=false`，
/// 两种形态下都不会漏数据也不会翻过头。
CloudDiskPage mapNeteaseCloudPage(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '云盘');
  // `cloudFileId` 记 songId：它是 `isCloudTrack` 的判据，也是删除 / 取流 / 歌词
  // 三处的身份键（网易云盘没有酷狗那种 kv_id + hash 双键）。
  final tracks = [
    for (final t in mapNeteaseSongs(root['data'])) t.copyWith(cloudFileId: t.id),
  ];
  final total = _int(root['count']);
  return CloudDiskPage(
    tracks: tracks,
    total: total > 0 ? total : tracks.length,
    capacity: CloudDiskCapacity(
      usedBytes: _int(root['size']),
      totalBytes: _int(root['maxSize']),
    ),
    page: 1,
    hasMore: root['hasMore'] == true,
  );
}

/// J4 云盘取流 → [PlayUrlResult]。
///
/// **响应是平铺的**（2026-10-09 实测）：`{code, size, name, url}` 全在顶层，
/// 不是曲库那套 `data[0].url` 包裹。URL 是 `http://m803.music.126.net/...` 带
/// `vuutv` 时效签名的直链，和曲库取流一样短时有效，故照旧下发防盗链头。
PlayUrlResult mapNeteaseCloudPlayUrl(String raw) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code == 301) throw const LoginRequired('网易云会话失效 code=301');
  if (code != 200) throw mapNeteaseCode(code, message: '云盘取流 code=$code');
  final url = _str(root['url']);
  if (url.isEmpty) throw const NotFound('云盘文件没有取流地址');
  return PlayUrlResult(
    url: url,
    backupUrls: const [],
    headers: neteasePlaybackHeaders,
    isPreviewClip: false,
  );
}

/// J5 云盘歌词 → [LyricPayload]。
///
/// 歌词来自**文件里的 `LYRICS` 标签**（不是曲库歌词口），响应是**顶层字符串**
/// `{lrc, krc}`（2026-10-09 实测；注意与曲库那套 `lrc:{version,lyric}` 对象不同）。
/// 两者皆空 = 该文件没内嵌歌词，**口是通的**，返回 [LyricPayload.empty] 而非抛错。
///
/// `krc` 的格式未实测（盘里没带歌词的文件），故先按 YRC 解、解不出来按 LRC 解，
/// 两种格式都不会把内容丢掉。
LyricPayload mapNeteaseCloudLyric(String raw) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code != 0 && code != 200) {
    throw mapNeteaseCode(code, message: '云盘歌词 code=$code');
  }
  final krc = _str(root['krc']);
  final lrc = _str(root['lrc']);
  var lines = const <LyricLine>[];
  var fromKrc = false;
  if (krc.isNotEmpty) {
    lines = parseYrc(krc);
    fromKrc = lines.isNotEmpty;
  }
  if (lines.isEmpty && krc.isNotEmpty) lines = parseLrc(krc);
  if (lines.isEmpty && lrc.isNotEmpty) lines = parseLrc(lrc);
  if (lines.isEmpty) return LyricPayload.empty;
  return LyricPayload(
    lines: lines,
    sourceTag: fromKrc ? 'netease-cloud-krc' : 'netease-cloud-lrc',
  );
}

/// J2 云盘详情：`data[]` 每项 `{simpleSong, songId, fileName, fileSize, addTime,
/// cover, coverId, lyricId, matchType, bitrate, album, artist, ...}`。
///
/// 列表口给不到这些，故「上传时间 / 文件大小 / 文件名」要展示时再调它
/// （按 songId 与列表项对齐，可批量）。当前产品不消费，先只做探针摘要用。
List<Track> mapNeteaseCloudDetails(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '云盘详情');
  final data = root['data'];
  if (data is! List) return const [];
  final out = <Track>[];
  for (final node in data) {
    if (node is! Map) continue;
    final song = node['simpleSong'];
    final track = mapNeteaseSong(song is Map ? song : node);
    if (track == null) continue;
    out.add(track.copyWith(cloudFileId: _str(node['songId'])));
  }
  return out;
}

// ── 内部工具 ─────────────────────────────────────────────────

/// 写操作（加曲/删曲/喜欢）响应校验：`code==200` 或 `status==1` 视为成功。
///
/// 写口响应形态不统一（有的只给 `status`），故两者都认；都没有则按失败抛。
void throwIfNeteaseWriteFailed(String raw, String label) {
  final root = _decode(raw);
  final code = _int(root['code']);
  if (code == 200) return;
  if (code == 0 && _int(root['status']) == 1) return;
  throw mapNeteaseCode(
    code == 0 ? null : code,
    message: '$label 失败 code=$code',
  );
}

Map<String, dynamic> _decode(String raw) {
  try {
    final data = jsonDecode(raw);
    if (data is Map) return Map<String, dynamic>.from(data);
  } catch (_) {
    // 落到下面的统一错误。
  }
  throw const UpstreamChanged('网易云响应不是 JSON');
}

void _throwIfBadCode(Map<String, dynamic> root, String label) {
  final code = _int(root['code']);
  if (code != 0 && code != 200) {
    throw mapNeteaseCode(code, message: '$label code=$code');
  }
}

String _lyricText(Object? node) {
  final map = _asMap(node);
  final lyric = map['lyric'];
  return lyric is String ? lyric : '';
}

/// LRC 文本 → `时间戳(ms) → 文本`（空行丢弃）。
Map<int, String> _timedTexts(String raw) {
  if (raw.trim().isEmpty) return const {};
  final out = <int, String>{};
  for (final line in parseLrc(raw)) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    out[line.timeMs] = text;
  }
  return out;
}

/// 取与 [timeMs] 对齐的副行文本；无精确对齐时容忍 ±100ms。
String? _nearestText(Map<int, String> map, int timeMs) {
  if (map.isEmpty) return null;
  final exact = map[timeMs];
  if (exact != null) return exact;
  String? best;
  var bestDiff = 101;
  for (final e in map.entries) {
    final diff = (e.key - timeMs).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = e.value;
    }
  }
  return best;
}

({List<String> names, String firstId}) _artists(Map<String, dynamic> m) {
  final raw = m['ar'] ?? m['artists'];
  final names = <String>[];
  var firstId = '';
  if (raw is List) {
    for (final a in raw) {
      if (a is! Map) continue;
      final name = _str(a['name']);
      if (name.isNotEmpty) names.add(name);
      if (firstId.isEmpty && _int(a['id']) > 0) firstId = '${_int(a['id'])}';
    }
  }
  // 老口兜底：album.artist / 单 artist 对象。
  if (names.isEmpty) {
    final album = _asMap(m['album'] ?? m['al']);
    final nested = album['artist'] ?? m['artist'];
    if (nested is Map) {
      final name = _str(nested['name']);
      if (name.isNotEmpty) names.add(name);
      if (firstId.isEmpty && _int(nested['id']) > 0) {
        firstId = '${_int(nested['id'])}';
      }
    }
  }
  return (names: names, firstId: firstId);
}

/// `privilege.pl`（可播最高码率）→ 已知可播音质。空集合 = 未知。
Set<AppQuality> _qualitiesFromPrivilege(Map<String, dynamic> privilege) {
  if (privilege.isEmpty) return const {};
  final br = _int(privilege['pl']) > 0
      ? _int(privilege['pl'])
      : _int(privilege['playMaxbr']);
  if (br <= 0) return const {};
  return {
    AppQuality.standard,
    if (br >= 300000) AppQuality.hq,
    if (br >= 900000) AppQuality.sq,
    if (br >= 1500000) AppQuality.hiRes,
  };
}

String _qualityToken(Set<AppQuality> qualities) {
  if (qualities.isEmpty) return '';
  if (qualities.contains(AppQuality.hiRes)) return 'Hi-Res';
  if (qualities.contains(AppQuality.sq)) return 'SQ';
  if (qualities.contains(AppQuality.hq)) return 'HQ';
  return '';
}

String _pic(String raw) {
  var url = raw.trim();
  if (url.isEmpty || url == 'null') return '';
  if (url.startsWith('//')) url = 'https:$url';
  return url.replaceFirst('http://', 'https://');
}

/// 专辑节点封面。
///
/// 新口（详情/云搜索）给 `al.picUrl`；**旧搜索口 `search/get` 只给
/// `album.picId`**（实测 2026-09-25：`album` 键为
/// `publishTime,size,artist,copyrightId,name,id,picId,mark,status`），
/// 此时按官方算法拼 CDN 直链，否则封面会退化成空串（列表显示灰块）。
String _albumCover(Map<String, dynamic> album) {
  final url = _pic(_str(
    album['picUrl'] ??
        album['blurPicUrl'] ??
        album['coverImgUrl'] ??
        album['albumPic'],
  ));
  if (url.isNotEmpty) return url;
  return NeteaseCrypto.picUrl(_int(album['picId']));
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

/// 宽松转 double（`progress` 可能是 `0.242` 也可能是字符串 `"0.242"`）；
/// 解析不了返回 0，由调用方钳范围。
double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.trim()) ?? 0;
}

String _str(Object? value) {
  final s = '${value ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

// ── N1 评论（E1 列表 / E2 楼层） ──────────────────────────────

/// 网易评论档位（`sortType` 值 → 展示名）。
///
/// 档位本该由响应的 `sortTypeList` 给出，但 [CommentReadSource.commentSortOptions]
/// 是**同步** getter（首屏前还没请求过），故这里先给一份实测默认值，
/// 拿到响应后用服务端档位覆盖（见 [mapNeteaseComments] 的 `sorts`）。
///
/// ⚠️ `sortType=1` 只是服务端给的展示序，**发出去必须转成 `99`**
/// （`NeteaseClient.commentListRaw` 有同样一句注释）。
const List<({String id, String label})> neteaseDefaultCommentSorts = [
  (id: '99', label: '推荐'),
  (id: '2', label: '最热'),
  (id: '3', label: '最新'),
];

/// E1 评论列表 → 一页评论 + 服务端档位。
///
/// ⚠️ **新口是 `data` 包裹**（`data.comments` / `data.totalCount` /
/// `data.hasMore` / `data.sortTypeList`）—— 老口才是顶层平铺，按错的那套读
/// 会拿到「空列表」而误判成接口不可用。
///
/// `nextCursor` **直接取服务端的 `data.cursor`**（2026-09-27 连翻 3 页实测：
/// 三档零重复、能收敛）。
///
/// ⚠️ 不要自己按 `pageNo * pageSize` 拼 offset —— 实测**响应条数不受 `pageSize`
/// 控制**（要 20 时推荐档给 26、时间档给 18、热度档给 20），且热度档的
/// cursor 是 `normalHot#20 → #40 → #110` 这种服务端自算的跳跃序列，
/// 拼出来的 offset 会错位。早前文档 §3.2 那句「响应 cursor 不等于下一页要传的」
/// 已被本次实测推翻，以代码注释为准。
({
  CommentPage page,
  List<({String id, String label})> sorts,
}) mapNeteaseComments(
  String raw, {
  required String threadId,
}) {
  final root = _decode(raw);
  _throwIfBadCode(root, '评论');
  final data = _asMap(root['data']);
  final comments = data['comments'];

  final items = <Comment>[];
  if (comments is List) {
    for (final node in comments) {
      final c = mapNeteaseComment(node);
      if (c != null) items.add(c);
    }
  }

  final hasMore = data['hasMore'] == true;
  final nextCursor = hasMore ? _str(data['cursor']) : '';

  return (
    page: CommentPage(
      items: items,
      total: _int(data['totalCount']),
      // 网易的评论池就是 threadId 本身（可从 Track 重算）—— 填它是为了让
      // 楼层 / 写侧有统一的取值路径，UI 不解读它的含义（酷狗那个是不透明 token）。
      childrenId: threadId,
      maxPage: 0, // 页码式字段，网易不用（分页靠 nextCursor）
      nextCursor: nextCursor,
    ),
    sorts: _neteaseSorts(data['sortTypeList']),
  );
}

/// N3 热搜：词在 **`result.hots[].first`** —— 网易的**第三套包裹**
/// （列表口是 `data` 包裹、老评论口是顶层平铺、热搜是 `result.hots`），
/// 别按惯性去 `data` 下找。
///
/// 实测只有 **10 条、无分页**；`second` 恒为 `1`、`third` 恒为 `null`
/// （含义不明），**没有热度值** —— 所以只回词，不编造热度。
List<String> mapNeteaseSearchHot(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '热搜');
  final hots = _asMap(root['result'])['hots'];
  if (hots is! List) return const [];
  final out = <String>[];
  for (final e in hots) {
    if (e is! Map) continue;
    final word = _str(e['first']);
    if (word.isNotEmpty) out.add(word);
  }
  return out;
}

/// E2 楼层：数据在 **`data.comments`**（不是顶层 `comments`）。
///
/// `data.ownerComment` 是父评论本身（不必再查一次），这里不返回
/// —— 调用方（UI）手上已经有那条父评论。
List<Comment> mapNeteaseFloorComments(String raw) {
  final root = _decode(raw);
  _throwIfBadCode(root, '楼层评论');
  return _mapNodes(_asMap(root['data'])['comments'], mapNeteaseComment);
}

/// 一条评论节点 → [Comment]；`commentId` 缺失视为无效。
Comment? mapNeteaseComment(Object? node) {
  if (node is! Map) return null;
  final m = Map<String, dynamic>.from(node);
  final id = _int(m['commentId']);
  if (id <= 0) return null;
  final user = _asMap(m['user']);
  final floor = _asMap(m['showFloorComment']);
  final replyCount = _int(m['replyCount']);
  return Comment(
    id: '$id',
    user: _str(user['nickname']),
    userId: _idOrEmpty(user['userId']),
    content: _str(m['content']),
    likeCount: _int(m['likedCount']),
    avatarUrl: _pic(_str(user['avatarUrl'])),
    // `timeStr` 已经是「9分钟前」「2024-12-08」这类可读文本，不要再格式化。
    timeLabel: _str(m['timeStr']),
    // 楼层数：正文没给就退回 `showFloorComment.replyCount`。
    replyCount: replyCount > 0 ? replyCount : _int(floor['replyCount']),
    location: _str(_asMap(m['ipLocation'])['location']),
    badges: _neteaseBadges(user, m),
    // 当前用户是否已赞（酷狗不给此字段，那边恒 false）。
    liked: m['liked'] == true,
  );
}

/// 网易铭牌判定 —— **另起一套，不复用酷狗的 `_plateId` 判定链**（字段语义
/// 完全不同：酷狗是 `vip_type`/`m_type`/`y_type` 组合，网易是
/// `vipType` / `authStatus` / `expertTags`）。
List<CommentBadge> _neteaseBadges(
  Map<String, dynamic> user,
  Map<String, dynamic> comment,
) {
  final out = <CommentBadge>[];
  if (_int(user['vipType']) > 0) {
    out.add(const CommentBadge(kind: 'vip', label: 'VIP'));
  }
  if (_int(user['authStatus']) > 0) {
    out.add(const CommentBadge(kind: 'music', label: '音乐人'));
  }
  final expert = user['expertTags'];
  if (expert is List && expert.isNotEmpty) {
    out.add(CommentBadge(kind: 'expert', label: _str(expert.first)));
  }
  if (_int(_asMap(comment['decoration'])['repliedByAuthorCount']) > 0) {
    out.add(const CommentBadge(kind: 'author', label: '作者回复'));
  }
  return out;
}

/// `sortTypeList` → 档位选项；`sortType=1` 归一化为 `99`。
/// 服务端没给（或全无效）时回落到 [neteaseDefaultCommentSorts]。
List<({String id, String label})> _neteaseSorts(Object? raw) {
  if (raw is! List) return neteaseDefaultCommentSorts;
  final out = <({String id, String label})>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = _asMap(e);
    var type = _int(m['sortType']);
    if (type == 1) type = 99;
    if (type <= 0) continue;
    final name = _str(m['sortTypeName']);
    if (name.isEmpty) continue;
    out.add((id: '$type', label: name));
  }
  return out.isEmpty ? neteaseDefaultCommentSorts : out;
}

String _idOrEmpty(Object? value) {
  final id = _int(value);
  return id > 0 ? '$id' : '';
}
