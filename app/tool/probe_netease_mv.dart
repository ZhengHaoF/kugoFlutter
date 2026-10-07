import 'dart:convert';

import 'package:kugo/core/api/netease/netease_client.dart';

/// CLI：网易云 **MV** 接口探针（A0）。
///
/// 对齐 `api-enhanced` `module/mv_*.js` / `cloudsearch.js`（type=1004）。
/// 本探针只做**只读**实测；收藏写操作需显式 `--write`。
///
/// ```bash
/// # 默认：详情 + 取流 + 搜 MV（免登录，游客即可）
/// dart run tool/probe_netease_mv.dart
/// dart run tool/probe_netease_mv.dart --mvid 5436712 --keyword 晴天
///
/// # 单项套件
/// dart run tool/probe_netease_mv.dart --suite detail
/// dart run tool/probe_netease_mv.dart --suite url --r 1080
/// dart run tool/probe_netease_mv.dart --suite search --keyword 晴天
/// dart run tool/probe_netease_mv.dart --suite artist --artist 6452
/// dart run tool/probe_netease_mv.dart --suite songmv --song 186016
///
/// # 收藏（需登录；sub/unsub 为写操作，必须 --write）
/// dart run tool/probe_netease_mv.dart --suite sublist
/// dart run tool/probe_netease_mv.dart --suite sub --mvid 5436712 --write --collect true
/// dart run tool/probe_netease_mv.dart --suite sub --mvid 5436712 --write --collect false
/// ```
///
/// 探针目标（见 `网易云接口文档.md` §十 与 `docs/api-notes.md`「网易云 MV（A0）」）：
/// 1. `mv/detail` 的 `brs` 形态（档位枚举依据）
/// 2. `song/enhance/play/mv/url` 的 `url` / `r` / 时效
/// 3. `cloudsearch` type=1004 的列表字段（映射 `MvBrief`）
/// 4. `artist/mvs` 列表字段
/// 5. `song.mv` 是否为 mvid（`songMvs` 1:1 语义）
/// 6. `mv/sub` + `cloudvideo/allvideo/sublist` 收藏闭环
Future<void> main(List<String> args) async {
  final o = _Args.parse(args);
  final client = NeteaseClient();
  print('== Netease MV probe · suites=${o.suites.join(',')} '
      'mvid=${o.mvid} r=${o.resolution} keyword=${o.keyword} ==');

  try {
    await client.ensureWeapiSession();
    print('[S] csrf=${client.csrf.isEmpty ? 'MISSING' : client.csrf}');
    print('[S] cookieKeys=${client.cookies.keys.join(',')}');
  } catch (e) {
    print('[S] preheat failed: $e');
  }

  if (o.suites.contains('detail')) await _probeDetail(client, o);
  if (o.suites.contains('url')) await _probeUrl(client, o);
  if (o.suites.contains('search')) await _probeSearch(client, o);
  if (o.suites.contains('artist')) await _probeArtist(client, o);
  if (o.suites.contains('songmv')) await _probeSongMv(client, o);
  if (o.suites.contains('sublist')) await _probeSublist(client);
  if (o.suites.contains('sub')) await _probeSub(client, o);

  print('== done ==');
}

// ── A0-1 · MV 详情 ─────────────────────────────────────────
//
// api-enhanced module/mv_detail.js:
//   data = { id: query.mvid }
//   request(`/api/v1/mv/detail`, data, weapi)
//
// ★ weapi 路径坑（与 NeteaseCloudMusicApi 同源）：其 request 对 weapi 做
//   `'/weapi/' + uri.substr(5)`，即剥掉 `/api/` 前缀。
//   module 写 `/api/v1/mv/detail` → 实际打 `music.163.com/weapi/v1/mv/detail`。
//   本仓 [NeteaseClient.callWeApi] 只补 `/weapi` 前缀，**不剥 `/api`**，
//   故这里 path 必须传**已剥前缀**的 `/v1/mv/detail`。
//
// 重点核对：
//   data.id / name / cover / desc / duration / publishTime / playCount
//   data.artists[]
//   data.brs  ← 档位枚举（"240"/"480"/"720"/"1080" → url）★
Future<void> _probeDetail(NeteaseClient client, _Args o) async {
  print('--- A0-1 mv_detail mvid=${o.mvid} ---');
  try {
    final raw = await client.callWeApi('/v1/mv/detail', {'id': o.mvid});
    _dump('mv_detail', raw, focus: const [
      'code',
      'data',
    ]);
    final data = _asMap(_decode(raw))['data'];
    if (data is Map) {
      final brs = data['brs'];
      print('     brief: id=${data['id']} name=${data['name']} '
          'duration=${data['duration']} publishTime=${data['publishTime']}');
      print('     counts: play=${data['playCount']} sub=${data['subCount']} '
          'comment=${data['commentCount']} share=${data['shareCount']}');
      print('     artists=${_artistsOf(data)}');
      print('     cover=${data['cover']}');
      if (brs is List) {
        // 实测（2026-09-28）：brs 是 **List**，元素 {size, br, point}，
        // **不含 url** —— 只用来枚举档位；播放地址一律走 mv_url。
        print('     ★ brs List len=${brs.length}');
        for (final e in brs) {
          final m = e is Map ? e : const {};
          print('        br=${m['br']} size=${m['size']} point=${m['point']}');
        }
      } else if (brs is Map) {
        // 容错：若上游改为 map 形态
        print('     ★ brs Map keys=${brs.keys.toList()}');
        for (final e in brs.entries) {
          final u = '${e.value}';
          print('        r=${e.key} urlLen=${u.length} '
              'head=${u.isEmpty ? '' : u.substring(0, u.length > 80 ? 80 : u.length)}…');
        }
      } else {
        print('     ★ brs MISSING or not List/Map: ${brs.runtimeType}');
      }
      // mp = 特权（pl/dl 为可播/可下最高码率）
      final mp = _asMap(_decode(raw))['mp'];
      if (mp.isNotEmpty) {
        print('     mp.pl=${mp['pl']} mp.dl=${mp['dl']} mp.st=${mp['st']} '
            'mp.fee=${mp['fee']} unauthorized=${mp['unauthorized']}');
      }
      print('     subed=${_asMap(_decode(raw))['subed']}');
      // 其它可能带清晰度的字段，防止形态漂移。
      for (final k in ['videos', 'video', 'url', 'mp4Url', 'resolutions']) {
        if (data.containsKey(k)) {
          print('     extra key "$k": ${_slice(data[k])}');
        }
      }
    } else {
      print('     data is not Map: ${_slice(data)}');
    }
  } catch (e) {
    print('[mv_detail] FAIL ${_err(e)}');
  }
}

// ── A0-2 · MV 取流 ─────────────────────────────────────────
//
// api-enhanced module/mv_url.js:
//   data = { id: query.id, r: query.r || 1080 }
//   request(`/api/song/enhance/play/mv/url`, data, weapi)
// 同 weapi 剥前缀坑 → 实际 `/weapi/song/enhance/play/mv/url`
//
// 重点核对：
//   data.url  ← mp4 直链（短时效）★
//   data.r / data.size / data.validity / data.code
Future<void> _probeUrl(NeteaseClient client, _Args o) async {
  print('--- A0-2 mv_url mvid=${o.mvid} r=${o.resolution} ---');
  try {
    final raw = await client.callWeApi('/song/enhance/play/mv/url', {
      'id': o.mvid,
      'r': o.resolution,
    });
    _dump('mv_url', raw);
    final data = _asMap(_decode(raw))['data'];
    if (data is Map) {
      final url = '${data['url'] ?? ''}';
      print('     ★ urlEmpty=${url.isEmpty} len=${url.length}');
      // 实测字段名是 expi（秒），不是 validity。
      print('     r=${data['r']} size=${data['size']} '
          'expi=${data['expi']} code=${data['code']}');
      if (url.isNotEmpty) {
        print('     head=${url.substring(0, url.length > 100 ? 100 : url.length)}…');
        print('     ext-hint=${url.contains('.mp4') ? 'mp4' : url.contains('.flv') ? 'flv' : '?'}');
      }
    } else {
      print('     data is not Map: ${_slice(data)}');
    }
  } catch (e) {
    print('[mv_url] FAIL ${_err(e)}');
  }

  // 对照：低一档，验证 r 是否真生效（url 是否不同）。
  if (o.resolution != 480) {
    print('--- A0-2b mv_url r=480 对照 ---');
    try {
      final raw = await client.callWeApi('/song/enhance/play/mv/url', {
        'id': o.mvid,
        'r': 480,
      });
      final data = _asMap(_decode(raw))['data'];
      if (data is Map) {
        final url = '${data['url'] ?? ''}';
        print('     r=${data['r']} len=${url.length} code=${data['code']}');
      } else {
        print('     data is not Map: ${_slice(data)}');
      }
    } catch (e) {
      print('[mv_url r=480] FAIL ${_err(e)}');
    }
  }
}

// ── A0-3 · 搜 MV ──────────────────────────────────────────
//
// api-enhanced module/cloudsearch.js:
//   data = { s, type: 1004, limit, offset, total: true }
//   request(`/api/cloudsearch/pc`, data)  // 默认 crypto 空 → weapi 系
//
// 重点核对：result.mvs[] 字段 → MvBrief（id/name/cover/artist/duration）
Future<void> _probeSearch(NeteaseClient client, _Args o) async {
  print('--- A0-3 cloudsearch type=1004 keyword=${o.keyword} ---');
  // weapi 剥前缀坑：module `/api/cloudsearch/pc` → 实际 `/weapi/cloudsearch/pc`。
  // `/cloudsearch/get/web` 是本仓已有旧口（见 NeteaseEndpoints.searchCloud），对照用。
  for (final path in const ['/cloudsearch/pc', '/cloudsearch/get/web']) {
    try {
      final raw = await client.callWeApi(path, {
        's': o.keyword,
        'type': 1004,
        'limit': o.limit,
        'offset': 0,
        'total': true,
      });
      _dump('search1004 $path', raw);
      final result = _asMap(_decode(raw))['result'];
      if (result is Map) {
        final mvs = result['mvs'] ?? result['mv'];
        print('     total=${result['mvCount']} mvsType=${mvs.runtimeType} '
            'len=${mvs is List ? mvs.length : '-'}');
        if (mvs is List && mvs.isNotEmpty) {
          final first = mvs.first;
          print('     ★ firstKeys=${first is Map ? first.keys.toList() : first.runtimeType}');
          print('     first=${_slice(first, 500)}');
        }
      } else {
        print('     result not Map: ${_slice(result)}');
      }
    } catch (e) {
      print('[search1004 $path] FAIL ${_err(e)}');
    }
    print('---');
  }
}

// ── A0-4 · 歌手 MV ────────────────────────────────────────
//
// api-enhanced module/artist_mv.js:
//   data = { artistId, limit, offset, total: true }
//   request(`/api/artist/mvs`, data, weapi)
Future<void> _probeArtist(NeteaseClient client, _Args o) async {
  print('--- A0-4 artist_mvs artistId=${o.artistId} ---');
  try {
    final raw = await client.callWeApi('/artist/mvs', {
      'artistId': o.artistId,
      'limit': o.limit,
      'offset': 0,
      'total': true,
    });
    _dump('artist_mv', raw);
    final m = _asMap(_decode(raw));
    final hasMore = m['hasMore'];
    final mvs = m['mvs'] ?? m['data'];
    print('     hasMore=$hasMore mvsType=${mvs.runtimeType} '
        'len=${mvs is List ? mvs.length : '-'}');
    if (mvs is List && mvs.isNotEmpty) {
      final first = mvs.first;
      print('     ★ firstKeys=${first is Map ? first.keys.toList() : first.runtimeType}');
      print('     first=${_slice(first, 500)}');
    }
  } catch (e) {
    print('[artist_mv] FAIL ${_err(e)}');
  }
}

// ── A0-5 · 歌曲 → MV（songMvs 1:1 语义）──────────────────
//
// 网易歌曲详情 `mv` 字段：0 = 无，>0 = mvid。
// 验证后 `songMvs` 可返回单元素列表。
Future<void> _probeSongMv(NeteaseClient client, _Args o) async {
  print('--- A0-5 song_detail → mv  field  songId=${o.songId} ---');
  try {
    // 与 NeteaseClient.songDetail 同源（c[] 包一层）。
    final raw = await client.callWeApi('/weapi/v3/song/detail', {
      'c': '[{"id":${o.songId}}]',
    });
    final m = _asMap(_decode(raw));
    final songs = m['songs'];
    if (songs is List && songs.isNotEmpty) {
      final s = _asMap(songs.first);
      print('     song id=${s['id']} name=${s['name']}');
      print('     ★ mv=${s['mv']}  (0=无 MV, >0=mvid)');
      final mv = s['mv'];
      if (mv is num && mv > 0) {
        print('     → songMvs 应返回 1 条，mvid=$mv');
      } else {
        print('     → songMvs 应返回空列表');
      }
    } else {
      print('     songs empty: ${_slice(m, 300)}');
    }
  } catch (e) {
    print('[song_detail] FAIL ${_err(e)}');
  }
}

// ── A0-6 · 收藏列表 / 收藏 ────────────────────────────────
//
// api-enhanced module/mv_sublist.js:
//   data = { limit, offset, total: true }
//   request(`/api/cloudvideo/allvideo/sublist`, data, weapi)
// module/mv_sub.js:
//   t: 1→sub / 0→unsub
//   data = { mvId, mvIds: '["<id>"]' }
//   request(`/api/mv/${t}`, data, weapi)
Future<void> _probeSublist(NeteaseClient client) async {
  print('--- A0-6a mv_sublist ---');
  try {
    final raw = await client.callWeApi('/cloudvideo/allvideo/sublist', {
      'limit': 10,
      'offset': 0,
      'total': true,
    });
    _dump('mv_sublist', raw);
    final m = _asMap(_decode(raw));
    print('     hasMore=${m['hasMore']} dataLen=${m['data'] is List ? (m['data'] as List).length : '-'}');
    final data = m['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      print('     ★ firstKeys=${first is Map ? first.keys.toList() : first.runtimeType}');
      print('     first=${_slice(first, 400)}');
    }
  } catch (e) {
    print('[mv_sublist] FAIL ${_err(e)}');
  }
}

Future<void> _probeSub(NeteaseClient client, _Args o) async {
  if (!o.write) {
    print('--- A0-6b mv_sub SKIPPED（写操作，需 --write）---');
    return;
  }
  final t = o.collect ? 'sub' : 'unsub';
  print('--- A0-6b mv_sub t=$t mvid=${o.mvid} ★ WRITE ---');
  try {
    final raw = await client.callWeApi('/mv/$t', {
      'mvId': o.mvid,
      'mvIds': '[${o.mvid}]',
    });
    _dump('mv_sub $t', raw);
  } catch (e) {
    print('[mv_sub] FAIL ${_err(e)}');
  }
}

// ── helpers ───────────────────────────────────────────────

void _dump(String name, String raw, {List<String> focus = const []}) {
  print('[$name] len=${raw.length}');
  final decoded = _decode(raw);
  if (decoded is Map || decoded is List) {
    const encoder = JsonEncoder.withIndent('  ');
    var pretty = encoder.convert(decoded);
    if (pretty.length > 2000) pretty = '${pretty.substring(0, 2000)}…';
    print(pretty);
  } else {
    print(raw.length > 800 ? '${raw.substring(0, 800)}…' : raw);
  }
  if (focus.isNotEmpty) {
    final m = _asMap(decoded);
    for (final k in focus) {
      print('  [focus] $k → ${_slice(m[k], 120)}');
    }
  }
  print('---');
}

dynamic _decode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return raw;
  }
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

String _slice(dynamic v, [int max = 200]) {
  final s = '$v';
  return s.length > max ? '${s.substring(0, max)}…' : s;
}

String _artistsOf(Map data) {
  final artists = data['artists'];
  if (artists is! List) return '${data['artistName'] ?? ''}';
  return artists
      .whereType<Map>()
      .map((e) => '${e['name'] ?? ''}')
      .where((s) => s.isNotEmpty)
      .join(' / ');
}

String _err(Object e) => e.toString().split('\n').first;

class _Args {
  _Args({
    required this.suites,
    required this.mvid,
    required this.resolution,
    required this.keyword,
    required this.artistId,
    required this.songId,
    required this.limit,
    required this.write,
    required this.collect,
  });

  final List<String> suites;
  final String mvid;
  final int resolution;
  final String keyword;
  final String artistId;
  final String songId;
  final int limit;
  final bool write;
  final bool collect;

  /// 默认 mvid / songId 用公开样例；keyword 默认「晴天」。
  static _Args parse(List<String> args) {
    var suites = 'detail,url,search';
    var mvid = '5436712';
    var r = 1080;
    var keyword = '晴天';
    var artistId = '6452'; // 周杰伦
    var songId = '186016'; // 晴天
    var limit = 5;
    var write = false;
    var collect = true;

    for (var i = 0; i < args.length; i++) {
      String next(String flag) {
        if (i + 1 >= args.length) {
          throw ArgumentError('missing value for $flag');
        }
        return args[++i];
      }

      switch (args[i]) {
        case '--suite':
        case '--suites':
          suites = next('--suite');
        case '--mvid':
          mvid = next('--mvid');
        case '--r':
          r = int.parse(next('--r'));
        case '--keyword':
          keyword = next('--keyword');
        case '--artist':
          artistId = next('--artist');
        case '--song':
          songId = next('--song');
        case '--limit':
          limit = int.parse(next('--limit'));
        case '--write':
          write = true;
        case '--collect':
          collect = next('--collect') == 'true';
        case '-h':
        case '--help':
          print(_usage);
          throw StateError('help');
      }
    }
    return _Args(
      suites: suites.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      mvid: mvid,
      resolution: r,
      keyword: keyword,
      artistId: artistId,
      songId: songId,
      limit: limit,
      write: write,
      collect: collect,
    );
  }

  static const _usage = '''
usage: dart run tool/probe_netease_mv.dart [options]
  --suite detail,url,search,artist,songmv,sublist,sub
  --mvid <id>        MV id（默认 5436712）
  --r <1080|720|...> 取流清晰度（默认 1080）
  --keyword <kw>     搜索词（默认 晴天）
  --artist <id>      歌手 id（默认 6452 周杰伦）
  --song <id>        歌曲 id（默认 186016 晴天）
  --limit <n>        列表条数（默认 5）
  --write            允许收藏写操作
  --collect true|false  收藏 / 取消（默认 true）
''';
}
