import 'dart:convert';

import '../../models/audio_quality.dart';
import '../../models/search_result.dart';
import '../../models/track.dart';
import '../../source/capabilities.dart';
import '../../source/music_platform.dart';
import '../../source/music_source.dart';
import '../../utils/lrc_parser.dart';
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

/// 搜索专辑节点 → [AlbumBrief]；`id` 非数字视为无效。
AlbumBrief? mapNeteaseAlbumBrief(Object? node) {
  if (node is! Map) return null;
  final m = Map<String, dynamic>.from(node);
  final id = _int(m['id']);
  if (id <= 0) return null;
  final artists = _artists(m);
  return AlbumBrief(
    id: '$id',
    name: _str(m['name'] ?? m['albumName']),
    coverUrl: _pic(_str(
      m['picUrl'] ?? m['blurPicUrl'] ?? m['coverImgUrl'] ?? m['albumPic'],
    )),
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

/// 歌单元数据（榜单封面用）：`playlist.name / coverImgUrl / trackCount`。
({String name, String coverUrl, int trackCount}) mapNeteasePlaylistMeta(
  String raw,
) {
  final root = _decode(raw);
  final playlist = _asMap(root['playlist']);
  return (
    name: _str(playlist['name']),
    coverUrl: _pic(_str(playlist['coverImgUrl'] ?? playlist['picUrl'])),
    trackCount: _int(playlist['trackCount']),
  );
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
Track? mapNeteaseSong(Object? node) {
  if (node is! Map) return null;
  var m = Map<String, dynamic>.from(node);
  // G5 新歌等把曲目塞在 `song` 里。
  final nested = m['song'];
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
  final url = _pic(_str(album['picUrl'] ?? album['blurPicUrl']));
  if (url.isNotEmpty) return url;
  return NeteaseCrypto.picUrl(_int(album['picId']));
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

String _str(Object? value) {
  final s = '${value ?? ''}'.trim();
  return s == 'null' ? '' : s;
}
