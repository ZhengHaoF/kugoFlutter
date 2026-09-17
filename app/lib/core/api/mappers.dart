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

String kugouCover(String? hashOrFile, {String size = '400'}) {
  final f = _s(hashOrFile).toLowerCase();
  if (f.isEmpty) return 'mock://cover';
  return 'https://imge.kugou.com/soft/collection/$size/$f';
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
  final coverRaw = _s(json['cover'], _s(json['pic'], hash));

  return Track(
    id: id.isEmpty ? hash : id,
    name: name,
    artist: artist.isEmpty ? '未知歌手' : artist,
    album: albumName,
    coverUrl: kugouCover(coverRaw.isEmpty ? hash : coverRaw),
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
  final name = _s(json['name'], _s(json['specialname'], '歌单'));
  final pic = _s(json['pic'], _s(json['imgurl'], _s(json['cover'])));
  final cover = pic.startsWith('http')
      ? pic
      : kugouCover(pic.isEmpty ? id : pic);
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

String normalizeCoverUrl(String raw) {
  if (raw.isEmpty) return 'mock://cover';
  if (raw.startsWith('http')) return raw;
  return kugouCover(raw);
}
