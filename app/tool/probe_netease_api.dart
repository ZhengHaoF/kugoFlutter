import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/source/music_source.dart';

/// CLI：网易云接口调试探针（一期）。
///
/// ```bash
/// dart run tool/probe_netease_api.dart
/// dart run tool/probe_netease_api.dart --keyword 晴天 --id 186016
/// ```
Future<void> main(List<String> args) async {
  var keyword = '周杰伦';
  int? songId;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--keyword' && i + 1 < args.length) {
      keyword = args[++i];
    } else if (args[i] == '--id' && i + 1 < args.length) {
      songId = int.tryParse(args[++i]);
    }
  }

  final client = NeteaseClient();
  print('== Netease probe · keyword=$keyword ==');

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

  print('== done · cookies=${client.cookies.keys.join(',')} ==');
}

String _err(Object e) {
  if (e is SourceFailure) return '$e';
  return e.toString().split('\n').first;
}
