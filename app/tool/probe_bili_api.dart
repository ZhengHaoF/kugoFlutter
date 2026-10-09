import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/api/bili/bili_endpoints.dart';
import 'package:kugo/core/api/bili/bili_qr_login.dart';
import 'package:qr/qr.dart';

/// CLI：哔哩哔哩接口调试探针（B1 协议走私 + 账号阶段探针提前）。
///
/// ```bash
/// # 默认：wbi（spi + nav/mixinKey）+ search
/// dart run tool/probe_bili_api.dart
///
/// # 只要签名基础设施
/// dart run tool/probe_bili_api.dart --suite wbi
///
/// # 搜索（打印 numResults/numPages、剥壳前后标题、是否含 cid）
/// dart run tool/probe_bili_api.dart --suite search --keyword 周杰伦
///
/// # 分 P / 视频信息（必答项 #2：cid 从哪来）
/// dart run tool/probe_bili_api.dart --suite pagelist --bvid BV1xx411c7Hg
/// dart run tool/probe_bili_api.dart --suite view --bvid BV1xx411c7Hg
///
/// # 取流（必答项 #4：音轨档位形态；并验证防盗链直链可达）
/// dart run tool/probe_bili_api.dart --suite playurl --bvid BV1xx411c7Hg
/// dart run tool/probe_bili_api.dart --suite playurl --bvid BV1xx --cid 123 \
///   --fnval 272 --try-look 1
///
/// # 扫码登录（终端渲染二维码，每 2s 轮询；用手机 B 站 App 扫码并确认）
/// dart run tool/probe_bili_api.dart --suite login --qr
/// dart run tool/probe_bili_api.dart --suite login --qr --qr-timeout 240
///
/// # 直接灌 Cookie 免扫码（浏览器 F12 复制 SESSDATA 等）
/// dart run tool/probe_bili_api.dart --suite login \
///   --cookie "SESSDATA=xxx; bili_jct=yyy; DedeUserID=zzz"
///
/// # 扫码登录后链式取流：复核杜比 / Hi-Res 是否登录才有（必答项 #4 遗留）
/// dart run tool/probe_bili_api.dart --suite login,playurl --qr \
///   --bvid BV1FPjy6TEiE --cid 39252201332
/// ```
///
/// `--suite` 语义对齐 `probe_netease_api.dart`：**跑什么写什么**，不隐含主链。
/// 每个 suite 的通过标准见《哔哩哔哩接入方案》§8 B1 四个必答项。
Future<void> main(List<String> args) async {
  final o = _Args.parse(args);
  final client = BiliClient();
  print('== Bili probe · suites=${o.suites.join(',')} keyword=${o.keyword} ==');

  String? bvid = o.bvid;
  int? cid = o.cid;
  final notes = <String>[];

  // 直接灌 Cookie 免扫码（与 --qr 二选一；都给了以 --cookie 为准）。
  if (o.cookie.isNotEmpty) {
    final seeded = _parseCookieHeader(o.cookie);
    client.seedCookies(seeded);
    print('[G0] seeded cookie keys=${seeded.keys.join(',')}');
  }

  if (o.suites.contains('wbi')) await _probeWbi(client, notes);
  if (o.suites.contains('login')) await _probeLogin(client, o, notes);
  if (o.suites.contains('search')) {
    final picked = await _probeSearch(client, o, notes);
    bvid ??= picked;
  }
  if (o.suites.contains('pagelist')) {
    cid ??= await _probePages(client, bvid, notes);
  }
  if (o.suites.contains('view')) await _probeView(client, bvid, notes);
  if (o.suites.contains('playurl')) {
    await _probePlayUrl(client, bvid, cid, o, notes);
  }

  print('');
  print('== 必答项速记（详细结论请人工写进排期记录）==');
  for (final n in notes) {
    print('  $n');
  }
  print('== done · login=${client.hasLogin} cookieKeys=${client.cookies.keys.join(',')} ==');
}

// ── 登录（账号阶段探针）──────────────────────────────────────

Future<void> _probeLogin(BiliClient client, _Args o, List<String> notes) async {
  if (o.qr) {
    final qr = BiliQrLoginClient();
    try {
      final session = await qr.createSession();
      print('[G1] qrcode ok key=${_short(session.key)}');
      print('[G1] qrContent=${session.qrContent}');
      _printQr(session.qrContent);
      print('[G2] 轮询中（每 2s，最多 ${o.qrTimeout}s）——请用手机 B 站 App 扫码并确认');

      final deadline = DateTime.now().add(Duration(seconds: o.qrTimeout));
      var lastCode = -999;
      BiliQrLoginPoll? last;
      while (DateTime.now().isBefore(deadline)) {
        last = await qr.pollLogin(session);
        if (last.code != lastCode) {
          print('[G2] code=${last.code} — ${_qrHint(last.code)}');
          lastCode = last.code;
        }
        if (last.isConfirmed || last.code == 86038) break;
        await Future.delayed(const Duration(seconds: 2));
      }
      if (last != null && last.isConfirmed) {
        // 扫码 Cookie 在轮询响应的 Set-Cookie 里 → 灌回主客户端，
        // 后续 suite（如 playurl）即带登录态。
        client.seedCookies(qr.cookies);
        print('[G2] 登录成功 cookieKeys=${qr.cookies.keys.join(',')}');
        // 打印完整串：第二次跑可用 --cookie 复用，免二次扫码。
        print('[G2] cookie 串（--cookie 复用）：'
            '${qr.cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')}');
        notes.add('账号：扫码登录成功（keys=${qr.cookies.keys.join(',')}）');
      } else if (last != null && last.code == 86038) {
        print('[G2] 二维码过期 — 重跑本命令换新码');
      } else {
        print('[G2] 轮询超时（${o.qrTimeout}s）未确认');
      }
    } catch (e) {
      print('[G1/G2] FAIL ${_err(e)}');
    }
  } else if (!client.hasLogin) {
    print('[tip] 未登录 — 加 --qr 进程内扫码，或 --cookie "SESSDATA=..."');
  }

  // G3 登录校验（nav 的 isLogin/mid/uname）。
  try {
    final acc = await client.currentAccount();
    if (acc == null) {
      print('[G3] nav：未登录（isLogin=false）');
    } else {
      print('[G3] nav：已登录 $acc');
      notes.add('账号：nav 校验通过 $acc');
    }
  } catch (e) {
    print('[G3] FAIL ${_err(e)}');
  }
}

// ── suites ───────────────────────────────────────────────────

Future<void> _probeWbi(BiliClient client, List<String> notes) async {
  try {
    final cookies = await client.ensureAnonCookies();
    print('[I3] anon cookies: ${cookies.keys.join(',')}');
    print('[I3] buvid_fp=${cookies['buvid_fp'] ?? "（该口已不返回，带 b_3/b_4 即可）"}');
  } catch (e) {
    print('[I3] FAIL ${_err(e)}');
    notes.add('#1 游客态：I3 spi 失败（$e）→ 网络/风控存疑，记录');
  }

  try {
    final key = await client.mixinKey();
    print('[I1] nav ok · mixinKey(len=${key.length}) = ${key.substring(0, 12)}…');
    notes.add('#1 游客态：I3+I1 游客可过（未登录也拿到了签名材料）');
  } catch (e) {
    print('[I1] FAIL ${_err(e)}');
    notes.add('#1 游客态：I1 nav 失败（$e）');
  }
}

Future<String?> _probeSearch(
  BiliClient client,
  _Args o,
  List<String> notes,
) async {
  try {
    final page = await client.searchVideos(
      o.keyword,
      page: o.page,
      tids: o.tids,
    );
    print('[A1] search("${o.keyword}") hits=${page.items.length} '
        'numResults=${page.numResults} numPages=${page.numPages}');
    for (final item in page.items.take(10)) {
      print('     $item');
    }

    // 必答项 #3：title 剥壳（原文字段 vs 剥壳后）。
    final first = page.items.isEmpty ? null : page.items.first;
    if (first != null) {
      print('[A1] #3 title 剥壳：raw="${first.titleRaw}"');
      print('[A1] #3 title 剥壳：plain="${first.title}"');
    }

    // 必答项 #2：search/type=video 是否返回 cid（方案预期：不返回）。
    final withCid = page.items.where((i) => i.raw.containsKey('cid')).length;
    print('[A1] #2 条目含 cid 字段的条数：$withCid / ${page.items.length}'
        '（方案预期 0 → 搜索态身份用裸 bvid）');
    notes.add('#2 cid 来源：A1 搜索 ${withCid == 0 ? "确认不返回 cid" : "竟然返回了 cid（$withCid 条）——需回填方案"}');

    notes.add('#1 游客态：A1 搜索游客可过（hits=${page.items.length}）');
    return first?.bvid;
  } catch (e) {
    print('[A1] FAIL ${_err(e)}');
    notes.add('#1 游客态：A1 搜索失败（${_err(e)}）');
    return null;
  }
}

Future<int?> _probePages(
  BiliClient client,
  String? bvid,
  List<String> notes,
) async {
  if (bvid == null || bvid.isEmpty) {
    print('[B2] skip：无 bvid（--suite search 自动带，或 --bvid 指定）');
    return null;
  }
  try {
    final pages = await client.pages(bvid);
    print('[B2] pagelist($bvid) → ${pages.length} 个分 P');
    for (final p in pages) {
      print('     $p');
    }
    notes.add('#2 cid 来源：B2 pagelist 给全量 cid（${pages.length} P）→ '
        '裸 bvid 播放前先 pagelist 取 P1 cid 的链路成立');
    return pages.isEmpty ? null : pages.first.cid;
  } catch (e) {
    print('[B2] FAIL ${_err(e)}');
    return null;
  }
}

Future<void> _probeView(
  BiliClient client,
  String? bvid,
  List<String> notes,
) async {
  if (bvid == null || bvid.isEmpty) {
    print('[C1] skip：无 bvid（--suite search 自动带，或 --bvid 指定）');
    return;
  }
  try {
    final data = await client.videoBasicInfo(bvid);
    final owner = data['owner'];
    print('[C1] view($bvid) title="${data['title']}" '
        'owner=${owner is Map ? owner['name'] : '?'} '
        'pages=${data['pages'] is List ? (data['pages'] as List).length : '?'}');
    // view 的顶层 cid = P1 的 cid（分 P 全集在 pages[] 里）。
    print('[C1] #2 view 顶层 cid=${data['cid']}'
        '（P1 语义；多 P 时各 P cid 在 pages[]）');
    notes.add('#2 cid 来源：C1 view 顶层给 P1 cid=${data['cid']}');
  } catch (e) {
    print('[C1] FAIL ${_err(e)}');
  }
}

Future<void> _probePlayUrl(
  BiliClient client,
  String? bvid,
  int? cid,
  _Args o,
  List<String> notes,
) async {
  if (bvid == null || bvid.isEmpty) {
    print('[B1] skip：无 bvid（--suite search 自动带，或 --bvid 指定）');
    return;
  }
  cid ??= 0;
  try {
    final info = await client.playUrl(
      bvid: bvid,
      cid: cid,
      fnval: o.fnval,
      tryLook: o.tryLook,
    );
    print('[B1] playurl($bvid, cid=$cid, fnval=${o.fnval}) '
        'audio=${info.audio.length} dolby=${info.dolby.length} '
        'flac=${info.flac.length} durl=${info.durlCount}');
    _printTracks('[B1] dash.audio   ', info.audio);
    _printTracks('[B1] dash.dolby   ', info.dolby);
    _printTracks('[B1] dash.flac    ', info.flac);

    // 必答项 #4：档位形态速记（tag / 带宽 / id 集合）。
    final state = client.hasLogin ? '登录态' : '游客态';
    notes.add('#4 音轨档位（$state）：'
        'audio=[${info.audio.map(_trackBrief).join(", ")}] '
        'dolby=${info.dolby.length} flac=${info.flac.length}');

    // D6：防盗链直链验证（必须带 Referer + Web UA）。
    final target = info.audio.isNotEmpty
        ? info.audio.first
        : (info.dolby.isNotEmpty ? info.dolby.first : null);
    if (target == null || target.baseUrl.isEmpty) {
      print('[B1] #D6 无可用直链（音轨全空 → B2 的 html5/mp4 兜底路径）');
      notes.add('#1 游客态：B1 取流 code=0 但音轨空 → 记录（可能需登录/换视频）');
      return;
    }
    final status = await _pingStream(target.baseUrl, target.backupUrls);
    print('[B1] #D6 直链带头请求 → $status');
    notes.add('#1 游客态：B1 取流 + 防盗链直链可达（$status）');
  } catch (e) {
    print('[B1] FAIL ${_err(e)}');
    notes.add('#1 游客态：B1 取流失败（${_err(e)}）');
  }
}

// ── 小工具 ───────────────────────────────────────────────────

String _qrHint(int code) => switch (code) {
      0 => '登录成功',
      86090 => '已扫码，等待手机端确认',
      86101 => '等待扫码',
      86038 => '二维码已过期',
      _ => '未知状态',
    };

/// 终端渲染二维码：半块字符（1 字符宽 = 1 模块，1 行高 = 2 模块）。
/// 与 `probe_netease_api.dart` 同一套渲染。
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

/// `"k=v; k2=v2"` → map。
Map<String, String> _parseCookieHeader(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final kv = part.trim().split('=');
    if (kv.length >= 2 && kv[0].isNotEmpty) {
      out[kv[0]] = kv.sublist(1).join('=');
    }
  }
  return out;
}

String _short(String key) =>
    key.length <= 10 ? key : '${key.substring(0, 10)}…(${key.length})';

void _printTracks(String label, List<BiliAudioTrack> tracks) {
  for (final t in tracks) {
    print('$label $t');
  }
}

String _trackBrief(BiliAudioTrack t) =>
    'id=${t.id}/tag=${t.qualityTag ?? "-"}/${(t.bandwidth / 1024).round()}k';

/// 带头 GET 音轨直链（只取前 1KB，验证防盗链，不整段下载）。
Future<String> _pingStream(String url, List<String> backups) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.bytes,
  ));
  final urls = [url, ...backups];
  for (final u in urls) {
    try {
      final res = await dio.get<dynamic>(
        u,
        options: Options(
          headers: {
            'Referer': BiliEndpoints.referer,
            'User-Agent': BiliEndpoints.webUA,
            'Range': 'bytes=0-1023',
          },
        ),
      );
      final len = res.data is List ? (res.data as List).length : -1;
      return 'HTTP ${res.statusCode}（${len}B）$u';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null) {
        return 'HTTP $code（直链被拒）$u';
      }
      // 网络层错误：试下一条备份 CDN。
    }
  }
  return '全部 CDN 均不可达（网络层错误）';
}

String _err(Object e) => e.toString().split('\n').first;

// ── 参数 ─────────────────────────────────────────────────────

class _Args {
  _Args({
    required this.suites,
    required this.keyword,
    this.bvid,
    this.cid,
    this.page = 1,
    this.tids,
    this.fnval = BiliEndpoints.fnvalDefault,
    this.tryLook,
    this.qr = false,
    this.qrTimeout = 180,
    this.cookie = '',
  });

  static _Args parse(List<String> args) {
    final suites = <String>['wbi', 'search'];
    final map = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (!a.startsWith('--')) continue;
      final key = a.substring(2);
      // 值 = 后面所有连续的非标志 token（支持不带引号的多词关键词，
      // 如 `--keyword 周杰伦 官方MV`）。
      final parts = <String>[];
      var j = i + 1;
      while (j < args.length && !args[j].startsWith('--')) {
        parts.add(args[j]);
        j++;
      }
      map[key] = parts.isEmpty ? 'true' : parts.join(' ');
      i = j - 1;
    }
    final suiteArg = map['suite'];
    if (suiteArg != null) {
      suites
        ..clear()
        ..addAll(suiteArg
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty));
    }
    return _Args(
      suites: suites,
      keyword: map['keyword'] ?? '周杰伦',
      bvid: map['bvid'],
      cid: int.tryParse(map['cid'] ?? ''),
      page: int.tryParse(map['page'] ?? '') ?? 1,
      tids: int.tryParse(map['tids'] ?? ''),
      fnval: int.tryParse(map['fnval'] ?? '') ?? BiliEndpoints.fnvalDefault,
      tryLook: int.tryParse(map['try-look'] ?? ''),
      qr: map['qr'] == 'true',
      qrTimeout: int.tryParse(map['qr-timeout'] ?? '') ?? 180,
      cookie: map['cookie'] ?? '',
    );
  }

  final List<String> suites;
  final String keyword;
  final String? bvid;
  final int? cid;
  final int page;
  final int? tids;
  final int fnval;
  final int? tryLook;

  /// 终端渲染二维码扫码登录。
  final bool qr;

  /// 扫码轮询总时长（秒）。
  final int qrTimeout;

  /// 直接灌入的 Cookie 串（免扫码）。
  final String cookie;
}
