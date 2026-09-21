import '../models/audio_quality.dart';
import '../models/search_result.dart';
import '../models/track.dart';

String _s(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? fallback : t;
}

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(_s(v)) ?? 0;
}

int _i2(Object? a, Object? b) {
  final x = _i(a);
  return x != 0 ? x : _i(b);
}

/// EchoMusic-style cover normalization: `{size}` → 400, http→https, old CDN host swap.
String normalizeCoverUrl(String raw, {String size = '400'}) {
  var cover = raw.trim();
  if (cover.isEmpty || cover == 'mock://cover') return '';
  if (cover.startsWith('//')) cover = 'https:$cover';
  cover = cover.replaceAll('{size}', size);
  cover = cover.replaceFirst('http://', 'https://');
  cover = cover.replaceFirst('c1.kgimg.com', 'imge.kugou.com');
  if (cover.startsWith('https://')) return cover;
  if (cover.startsWith('http://')) return cover;
  // Bare hash / relative path → soft collection CDN
  final f = cover.toLowerCase();
  return 'https://imge.kugou.com/soft/collection/$size/$f';
}

String kugouCover(String? hashOrFile, {String size = '400'}) {
  return normalizeCoverUrl(_s(hashOrFile), size: size);
}

String _pickCover(Map<String, dynamic> json) {
  final trans = json['trans_param'];
  final transMap = trans is Map ? Map<String, dynamic>.from(trans) : const <String, dynamic>{};
  final albumInfo = json['album_info'] is Map
      ? Map<String, dynamic>.from(json['album_info'] as Map)
      : const <String, dynamic>{};
  final candidates = <String>[
    _s(json['album_sizable_cover']),
    _s(json['sizable_cover']),
    _s(albumInfo['sizable_cover']),
    _s(json['cover']),
    _s(json['pic']),
    _s(json['img']),
    _s(json['imgurl']),
    _s(transMap['union_cover']),
  ];
  for (final c in candidates) {
    if (c.isNotEmpty) return c;
  }
  return '';
}

/// Pull the primary singer id out of a song payload.
///
/// Search/album/special responses differ: search gives `singers[].id` or
/// `AuthorId`/`singerid`, while `special/song` gives only `filename`
/// (`周杰伦 - 晴天`) with no id at all. Returns `''` when unknown — callers
/// must not fabricate a numeric fallback.
String _pickArtistId(Map<String, dynamic> json) {
  final singers = json['singers'] ?? json['Singers'] ?? json['authors'];
  if (singers is List) {
    for (final e in singers) {
      if (e is Map) {
        final id = _s(
          e['id'],
          _s(
            e['author_id'],
            _s(e['AuthorId'], _s(e['singerid'], _s(e['singer_id']))),
          ),
        );
        if (id.isNotEmpty) return id;
      }
    }
  }
  return _s(
    json['AuthorId'],
    _s(json['author_id'],
        _s(json['singerid'], _s(json['singer_id'], _s(json['authorid'])))),
  );
}

/// Cleans common audio container extensions from song titles or artist names.
String cleanupAudioExtension(String value) {
  var output = value.trim();
  const extensions = [
    '.mp3',
    '.flac',
    '.wav',
    '.aac',
    '.m4a',
    '.ape',
    '.ogg',
    '.wma',
  ];
  final lower = output.toLowerCase();
  for (final ext in extensions) {
    if (lower.endsWith(ext)) {
      output = output.substring(0, output.length - ext.length).trim();
      break;
    }
  }
  return output;
}

/// Strips "Artist - " prefix if raw title is composite.
String processSongTitle(String rawTitle) {
  final clean = cleanupAudioExtension(rawTitle);
  final idx = clean.indexOf(' - ');
  if (idx > 0) {
    return clean.substring(idx + 3).trim();
  }
  return clean;
}

/// Split a kugou `filename` (`周杰伦 - 晴天`) into (artist, title).
/// Returns `(null, filename)` when there is no ` - ` separator.
({String? artist, String title}) _splitFilename(String filename) {
  final clean = cleanupAudioExtension(filename);
  final idx = clean.indexOf(' - ');
  if (idx <= 0) return (artist: null, title: clean);
  return (
    artist: clean.substring(0, idx).trim(),
    title: clean.substring(idx + 3).trim(),
  );
}

Track mapMobileSearchSong(Map<String, dynamic> json) {
  final audioInfo = json['audio_info'] is Map
      ? Map<String, dynamic>.from(json['audio_info'] as Map)
      : const <String, dynamic>{};
  final albumInfo = json['album_info'] is Map
      ? Map<String, dynamic>.from(json['album_info'] as Map)
      : const <String, dynamic>{};
  // rank/audio nests playable hashes under audio_info; search often has flat hash.
  final hash = _s(
    json['hash'],
    _s(
      audioInfo['hash'],
      _s(
        audioInfo['hash_320'],
        _s(audioInfo['hash_128'], _s(audioInfo['hash_flac'])),
      ),
    ),
  ).toLowerCase();
  final id = _s(
    json['audio_id'],
    _s(
      json['mixsongid'],
      _s(
        json['album_audio_id'],
        _s(json['fileid'], _s(audioInfo['audio_id'], hash)),
      ),
    ),
  );
  final filename = _s(json['filename'], _s(audioInfo['filename']));
  final split = filename.isEmpty
      ? (artist: null, title: '')
      : _splitFilename(filename);

  // Extract song title:
  // If `songname` exists and is clean, use it.
  // Otherwise fall back to name, audio_name, filename and strip "Artist - " if needed.
  var cleanSongName = cleanupAudioExtension(_s(
    json['songname'],
    _s(json['song_name'], _s(audioInfo['songname'])),
  ));
  if (cleanSongName.isEmpty) {
    final fallbackName = _s(
      json['name'],
      _s(
        json['audio_name'],
        _s(
          json['ori_audio_name'],
          _s(
            json['filename'],
            _s(audioInfo['name'], _s(audioInfo['filename'], _s(split.title, '未知歌曲'))),
          ),
        ),
      ),
    );
    cleanSongName = processSongTitle(fallbackName);
  } else if (cleanSongName.contains(' - ')) {
    cleanSongName = processSongTitle(cleanSongName);
  }
  cleanSongName = cleanupAudioExtension(cleanSongName);
  final name = cleanSongName.isEmpty ? '未知歌曲' : cleanSongName;

  // Extract artist name:
  // Rank/song uses `authors[]`; search uses `singername` / `singer`; cloud uses `author_name`.
  final singers = json['singername'] ??
      json['singer'] ??
      json['authors'] ??
      json['singers'] ??
      json['author_name'] ??
      audioInfo['author_name'] ??
      audioInfo['singername'] ??
      audioInfo['singer'] ??
      audioInfo['authors'] ??
      audioInfo['singers'];
  var artist = '';
  if (singers is List) {
    artist = singers
        .map((e) {
          if (e is Map) {
            return _s(e['name'] ?? e['author_name'] ?? e['singername'] ?? e['singer']);
          }
          return _s(e);
        })
        .where((s) => s.isNotEmpty)
        .join('/');
  } else {
    artist = _s(singers);
  }

  // If artist is still empty, extract from composite raw title (e.g. "老王乐队 - 我还年轻", "麋先生 - 坏蛋.mp3")
  if (artist.isEmpty) {
    final rawCandidate = _s(
      json['name'],
      _s(
        json['filename'],
        _s(
          json['audio_name'],
          _s(
            json['ori_audio_name'],
            _s(
              json['songname'],
              _s(audioInfo['filename'], _s(audioInfo['name'], _s(audioInfo['songname']))),
            ),
          ),
        ),
      ),
    );
    final cleanCandidate = cleanupAudioExtension(rawCandidate);
    final idx = cleanCandidate.indexOf(' - ');
    if (idx > 0) {
      artist = cleanCandidate.substring(0, idx).trim();
    }
  }

  if (artist.isEmpty) artist = split.artist ?? '';
  artist = cleanupAudioExtension(artist);
  if (artist.isEmpty) artist = '未知歌手';

  final artistId = _pickArtistId(json);
  var duration = _i(json['duration']) * 1000;
  if (duration == 0) {
    final rawLen = _i2(json['timelen'], json['time_length']);
    final len = rawLen != 0
        ? rawLen
        : _i2(
            audioInfo['duration_320'],
            _i2(
              audioInfo['duration_128'],
              _i2(audioInfo['duration'], audioInfo['timelen']),
            ),
          );
    duration = len > 10000 ? len : len * 1000;
  }
  final albumId = _s(json['album_id'], _s(audioInfo['album_id']));
  final albumName = cleanupAudioExtension(_s(
    json['album_name'],
    _s(
      json['albumname'],
      _s(
        albumInfo['album_name'],
        _s(audioInfo['album_name'], _s(audioInfo['albumname'])),
      ),
    ),
  ));
  final coverRaw = _pickCover(json);
  final goods = AudioQualityUtil.buildRelateGoods(json);
  final available = AudioQualityUtil.availableFromGoods(goods);
  // Mobile search: hash + 320hash + sqhash + privilege/pay_type flags.
  if (available.isEmpty && hash.isNotEmpty) {
    available.add(AppQuality.standard);
  }
  final catalogComplete =
      json.containsKey('relate_goods') || json.containsKey('relateGoods');
  final isVip = _isVipFromJson(json);
  final highest = available.isEmpty
      ? null
      : (available.contains(AppQuality.hiRes)
          ? 'Hi-Res'
          : available.contains(AppQuality.sq)
              ? 'SQ'
              : available.contains(AppQuality.hq)
                  ? 'HQ'
                  : 'SD');

  return Track(
    id: id.isEmpty ? hash : id,
    name: name,
    artist: artist.isEmpty ? '未知歌手' : artist,
    album: albumName,
    coverUrl: normalizeCoverUrl(coverRaw.isEmpty ? hash : coverRaw),
    durationMs: duration,
    hash: hash,
    albumId: albumId,
    // Comments/play prefer album_audio_id; search often omits mixsongid.
    mixSongId: _s(
      json['mixsongid'],
      _s(json['album_audio_id'], _s(json['audio_id'], id)),
    ),
    quality: highest ?? _s(json['quality'], 'SQ'),
    isVip: isVip,
    artistId: artistId,
    availableQualities: available.isEmpty ? const {} : Set.of(available),
    relateGoods: goods,
    qualityCatalogComplete: catalogComplete,
  );
}

bool _isVipFromJson(Map<String, dynamic> json) {
  final privilege = json['privilege'];
  if (privilege is Map) {
    return _i(privilege['vip_type']) > 0 || _i(privilege['privilege']) >= 10;
  }
  final p = _i(privilege);
  if (p >= 10) return true;
  // EchoMusic: privilege===10 && payType===3 → VIP paid.
  final payType = _i(json['pay_type'] ?? json['payType']);
  return payType == 3 && p > 0;
}

/// Maps a playlist/`special` payload into [PlaylistBrief].
///
/// `id` must stay the **numeric `specialid`** — that is what
/// `fetchPlaylist` forwards (it strips non-digits and sends `specialid`).
/// `global_collection_id` looks like `collection_3_509005046_32_0`, and
/// stripping its non-digits yields a *different*, wrong id, so prefer the
/// numeric field when the payload offers one.
PlaylistBrief mapPlaylistInfo(Map<String, dynamic> json) {
  final numeric = _s(json['specialid'], _s(json['listid']));
  final fallback = _s(json['global_collection_id'], _s(json['id']));
  final id = numeric.isNotEmpty ? numeric : fallback;
  final name = _s(
    json['name'],
    _s(json['specialname'], _s(json['rankname'], '歌单')),
  );
  final pic = _pickCover(json);
  final cover = normalizeCoverUrl(pic.isEmpty ? id : pic);
  final count = _i2(json['songcount'], json['song_count']);
  final intro = _s(json['intro'], _s(json['info']));
  final play = _i2(json['playcount'], json['listen_num']);
  final creator = _s(json['nickname'], _s(json['username'], _s(json['creator'])));
  return PlaylistBrief(
    id: id,
    name: name,
    coverUrl: cover,
    description: intro,
    creator: creator,
    trackCount: count,
    playCountLabel: play > 0 ? formatCount(play) : '',
  );
}

/// Maps `/api/v3/rank/list` / `rank/info` items into [PlaylistBrief].
///
/// `id` must be **`rankid`** — `rank/song` and `rank/info` only accept that
/// (not `specialid`, not `rank_cid`).
PlaylistBrief mapRankBrief(Map<String, dynamic> json) {
  final rankId = _s(json['rankid'], _s(json['rank_id'], _s(json['id'])));
  final name = _s(json['rankname'], _s(json['name'], '榜单'));
  final pic = _s(
    json['imgurl'],
    _s(
      json['img_cover'],
      _s(json['bannerurl'], _s(json['img_9'], _s(json['banner_9']))),
    ),
  );
  final cover = normalizeCoverUrl(pic.isEmpty ? rankId : pic);
  final play = _i2(json['play_times'], json['listen_num']);
  final intro = _s(json['intro']);
  // rank/list keeps the real board size under extra.resp.all_total (TOP500→500);
  // the public rank/song `total` is often a degraded slice and must not win.
  final extra = json['extra'];
  final extraMap =
      extra is Map ? Map<String, dynamic>.from(extra) : const <String, dynamic>{};
  final resp = extraMap['resp'] is Map
      ? Map<String, dynamic>.from(extraMap['resp'] as Map)
      : const <String, dynamic>{};
  final count = _i2(
    json['all_total'],
    _i2(resp['all_total'], _i2(json['song_count'], json['total'])),
  );
  return PlaylistBrief(
    id: rankId,
    name: name,
    coverUrl: cover,
    description: intro,
    creator: '酷狗官方',
    trackCount: count,
    playCountLabel: play > 0 ? formatCount(play) : '',
    isRank: true,
  );
}

/// KuGouMusicApi `POST /openapi/kmr/v2/rank/audio` → `data.songlist[]`.
///
/// Public `mobilecdn .../rank/song` often returns only a handful of rows even
/// when the board claims hundreds; the signed gateway path is what EchoMusic
/// uses for the full chart.
List<dynamic> extractRankAudioSongs(dynamic body) {
  final map =
      body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  final list = data['songlist'] ?? data['info'] ?? data['list'];
  return list is List ? list : const [];
}

/// Board size reported by `rank/audio` (`data.total`, also mirrored at root).
int extractRankAudioTotal(dynamic body) {
  final map =
      body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};
  final data = map['data'] is Map
      ? Map<String, dynamic>.from(map['data'] as Map)
      : map;
  return _i2(data['total'], map['total']);
}

/// Maps a `search/album` item.
AlbumBrief mapAlbumBrief(Map<String, dynamic> json) {
  final id = _s(json['albumid'], _s(json['album_id'], _s(json['id'])));
  final name = _s(json['albumname'], _s(json['album_name'], _s(json['name'], '专辑')));
  final rawCover = _s(json['imgurl'], _s(json['sizable_cover'], _s(json['cover'])));
  return AlbumBrief(
    id: id,
    name: name,
    coverUrl: normalizeCoverUrl(rawCover.isEmpty ? id : rawCover),
    artist: _s(json['singername'], _s(json['singer_name'], _s(json['author_name']))),
    trackCount: _i2(json['songcount'], json['song_count']),
    publishDate: _s(json['publishtime'], _s(json['publish_time'])).split(' ').first,
  );
}

/// Maps a `search/singer` item — the payload carries only id + name.
ArtistBrief mapArtistBrief(Map<String, dynamic> json) {
  return ArtistBrief(
    id: _s(json['singerid'], _s(json['singer_id'], _s(json['AuthorId']))),
    name: _s(
      json['singername'],
      _s(json['singer_name'], _s(json['AuthorName'], _s(json['name']))),
    ),
  );
}

String formatCount(int n) {
  if (n >= 100000000) {
    return '${(n / 100000000).toStringAsFixed(1)}亿';
  }
  if (n >= 10000) {
    return '${(n / 10000).toStringAsFixed(1)}万';
  }
  return '$n';
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

Object? _pick(List<Object?> values, List<String> keys) {
  // Key-major: first non-empty value for each key, across source priority.
  for (final key in keys) {
    for (final source in values) {
      if (source is! Map) continue;
      final map = Map<String, dynamic>.from(source);
      final v = map[key];
      if (v == null || v is Map || v is List) continue;
      final t = v.toString().trim();
      if (t.isEmpty || t == 'null') continue;
      return v;
    }
  }
  return null;
}

String _joinSingers(List<dynamic> singers) {
  return singers
      .map((e) {
        if (e is Map) return _s(e['name'] ?? e['singername'] ?? e['author_name']);
        return _s(e);
      })
      .where((s) => s.isNotEmpty)
      .join('/');
}

/// EchoMusic extractors.ts — everyday/recommend list shapes vary by platform.
List<dynamic> extractEverydayList(dynamic body) {
  if (body is List) return body;
  if (body is! Map) return const [];
  final map = Map<String, dynamic>.from(body);
  final data = _asMap(map['data']);
  final info = _asMap(map['info']);
  final songs = _asMap(data['songs']);
  final candidates = <Object?>[
    data['special_list'],
    data['list'],
    data['info'],
    data['song_list'],
    data['songlist'],
    data['songs'],
    songs['list'],
    songs['songs'],
    info['list'],
    info['songs'],
    info['songlist'],
    map['special_list'],
    map['list'],
    map['info'],
    map['song_list'],
    map['songlist'],
    map['songs'],
    map['data'],
  ];
  for (final candidate in candidates) {
    if (candidate is List) return candidate;
  }
  return const [];
}

/// Flatten everyday_song_recommend song objects (base/audio_info/…).
Track mapEverydaySong(Map<String, dynamic> json) {
  final base = _asMap(json['base']);
  final audioInfo = _asMap(json['audio_info']);
  final recInfo = _asMap(json['rec_song_info']);
  final albumInfo = _asMap(json['album_info'] ?? json['albuminfo']);
  final sources = <Object?>[json, base, audioInfo, recInfo, albumInfo];

  final hash = _s(
    _pick(sources, ['hash', 'hash_128', 'FileHash']),
  ).toLowerCase();
  final mixSongId = _s(
    _pick(sources, [
      'mixsongid',
      'MixSongID',
      'album_audio_id',
      'audio_id',
    ]),
  );
  final audioId = _s(_pick(sources, ['audio_id', 'songid', 'song_id']));

  String artist = _s(_pick(sources, [
    'author_name',
    'singername',
    'AuthorName',
  ]));
  if (artist.isEmpty) {
    for (final source in sources) {
      if (source is! Map) continue;
      final map = Map<String, dynamic>.from(source);
      // personal_recommend 用 singerinfo[]；搜索/每日推荐多用 singer/singers。
      final singers = map['singer'] ?? map['singers'] ?? map['singerinfo'];
      if (singers is List && singers.isNotEmpty) {
        artist = _joinSingers(singers);
        if (artist.isNotEmpty) break;
      }
    }
  }

  // Singer id for the artist-detail route; `''` when the payload omits it.
  String artistId = '';
  for (final source in sources) {
    if (source is! Map) continue;
    final map = Map<String, dynamic>.from(source);
    final candidate = _pickArtistId(map);
    if (candidate.isNotEmpty) {
      artistId = candidate;
      break;
    }
  }

  final rawName = processSongTitle(
    _s(
      _pick(sources, [
        'songname',
        'audio_name',
        'name',
        'filename',
      ]),
      '未知歌曲',
    ),
  );

  // personal_recommend 的 time_length 是秒；everyday 等常见毫秒。
  // <10000 视为秒（约 2.8 小时），≥10000 视为已是毫秒。
  var timeLength = _i(_pick(sources, ['time_length']));
  if (timeLength > 0 && timeLength < 10000) timeLength *= 1000;
  final durationRaw = timeLength != 0
      ? timeLength
      : _i(_pick(sources, ['timelength', 'duration']));
  // time_length 归一后是 ms；plain duration 通常是秒。
  final durationMs =
      timeLength != 0 || durationRaw > 10000 ? durationRaw : durationRaw * 1000;

  final isVip = _isVipFromJson(json);

  final coverRaw = _s(_pick(sources, [
    'album_sizable_cover',
    'sizable_cover',
    'cover',
    'pic',
    'img',
    'imgurl',
  ]));
  final trans = _asMap(json['trans_param']);
  final transCover = _s(trans['union_cover']);

  final goods = <RelateGood>[
    for (final src in sources)
      if (src is Map) ...AudioQualityUtil.buildRelateGoods(Map<String, dynamic>.from(src)),
  ];
  final available = AudioQualityUtil.availableFromGoods(goods);
  if (available.isEmpty && hash.isNotEmpty) available.add(AppQuality.standard);
  final highest = available.isEmpty
      ? null
      : (available.contains(AppQuality.hiRes)
          ? 'Hi-Res'
          : available.contains(AppQuality.sq)
              ? 'SQ'
              : available.contains(AppQuality.hq)
                  ? 'HQ'
                  : 'SD');

  return Track(
    id: mixSongId.isNotEmpty ? mixSongId : (audioId.isNotEmpty ? audioId : hash),
    name: rawName,
    artist: artist.isEmpty ? '未知歌手' : artist,
    album: _s(_pick(sources, ['album_name', 'albumname', 'AlbumName'])),
    coverUrl: normalizeCoverUrl(
      coverRaw.isNotEmpty
          ? coverRaw
          : (transCover.isNotEmpty ? transCover : hash),
    ),
    durationMs: durationMs,
    hash: hash,
    albumId: _s(_pick(sources, ['album_id', 'albumid', 'AlbumID'])),
    mixSongId: mixSongId.isNotEmpty
        ? mixSongId
        : _s(_pick(sources, ['audio_id', 'album_audio_id'])),
    quality: highest ?? 'SQ',
    isVip: isVip,
    artistId: artistId,
    availableQualities: available.isEmpty ? const {} : Set.of(available),
    relateGoods: goods,
  );
}

/// Extract style-recommend tag groups from `tag_info` (EchoMusic Home.vue).
///
/// Payload shape: `data.tag_info[]` → `{ name, child: [{id,name,default}] }`.
List<({String name, List<({String id, String name, bool isDefault})> child})>
    extractStyleTagGroups(dynamic body) {
  Map<String, dynamic>? data;
  if (body is Map) {
    final map = Map<String, dynamic>.from(body);
    data = map['data'] is Map
        ? Map<String, dynamic>.from(map['data'] as Map)
        : map;
  } else {
    return const [];
  }

  final rawGroups = data['tag_info'];
  if (rawGroups is! List) return const [];

  final groups = <({String name, List<({String id, String name, bool isDefault})> child})>[];
  for (final group in rawGroups) {
    if (group is! Map) continue;
    final g = Map<String, dynamic>.from(group);
    final name = _s(g['name']);
    final rawChild = g['child'];
    if (name.isEmpty || rawChild is! List) continue;
    final child = <({String id, String name, bool isDefault})>[];
    for (final tag in rawChild) {
      if (tag is! Map) continue;
      final t = Map<String, dynamic>.from(tag);
      final id = _s(t['id']);
      final tagName = _s(t['name']);
      if (id.isEmpty || tagName.isEmpty) continue;
      final defaultRaw = t['default'];
      final isDefault = defaultRaw == 1 ||
          defaultRaw == true ||
          defaultRaw == '1';
      child.add((id: id, name: tagName, isDefault: isDefault));
    }
    if (child.isEmpty) continue;
    groups.add((name: name, child: child));
  }
  return groups;
}

/// Maps gateway playlist payloads (special_recommend / top_ip) into
/// [PlaylistBrief] with an id that `/playlist/:id` can actually resolve.
///
/// Gateway items mix `specialid` / `listid` / `list_create_listid` /
/// `global_collection_id` / `ip_id`. Prefer numeric special ids; when only a
/// `collection_x_<special>_y_z` gid exists, take the embedded special number.
PlaylistBrief mapRecommendPlaylist(Map<String, dynamic> json) {
  final extra = json['extra'] is Map
      ? Map<String, dynamic>.from(json['extra'] as Map)
      : const <String, dynamic>{};

  String numericId = '';
  for (final source in [json, extra]) {
    for (final key in [
      'specialid',
      'listid',
      'list_create_listid',
      'ip_id',
      'id',
    ]) {
      final v = source[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isEmpty || s == '0') continue;
      if (int.tryParse(s) == null) continue;
      numericId = s;
      break;
    }
    if (numericId.isNotEmpty) break;
  }

  if (numericId.isEmpty) {
    final gid = _s(
      json['global_collection_id'],
      _s(json['gid'], _s(extra['global_collection_id'], _s(extra['global_special_id']))),
    );
    final match = RegExp(r'collection_\d+_(\d+)_').firstMatch(gid);
    if (match != null) numericId = match.group(1)!;
  }

  // Parse `ip_id` out of `extra.inner_url` when the API omitted the field.
  if (numericId.isEmpty) {
    final inner = _s(extra['inner_url'], _s(json['inner_url']));
    final idx = inner.lastIndexOf('ip_id');
    if (idx != -1 && idx + 6 < inner.length) {
      final raw = inner.substring(idx + 6).split(RegExp(r'[^0-9]')).first;
      if (raw.isNotEmpty) numericId = raw;
    }
  }

  final name = _s(
    json['name'],
    _s(json['specialname'], _s(json['listname'], _s(json['title'], '歌单'))),
  );
  final pic = _pickCover(json);
  final cover = normalizeCoverUrl(pic.isEmpty ? (numericId.isEmpty ? name : numericId) : pic);
  final count = _i2(json['songcount'], json['song_count']);
  final play = _i2(
    json['playcount'],
    _i2(json['play_count'], json['listen_num']),
  );
  final creator = _s(
    json['nickname'],
    _s(json['username'], _s(json['list_create_username'], _s(json['creator']))),
  );
  final intro = _s(json['intro'], _s(json['description'], _s(json['desc'])));

  return PlaylistBrief(
    id: numericId,
    name: name,
    coverUrl: cover,
    description: intro,
    creator: creator,
    trackCount: count,
    playCountLabel: play > 0 ? formatCount(play) : '',
  );
}
