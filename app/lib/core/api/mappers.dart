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
  if (cover.isEmpty) return 'mock://cover';
  if (cover.startsWith('//')) cover = 'https:$cover';
  cover = cover.replaceAll('{size}', size);
  cover = cover.replaceFirst('http://', 'https://');
  cover = cover.replaceFirst('c1.kgimg.com', 'imge.kugou.com');
  if (cover.startsWith('https://') || cover.startsWith('mock://')) return cover;
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
  final candidates = <String>[
    _s(json['album_sizable_cover']),
    _s(json['sizable_cover']),
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

Track mapMobileSearchSong(Map<String, dynamic> json) {
  final hash = _s(json['hash']).toLowerCase();
  final id = _s(json['audio_id'], _s(json['mixsongid'], hash));
  final name = _s(json['songname'], _s(json['song_name'], '未知歌曲'));
  final singers = json['singername'] ?? json['singer'];
  var artist = _s(singers);
  if (artist.isEmpty && singers is List) {
    artist = singers.map((e) => _s(e is Map ? e['name'] : e)).join('/');
  }
  final duration = _i(json['duration']) * 1000;
  final albumId = _s(json['album_id']);
  final albumName = _s(json['album_name'], _s(json['albumname']));
  final privilege = json['privilege'];
  final isVip = privilege is Map ? _i(privilege['vip_type']) > 0 : false;
  final coverRaw = _pickCover(json);

  return Track(
    id: id.isEmpty ? hash : id,
    name: name,
    artist: artist.isEmpty ? '未知歌手' : artist,
    album: albumName,
    coverUrl: normalizeCoverUrl(coverRaw.isEmpty ? hash : coverRaw),
    durationMs: duration,
    hash: hash,
    albumId: albumId,
    mixSongId: _s(json['mixsongid'], id),
    isVip: isVip,
  );
}

PlaylistBrief mapPlaylistInfo(Map<String, dynamic> json) {
  final id = _s(
    json['global_collection_id'],
    _s(json['specialid'], _s(json['id'])),
  );
  final name = _s(
    json['name'],
    _s(json['specialname'], _s(json['rankname'], '歌单')),
  );
  final pic = _pickCover(json);
  final cover = normalizeCoverUrl(pic.isEmpty ? id : pic);
  final count = _i2(json['songcount'], json['song_count']);
  final intro = _s(json['intro'], _s(json['info']));
  final play = _i2(json['playcount'], json['listen_num']);
  return PlaylistBrief(
    id: id,
    name: name,
    coverUrl: cover,
    description: intro,
    trackCount: count,
    playCountLabel: play > 0 ? formatCount(play) : '',
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
