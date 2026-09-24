import 'dart:convert';

import 'package:kugo/core/api/netease/netease_client.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:qr/qr.dart';

/// CLI：网易云接口调试探针。
///
/// ```bash
/// # 默认：搜索 + 单曲详情 + 播放 URL + 歌词
/// dart run tool/probe_netease_api.dart
/// dart run tool/probe_netease_api.dart --keyword love
///
/// # A1c 分类搜索（1 单曲 / 10 专辑 / 100 歌手 / 1000 歌单）
/// #   同时打印首条记录的键名，用于核对 netease_mappers 的多键回退
/// dart run tool/probe_netease_api.dart --types 1,10,100,1000
///
/// # B4 音质档位扫描
/// dart run tool/probe_netease_api.dart --levels standard,exhigh,lossless,hires
///
/// # A1b cloudsearch 对照（实测 50000005，仅排查用）
/// dart run tool/probe_netease_api.dart --suite cloudsearch
///
/// # 登录 / 我喜欢 / 详情 / 推荐
/// dart run tool/probe_netease_api.dart --suite login,like,detail,discover
/// dart run tool/probe_netease_api.dart --suite detail --playlist 24381616 --album 32311 --artist 6452
///
/// # E2/E3 交互式扫码登录（打印二维码 → 每 2s 轮询到 803）
/// #   默认不带 yd_token；2026-09-24 实测发空串即可走到 803
/// dart run tool/probe_netease_api.dart --suite login --qr
/// dart run tool/probe_netease_api.dart --suite login --qr --qr-timeout 180
/// dart run tool/probe_netease_api.dart --suite login --qr --yd-token <token>
///
/// # F 组登录态：同进程「扫码登录 → 跑我喜欢」（免传 MUSIC_U，uid 自动取）
/// dart run tool/probe_netease_api.dart --suite login,like --qr
///
/// # E4 密码登录 / E5 短信登录 / E6 发码 / E7 验码（需真实凭据，默认不发）
/// dart run tool/probe_netease_api.dart --suite login --phone 13800000000 --password xxx
/// dart run tool/probe_netease_api.dart --suite login --phone 13800000000 --captcha 1234
/// dart run tool/probe_netease_api.dart --suite login --phone 13800000000 --send-sms
/// dart run tool/probe_netease_api.dart --suite login --phone 13800000000 --captcha 1234 --verify-sms
///
/// # F4 / F5 写操作（必须 --write 显式打开，会真改账号）
/// dart run tool/probe_netease_api.dart --suite like --uid 123 --write --like true --id 1234567
/// dart run tool/probe_netease_api.dart --suite like --uid 123 --write --playlist 24381616 --id 1234567
/// ```
Future<void> main(List<String> args) async {
  final o = _Args.parse(args);
  final client = NeteaseClient();
  print('== Netease probe · suites=${o.suites.join(',')} keyword=${o.keyword} ==');

  try {
    await client.ensureWeapiSession();
    print('[S2] csrf=${client.csrf.isEmpty ? 'MISSING' : client.csrf}');
    print('[S2] cookieKeys=${client.cookies.keys.join(',')}');
  } catch (e) {
    print('[S2] preheat failed: $e');
  }

  if (o.suites.contains('search')) await _probeSearch(client, o);
  if (o.suites.contains('cloudsearch')) await _probeCloudsearch(client, o);
  if (o.suites.contains('login')) await _probeLogin(client, o);
  if (o.suites.contains('like')) await _probeLike(client, o);
  if (o.suites.contains('detail')) await _probeDetail(client, o);
  if (o.suites.contains('discover')) await _probeDiscover(client);

  print('== done · cookies=${client.cookies.keys.join(',')} ==');
}

// ── 搜索 / 播放 / 歌词 ──────────────────────────────────────

Future<void> _probeSearch(NeteaseClient client, _Args o) async {
  ProbeSong? first;
  try {
    final raw = await client.searchRaw(keyword: o.keyword);
    final songs = parseProbeSongs(raw);
    print('[A1] search(type=1) hits=${songs.length}');
    for (final s in songs) {
      print('     $s');
    }
    first = songs.isNotEmpty ? songs.first : null;
  } catch (e) {
    print('[A1] FAIL ${_err(e)}');
  }

  // A1c 分类搜索（单曲 1 / 专辑 10 / 歌手 100 / 歌单 1000）
  for (final t in o.types) {
    final type = int.tryParse(t);
    if (type == null) {
      print('[A1c] bad type: $t');
      continue;
    }
    try {
      final raw = await client.searchRaw(keyword: o.keyword, type: type);
      print('[A1c] type=$type ${_summary(raw)}');
      // 歌单/专辑/歌手的字段名尚未实测：打印首条记录的键名与候选字段，
      // 用于核对 `netease_mappers` 的多键回退是否命中。
      print('      fields=${_fieldSample(raw)}');
    } catch (e) {
      print('[A1c] type=$type FAIL ${_err(e)}');
    }
  }

  final songId = o.songId ?? first?.id;
  if (songId == null) {
    print('[A2/A3/A4] no songId — skip（可传 --id）');
    return;
  }
  print('[pick] songId=$songId');

  try {
    final raw = await client.songDetailRaw([songId]);
    print('[A4] detail title=${parseProbeDetailTitle(raw)}');
  } catch (e) {
    print('[A4] FAIL ${_err(e)}');
  }

  try {
    final raw = await client.songPlayUrlRaw(songId, level: o.level);
    print('[A2 raw] ${_short(raw, 400)}');
    final play = parseProbePlayUrl(raw);
    print('[A2] reqLevel=${o.level} url=${_short(play.url)}');
    print('[A2] grantedLevel=${play.level} type=${play.type} size=${play.size} '
        'preview=${play.isPreviewClip} fee=${play.fee}');
  } catch (e) {
    print('[A2] FAIL ${_err(e)}');
    try {
      final raw = await client.songPlayUrlWeapiRaw(songId);
      print('[A2b raw] ${_short(raw, 400)}');
      final play = parseProbePlayUrl(raw);
      print('[A2b] weapi fallback url=${_short(play.url)} level=${play.level}');
    } catch (e2) {
      print('[A2b] FAIL ${_err(e2)}');
    }
  }

  // B4 音质档位扫描（默认不跑）
  for (final lv in o.levels) {
    try {
      final raw = await client.songPlayUrlRaw(songId, level: lv);
      final play = parseProbePlayUrl(raw);
      print('[B4] req=$lv granted=${play.level} type=${play.type} size=${play.size}');
    } catch (e) {
      print('[B4] req=$lv FAIL ${_err(e)}');
    }
  }

  try {
    final raw = await client.songLyricRaw(songId);
    final lyric = parseProbeLyric(raw);
    print('[A3] lrc=${lyric.lrc.length} yrc=${lyric.yrc.length} '
        'tlyric=${lyric.tlyric.length} romalrc=${lyric.romalrc.length}');
  } catch (e) {
    print('[A3] FAIL ${_err(e)}');
  }

  try {
    final raw = await client.songLyricPlainRaw(songId);
    final lyric = parseProbeLyric(raw);
    print('[C2] plain lrc=${lyric.lrc.length} yrc=${lyric.yrc.length} '
        'tlyric=${lyric.tlyric.length}');
  } catch (e) {
    print('[C2] FAIL ${_err(e)}');
  }
}

/// A1b：cloudsearch 对照口（逐个试变体，实测 50000005）。
Future<void> _probeCloudsearch(NeteaseClient client, _Args o) async {
  try {
    final raw = await client.searchSongsDebug(o.keyword);
    print('[A1b] cloudsearch 变体命中 hits=${parseProbeSongs(raw).length}');
  } catch (e) {
    print('[A1b] FAIL ${_err(e)}');
  }
}

// ── 登录 / 账号 ─────────────────────────────────────────────

Future<void> _probeLogin(NeteaseClient client, _Args o) async {
  try {
    final raw = await client.accountRaw();
    print('[E1] account ${parseProbeAccount(raw)}');
  } catch (e) {
    print('[E1] FAIL ${_err(e)}');
  }

  if (o.qr) {
    await _probeQrLogin(client, o);
  } else {
    // 默认只打一次：验证 E2/E3 端点通不通，不进入扫码等待。
    try {
      final session = await client.createQrSession();
      print('[E2] qrUnikey ok key=${_short(session.key)} '
          'chainId=${session.chainId}');
      print('[E2] qrContent=${session.qrContent}');
      final res = await client.pollQrLogin(session, ydDeviceToken: o.ydToken);
      print('[E3] qrCheck code=${res.code} msg=${res.message} '
          'refreshToken=${res.refreshToken.isEmpty ? 'EMPTY' : 'len=${res.refreshToken.length}'}');
    } catch (e) {
      print('[E2/E3] FAIL ${_err(e)}');
    }
    print('[tip] 想真正扫码登录：加 --qr');
  }

  if (o.phone.isEmpty) {
    print('[E4–E7] skip — 需 --phone（配合 --password / --captcha / --send-sms / --verify-sms）');
    return;
  }
  if (o.password.isNotEmpty) {
    try {
      final raw = await client.loginByPhoneRaw(o.phone, o.password);
      print('[E4] phoneLogin code=${_codeOf(raw)} hasLogin=${client.hasLogin} '
          'cookies=${client.cookies.keys.join(',')}');
    } catch (e) {
      print('[E4] FAIL ${_err(e)}');
    }
  }
  if (o.captcha.isNotEmpty && !o.verifySms) {
    try {
      final raw = await client.loginByCaptchaRaw(o.phone, o.captcha);
      print('[E5] captchaLogin code=${_codeOf(raw)} hasLogin=${client.hasLogin}');
    } catch (e) {
      print('[E5] FAIL ${_err(e)}');
    }
  }
  if (o.sendSms) {
    try {
      final raw = await client.sendSmsCaptchaRaw(o.phone);
      print('[E6] sendSms code=${_codeOf(raw)}');
    } catch (e) {
      print('[E6] FAIL ${_err(e)}');
    }
  }
  if (o.verifySms && o.captcha.isNotEmpty) {
    try {
      final raw = await client.verifySmsCaptchaRaw(o.phone, o.captcha);
      print('[E7] verifySms code=${_codeOf(raw)}');
    } catch (e) {
      print('[E7] FAIL ${_err(e)}');
    }
  }
}

// ── E2/E3 交互式扫码登录 ────────────────────────────────────

/// 创建扫码会话 → 终端打印二维码 → 每 2s 轮询 → 803 后确认登录态。
///
/// 首要验证点：`ydDeviceToken` 发空串能否走到 803（Neri 里它只是 best-effort）。
Future<void> _probeQrLogin(NeteaseClient client, _Args o) async {
  final NeteaseQrSession session;
  try {
    session = await client.createQrSession();
  } catch (e) {
    print('[E2] FAIL ${_err(e)}');
    return;
  }
  print('[E2] unikey=${_short(session.key)} chainId=${session.chainId}');
  print('[E2] ydDeviceToken='
      '${o.ydToken.isEmpty ? 'EMPTY（本次即验证无指纹能否登录）' : 'len=${o.ydToken.length}'}');
  print('[E2] 用「网易云音乐」App 扫描下方二维码：');
  print('');
  _printQr(session.qrContent);
  print('');
  print('[E2] qrContent=${session.qrContent}');
  print('[E3] 轮询中（每 2s，最多 ${o.qrTimeout}s）…');

  final deadline = DateTime.now().add(Duration(seconds: o.qrTimeout));
  var last = -1;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final NeteaseQrCheckResult res;
    try {
      res = await client.pollQrLogin(session, ydDeviceToken: o.ydToken);
    } catch (e) {
      print('[E3] FAIL ${_err(e)}');
      continue;
    }
    if (res.code != last) {
      last = res.code;
      print('[E3] code=${res.code} msg=${res.message} — ${_qrHint(res.code)}');
    }
    if (res.code == 803) {
      print('[E3] refreshToken='
          '${res.refreshToken.isEmpty ? 'EMPTY' : 'len=${res.refreshToken.length}'}');
      final ok = await client.confirmQrLogin(refreshToken: res.refreshToken);
      print('[E3] 确认登录 hasLogin=${client.hasLogin} ok=$ok');
      print('[E3] cookieKeys=${client.cookies.keys.join(',')}');
      try {
        print('[E1] account ${parseProbeAccount(await client.accountRaw())}');
      } catch (e) {
        print('[E1] FAIL ${_err(e)}');
      }
      return;
    }
    if (res.code == 800) {
      print('[E3] 二维码已过期，请重新运行本命令');
      return;
    }
  }
  print('[E3] 轮询超时（${o.qrTimeout}s）');
}

String _qrHint(int code) => switch (code) {
      800 => '二维码过期/失效',
      801 => '等待扫码',
      802 => '已扫码，等待手机端确认',
      803 => '登录成功',
      _ => '未知状态',
    };

/// 终端渲染二维码：半块字符（1 字符宽 = 1 模块，1 行高 = 2 模块）。
void _printQr(String data, {int quiet = 2}) {
  final image = QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = image.moduleCount;
  final size = n + quiet * 2;
  bool dark(int x, int y) {
    final mx = x - quiet;
    final my = y - quiet;
    if (mx < 0 || my < 0 || mx >= n || my >= n) return false;
    return image.isDark(my, mx);
  }

  for (var y = 0; y < size; y += 2) {
    final sb = StringBuffer();
    for (var x = 0; x < size; x++) {
      final top = dark(x, y);
      final bottom = y + 1 < size && dark(x, y + 1);
      sb.write(top ? (bottom ? '█' : '▀') : (bottom ? '▄' : ' '));
    }
    print(sb.toString());
  }
}

// ── 我喜欢 / 用户歌单 ───────────────────────────────────────

Future<void> _probeLike(NeteaseClient client, _Args o) async {
  var uid = o.uid;
  if (uid == 0) {
    try {
      final acc = parseProbeAccount(await client.accountRaw());
      uid = (acc['userId'] as num?)?.toInt() ?? 0;
    } catch (e) {
      print('[F0] account FAIL ${_err(e)}');
    }
  }
  print('[F0] uid=$uid hasLogin=${client.hasLogin}');

  if (uid == 0) {
    print('[F1–F6] no uid — skip（先登录或传 --uid）');
  } else {
    try {
      final raw = await client.userPlaylistsRaw(uid);
      print('[F1/F2] userPlaylists ${parseProbeUserPlaylists(raw)}');
    } catch (e) {
      print('[F1/F2] FAIL ${_err(e)}');
    }
    try {
      final raw = await client.likedSongIdsRaw(uid);
      print('[F3] likedSongIds ${_summary(raw)}');
      // 「我喜欢」只回 id 列表，产品侧还要再调详情；此处顺带验证该链路。
      final ids = _likedIds(raw);
      if (ids.isNotEmpty) {
        final n = ids.length < 5 ? ids.length : 5;
        final detail = await client.songDetailRaw(ids.take(n).toList());
        print('[F3b] 前 $n 首详情 ${_firstItemKeys(detail)}');
      }
    } catch (e) {
      print('[F3] FAIL ${_err(e)}');
    }
    try {
      final raw = await client.userAlbumsRaw(uid);
      print('[F6] userAlbums ${_firstItemKeys(raw)}');
    } catch (e) {
      print('[F6] FAIL ${_err(e)}');
    }
  }

  // F4 / F5 写操作：默认不发，必须 --write 显式打开。
  if (!o.write) {
    print('[F4/F5] write APIs not fired（加 --write 才发，会真改账号）');
    return;
  }
  final songId = o.songId;
  if (o.like != null) {
    if (songId == null) {
      print('[F4] skip — 需 --id');
    } else {
      try {
        final raw = await client.likeSongRaw(songId, like: o.like!);
        print('[F4] likeSong(id=$songId, like=${o.like}) code=${_codeOf(raw)}');
      } catch (e) {
        print('[F4] FAIL ${_err(e)}');
      }
    }
  }
  if (o.playlistId != 0) {
    if (songId == null) {
      print('[F5] skip — 需 --id');
    } else {
      try {
        final raw = await client.addSongsToPlaylistRaw(o.playlistId, [songId]);
        print('[F5] addTrack(pid=${o.playlistId}, id=$songId) code=${_codeOf(raw)}');
      } catch (e) {
        print('[F5] FAIL ${_err(e)}');
      }
    }
  }
}

// ── 详情：歌单 / 专辑 / 歌手 ────────────────────────────────

Future<void> _probeDetail(NeteaseClient client, _Args o) async {
  final playlistId = o.playlistId == 0 ? 24381616 : o.playlistId;
  try {
    final raw = await client.playlistDetailRaw(playlistId);
    print('[D1] playlist($playlistId) ${parseProbePlaylistDetail(raw)}');
  } catch (e) {
    print('[D1] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.albumDetailRaw(o.albumId);
    print('[D2] album(${o.albumId}) ${parseProbeAlbumDetail(raw)}');
  } catch (e) {
    print('[D2] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistDetailRaw(o.artistId);
    print('[D3] artist(${o.artistId}) ${parseProbeArtistDetail(raw)}');
  } catch (e) {
    print('[D3] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistSongsRaw(o.artistId, limit: 5);
    print('[D4] artistSongs(${o.artistId}) ${_summary(raw)}');
  } catch (e) {
    print('[D4] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistDynamicRaw(o.artistId);
    print('[D5] artistDynamic(${o.artistId}) code=${_codeOf(raw)} ${_short(raw, 120)}');
  } catch (e) {
    print('[D5] FAIL ${_err(e)}');
  }
  try {
    final raw = await client.artistAlbumsRaw(o.artistId, limit: 5);
    print('[D7] artistAlbums(${o.artistId}) ${_summary(raw)}');
  } catch (e) {
    print('[D7] FAIL ${_err(e)}');
  }
}

// ── 推荐 / 发现 ─────────────────────────────────────────────

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

  // G10 官方榜单：复用歌单详情，n=1 只取元数据（避免拉全量曲目）。
  const charts = <String, int>{
    '飙升榜': 19723756,
    '新歌榜': 3779629,
    '热歌榜': 3778678,
  };
  for (final e in charts.entries) {
    try {
      final raw = await client.playlistDetailRaw(e.value, n: 1, s: 0);
      print('[G10] ${e.key}(${e.value}) ${parseProbePlaylistDetail(raw)}');
    } catch (err) {
      print('[G10] ${e.key} FAIL ${_err(err)}');
    }
  }
}

// ── 小工具 ──────────────────────────────────────────────────

/// 参数解析。
class _Args {
  String keyword = '周杰伦';
  int? songId;
  int uid = 0;
  int playlistId = 0;
  int albumId = 32311;
  int artistId = 6452;
  String level = 'exhigh';
  List<String> types = const [];
  List<String> levels = const [];
  String phone = '';
  String password = '';
  String captcha = '';
  String ydToken = '';
  bool qr = false;
  int qrTimeout = 120;
  bool sendSms = false;
  bool verifySms = false;
  bool write = false;
  bool? like;
  Set<String> suites = {'search'};

  static _Args parse(List<String> args) {
    final o = _Args();
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String next() => i + 1 < args.length ? args[++i] : '';
      if (a == '--keyword') {
        o.keyword = next();
      } else if (a == '--id') {
        o.songId = int.tryParse(next());
      } else if (a == '--uid') {
        o.uid = int.tryParse(next()) ?? 0;
      } else if (a == '--playlist') {
        o.playlistId = int.tryParse(next()) ?? 0;
      } else if (a == '--album') {
        o.albumId = int.tryParse(next()) ?? o.albumId;
      } else if (a == '--artist') {
        o.artistId = int.tryParse(next()) ?? o.artistId;
      } else if (a == '--level') {
        o.level = next();
      } else if (a == '--types') {
        o.types = _split(next());
      } else if (a == '--levels') {
        o.levels = _split(next());
      } else if (a == '--phone') {
        o.phone = next();
      } else if (a == '--password') {
        o.password = next();
      } else if (a == '--captcha') {
        o.captcha = next();
      } else if (a == '--yd-token') {
        o.ydToken = next();
      } else if (a == '--qr') {
        o.qr = true;
      } else if (a == '--qr-timeout') {
        o.qrTimeout = int.tryParse(next()) ?? o.qrTimeout;
      } else if (a == '--send-sms') {
        o.sendSms = true;
      } else if (a == '--verify-sms') {
        o.verifySms = true;
      } else if (a == '--write') {
        o.write = true;
      } else if (a == '--like') {
        o.like = next() != 'false';
      } else if (a == '--suite') {
        o.suites = _split(next()).toSet();
      } else {
        print('[warn] unknown arg: $a');
      }
    }
    if (o.suites.contains('recommend')) {
      o.suites
        ..remove('recommend')
        ..add('discover');
    }
    return o;
  }

  static List<String> _split(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

String _codeOf(String raw) =>
    RegExp(r'"code"\s*:\s*(-?\d+)').firstMatch(raw)?.group(1) ?? '-';

String _short(String s, [int max = 60]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// 通用列表摘要（A1c 分类搜索 / F3 / F6 / D4 / D7 用）。
///
/// 覆盖 `result.{songs,albums,artists,playlists}`、`{playlists,hotAlbums}`、
/// `data.list`、`ids` 等形态。
Map<String, Object?> _summary(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  Object? node = root['result'] ?? root['data'] ?? root;
  List? list;
  if (node is List) {
    list = node;
  } else if (node is Map) {
    for (final k in const [
      'songs',
      'albums',
      'artists',
      'playlists',
      'hotAlbums',
      'list',
      'data',
      'ids',
    ]) {
      final v = node[k];
      if (v is List) {
        list = v;
        break;
      }
      if (v is Map) {
        final inner = v['list'] ?? v['data'];
        if (inner is List) {
          list = inner;
          break;
        }
      }
    }
  }
  Object? first;
  if (list != null && list.isNotEmpty && list.first is Map) {
    final m = list.first as Map;
    first = m['name'] ?? m['songName'] ?? m['title'] ?? m['id'];
  }
  return {
    'code': root['code'] ?? root['status'],
    'count': list?.length,
    'first': first,
  };
}

/// 列表接口的**首条记录键名 + 候选字段取值**（字段名未实测时用来核对 mapper 回退键）。
///
/// 兼容 `{data:[…]}` / `{result:{…}}` 包裹，以及 `data[].album` / `data[].song` 这类一层嵌套。
Map<String, Object?> _firstItemKeys(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final node = root['data'] ?? root['result'] ?? root;
  List? list;
  if (node is List) {
    list = node;
  } else if (node is Map) {
    for (final k in const ['data', 'list', 'albums', 'songs', 'playlists']) {
      final v = node[k];
      if (v is List) {
        list = v;
        break;
      }
    }
  }
  if (list == null || list.isEmpty) return const {'count': 0, 'first': null};
  final first = list.first;
  if (first is! Map) return {'count': list.length, 'first': '$first'};
  final inner = first['album'] ?? first['song'] ?? first;
  final m = inner is Map ? inner : first;
  return {
    'count': list.length,
    'keys': m.keys.join(','),
    'id': m['id'],
    'name': m['name'] ?? m['title'],
    'cover': m['picUrl'] ?? m['coverImgUrl'] ?? m['blurPicUrl'],
    'artist': m['artist'] ?? m['artists'] ?? m['ar'],
  };
}

/// `song/like/get` 响应里的歌曲 id 列表（非数字项跳过）。
List<int> _likedIds(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final ids = root['ids'] as List? ?? const [];
  return [
    for (final v in ids)
      if (v is num) v.toInt(),
  ];
}

String _err(Object e) {
  if (e is SourceFailure) return '$e';
  return e.toString().split('\n').first;
}

/// A1c 字段核对：首条记录的**全部键名** + 映射候选字段取值。
///
/// 歌单/专辑/歌手的字段名未实测，`netease_mappers` 走多键回退；
/// 本输出用于确认回退键是否真的命中（跑 `--types 10,100,1000`）。
Map<String, Object?> _fieldSample(String raw) {
  final root = jsonDecode(raw) as Map<String, dynamic>;
  final node = root['result'] ?? root;
  if (node is! Map) return const {'first': null};
  List? list;
  for (final k in const ['songs', 'albums', 'artists', 'playlists']) {
    final v = node[k];
    if (v is List && v.isNotEmpty) {
      list = v;
      break;
    }
  }
  final first = list?.first;
  if (first is! Map) return const {'first': null};
  return {
    'keys': first.keys.join(','),
    'id': first['id'],
    'name': first['name'] ?? first['title'],
    'cover': first['picUrl'] ??
        first['coverImgUrl'] ??
        first['img1v1Url'] ??
        first['blurPicUrl'],
    'artist': first['artist'] ?? first['artists'] ?? first['ar'],
    'size': first['size'] ?? first['trackCount'],
    'musicSize': first['musicSize'],
    'fansCount': first['fansCount'],
    'creator': first['creator'],
    'publishTime': first['publishTime'],
    // 旧口 search/get 的曲目把专辑塞在 `album` 里，封面键名与顶层不同，
    // 故单列出来（核对 `mapNeteaseSong` 的 album 回退是否命中）。
    if (first['album'] is Map) ...{
      'albumKeys': (first['album'] as Map).keys.join(','),
      'albumCover': (first['album'] as Map)['picUrl'] ??
          (first['album'] as Map)['blurPicUrl'] ??
          (first['album'] as Map)['picId'],
    },
  };
}
