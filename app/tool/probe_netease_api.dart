import 'dart:convert';

import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/source/music_source.dart';

/// CLI：网易云接口调试探针。
///
/// ```bash
/// dart run tool/probe_netease_api.dart
/// dart run tool/probe_netease_api.dart --keyword love
/// dart run tool/probe_netease_api.dart --suite login,like,detail
/// dart run tool/probe_netease_api.dart --uid 1 --playlist 24381616 --album 32311 --artist 6452
/// ```
Future<void> main(List<String> args) async {
  var keyword = '周杰伦';
  int? songId;
  int uid = 0;
  int playlistId = 0;
  int albumId = 32311;
  int artistId = 6452;
  final suites = <String>{'search'};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() => i + 1 < args.length ? args[++i] : '';
    if (a == '--keyword') {
      keyword = next();
    } else if (a == '--id') {
      songId = int.tryParse(next());
    } else if (a == '--uid') {
      uid = int.tryParse(next()) ?? 0;
    } else if (a == '--playlist') {
      playlistId = int.tryParse(next()) ?? 0;
    } else if (a == '--album') {
      albumId = int.tryParse(next()) ?? albumId;
    } else if (a == '--artist') {
      artistId = int.tryParse(next()) ?? artistId;
    } else if (a == '--suite') {
      suites
        ..clear()
        ..addAll(next().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
  }
  if (suites.contains('discover') || suites.contains('recommend')) {
    suites.add('discover');
  }
  // … main body below calls _probeDiscover when needed

  final client = NeteaseClient();
  print('== Netease probe · suites=${suites.join(',')} keyword=$keyword ==');

  try {
    await client.ensureWeapiSession();
    print('[S2] csrf=${client.csrf.isEmpty ? 'MISSING' : client.csrf}');
    print('[S2] cookieKeys=${client.cookies.keys.join(',')}');
  } catch (e) {
    print('[S2] preheat failed: $e');
  }

  // 即使搜索失败，也用固定 id 打 EAPI（分离 weapi / eapi 问题）。
  // 搜到歌后会优先用搜索结果 id。

  ProbeSong? first;
  try {
    final raw = await client.searchSongsDebug(keyword);
    final songs = parseProbeSongs(raw);
    print('[A1] search hits=${songs.length}');
    for (final s in songs) {
      print('     $s');
    }
    first = songs.isNotEmpty ? songs.first : null;
  } catch (e) {
    print('[A1] FAIL ${_err(e)}');
  }

  songId ??= first?.id;
  if (songId != null) {
    try {
      final raw = await client.songDetailRaw([songId]);
      print('[A4] detail title=${parseProbeDetailTitle(raw)}');
    } catch (e) {
      print('[A4] FAIL ${_err(e)}');
    }

    try {
      final raw = await client.songPlayUrlRaw(songId);
      print('[A2 raw] ${raw.substring(0, raw.length.clamp(0, 400))}');
      final play = parseProbePlayUrl(raw);
      print(
        '[A2] url=${play.url.length > 60 ? '${play.url.substring(0, 60)}…' : play.url}',
      );
      print(
        '[A2] level=${play.level} type=${play.type} size=${play.size} '
        'preview=${play.isPreviewClip} fee=${play.fee}',
      );
    } catch (e) {
      print('[A2] FAIL ${_err(e)}');
      try {
        final raw = await client.songPlayUrlWeapiRaw(songId);
        print('[A2b raw] ${raw.substring(0, raw.length.clamp(0, 400))}');
        final play = parseProbePlayUrl(raw);
        print('[A2b] weapi fallback url ok level=${play.level}');
      } catch (e2) {
        print('[A2b] FAIL ${_err(e2)}');
      }
    }

    try {
      final raw = await client.songLyricRaw(songId);
      final lyric = parseProbeLyric(raw);
      print(
        '[A3] lrc=${lyric.lrc.length} yrc=${lyric.yrc.length} '
        'tlyric=${lyric.tlyric.length} romalrc=${lyric.romalrc.length}',
      );
    } catch (e) {
      print('[A3] FAIL ${_err(e)}');
      try {
        final raw = await client.songLyricPlainRaw(songId);
        final lyric = parseProbeLyric(raw);
        print('[A3b] plain lrc=${lyric.lrc.length} yrc=${lyric.yrc.length}');
      } catch (e2) {
        print('[A3b] FAIL ${_err(e2)}');
      }
    }
  } else {
    print('no songId — skip A2/A3/A4');
  }

  if (suites.contains('login')) {
    await _probeLogin(client);
  }
  if (suites.contains('like')) {
    await _probeLike(client, uid);
  }
  if (suites.contains('detail')) {
    await _probeDetail(
      client,
      playlistId: playlistId == 0 ? 24381616 : playlistId,
      albumId: albumId,
      artistId: artistId,
    );
  }
  if (suites.contains('discover')) {
    await _probeDiscover(client);
  }

  print('== done · cookies=${client.cookies.keys.join(',')} ==');
}

Future<void> _probeDiscover(NeteaseClient client) async {
  Future<void> hit(String id, Future<String> Function() call) async {
    try {
      final raw = await call();
      print('[$id] ${parseProbeRecommend(raw, label: id)}');
    } catch (e) {
      print('[$id] FAIL ${_err(e)}');
    }
  }

  await hit('G1-personalized', () => client.personalizedPlaylistsRaw(limit: 5));
  await hit('G2-daily-resource', client.dailyRecommendResourceRaw);
  await hit('G3-daily-songs', client.dailyRecommendSongsRaw);
  await hit('G4-personal-fm', client.personalFmRaw);
  await hit('G5-new-songs', () => client.personalizedNewSongsRaw(limit: 5));
  await hit('G6-top-playlists', () => client.topPlaylistsRaw(limit: 5));
  await hit('G7a-highquality', () => client.highQualityPlaylistsRaw(limit: 5));
  await hit('G7b-hq-tags', client.highQualityTagsRaw);
  await hit('G9-radar-meta', () => client.radarPlaylistMetaRaw(3136952023));
}

Future<void> _probeLogin(NeteaseClient client) async {
  try {
    final raw = await client.accountRaw();
    print('[L1] account ${parseProbeAccount(raw)}');
  } catch (e) {
    print('[L1] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.qrUnikeyRaw();
    final root = RegExp(r'"unikey"\s*:\s*"([^"]*)"').firstMatch(raw)?.group(1);
    print('[L2] qrUnikey code=${RegExp(r'"code"\s*:\s*(\d+)').firstMatch(raw)?.group(1)} '
        'unikey=${root?.isEmpty ?? true ? 'NONE' : '${root!.substring(0, root.length.clamp(0, 8))}…'}');
  } catch (e) {
    print('[L2] FAIL ${_err(e)}');
  }
  // 手机号/短信需真实凭据，这里只打印不会发请求。
  print('[L3] phone/sms login methods ready (need real credentials to probe)');
}

Future<void> _probeLike(NeteaseClient client, int uid) async {
  try {
    final raw = await client.accountRaw();
    final acc = parseProbeAccount(raw);
    final id = uid != 0 ? uid : ((acc['userId'] as num?)?.toInt() ?? 0);
    print('[K0] userId=$id hasLogin=${client.hasLogin}');
    if (id == 0) {
      print('[K0] no uid — skip like APIs (login first)');
      return;
    }
    final pl = await client.userPlaylistsRaw(id);
    print('[K1] userPlaylists ${parseProbeUserPlaylists(pl)}');
    final liked = await client.likedSongIdsRaw(id);
    final ids = RegExp(r'\d+').allMatches(liked).length;
    print('[K2] likedSongIds code=${RegExp(r'"code"\s*:\s*(\d+)').firstMatch(liked)?.group(1)} '
        'numTokens≈$ids');
    print('[K3] likeSong/addTracks ready (write API — not fired without login)');
  } catch (e) {
    print('[K] FAIL ${_err(e)}');
  }
}

Future<void> _probeDetail(
  NeteaseClient client, {
  required int playlistId,
  required int albumId,
  required int artistId,
}) async {
  try {
    final raw = await client.playlistDetailRaw(playlistId);
    print('[D1] playlist($playlistId) ${parseProbePlaylistDetail(raw)}');
  } catch (e) {
    print('[D1] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.albumDetailRaw(albumId);
    print('[D2] album($albumId) ${parseProbeAlbumDetail(raw)}');
  } catch (e) {
    print('[D2] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistDetailRaw(artistId);
    print('[D3] artist($artistId) ${parseProbeArtistDetail(raw)}');
  } catch (e) {
    print('[D3] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistSongsRaw(artistId, limit: 5);
    final n = RegExp(r'"songs"\s*:').hasMatch(raw)
        ? (jsonDecode(raw) is Map
            ? (((jsonDecode(raw) as Map)['songs'] as List?)?.length ?? 0)
            : 0)
        : 0;
    print('[D4] artistSongs($artistId) songs≈$n');
  } catch (e) {
    print('[D4] FAIL ${_err(e)}');
  }
}

String _err(Object e) {
  if (e is SourceFailure) return '$e';
  return e.toString().split('\n').first;
}
