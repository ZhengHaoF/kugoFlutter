import 'package:dio/dio.dart';
import 'package:kugo/core/api/bili/bili_client.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/sources/bili/bili_source.dart';

/// CLI：B 站音源**适配层**冒烟（B5 装配验证）。
///
/// 与 `probe_bili_api.dart` 的分工：探针打 `BiliClient` 裸协议（B1 四个
/// 必答项）；本工具打装配后的 `BiliSource`（B2 适配层 + B5 装配）——
/// 搜索 → Track → 取流的**用户主路径**，并验证防盗链直链可达。
///
/// ```bash
/// # 默认：搜索 → 取流 → 直链 206 校验（两种 id 形态各跑一遍）
/// dart run tool/smoke_bili_source.dart --keyword 周杰伦
///
/// # 只要搜索（不取流）
/// dart run tool/smoke_bili_source.dart --suite search --keyword 晴天
/// ```
///
/// 通过标准（对齐方案 §8 B5 DoD #2 的协议部分）：
/// 1. `searchSongs` 返回非空 Track（platform=bili、id 为裸 bvid）；
/// 2. 两种 id 形态（裸 bvid / bvid:cid）`resolvePlayUrl` 都拿到直链；
/// 3. 直链带 Source 下发的 Referer/UA 头请求返回 2xx（B1 实测 206）；
/// 4. `fetchLyric` 恒空（B 站无歌词接口）。
Future<void> main(List<String> args) async {
  final o = _Args.parse(args);
  final source = biliSource;
  print('== BiliSource smoke · keyword=${o.keyword} suites=${o.suites.join(',')} ==');

  final notes = <String>[];

  // 1. 搜索 → Track。
  final page = await source.searchSongs(o.keyword);
  print('[search] items=${page.items.length} total=${page.total}');
  if (page.items.isEmpty) {
    print('[search] 空结果——换关键词重试（风控或关键词问题）');
    return;
  }
  for (final t in page.items.take(5)) {
    print('  - ${t.id} | ${t.name} | ${t.artist} | '
        '${(t.durationMs / 1000).round()}s | cover=${t.coverUrl.isNotEmpty}');
  }
  notes.add('搜索 → Track：${page.items.length} 条（platform='
      '${page.items.first.platform.wireName}，id 为裸 bvid）');

  if (!o.suites.contains('playurl')) return;

  // 2a. 裸 bvid 形态（搜索态）→ resolvePlayUrl（内部会 pagelist 取 P1 cid）。
  final bare = page.items.first;
  final r1 = await source.resolvePlayUrl(bare);
  print('[playurl · 裸 bvid] ${bare.id} → quality=${r1.grantedQuality?.name ?? "未知"} '
      'backups=${r1.backupUrls.length} preview=${r1.isPreviewClip}');
  print('  url=${r1.url}');
  print('  headers=${r1.headers}');
  await _checkReachable(r1.url, r1.headers, notes, '裸 bvid');

  // 2b. bvid:cid 形态（内容态，B4 列表口产出）→ 直接用 cid，不再打 pagelist。
  final client = BiliClient();
  final pages = await client.pages(bare.id);
  if (pages.isEmpty) {
    print('[playurl · bvid:cid] ${bare.id} 无分 P，跳过');
  } else {
    final cid = pages.first.cid;
    final track = Track(
      platform: bare.platform,
      id: '${bare.id}:$cid',
      name: bare.name,
      artist: bare.artist,
      album: bare.album,
      coverUrl: bare.coverUrl,
      durationMs: bare.durationMs,
    );
    final r2 = await source.resolvePlayUrl(track);
    print('[playurl · bvid:cid] ${track.id} → '
        'quality=${r2.grantedQuality?.name ?? "未知"} '
        'backups=${r2.backupUrls.length}');
    print('  url=${r2.url}');
    await _checkReachable(r2.url, r2.headers, notes, 'bvid:cid');
    notes.add('两种 id 形态都能取流（B2 定案 #3）');
  }

  // 3. 歌词恒空。
  final lyric = await source.fetchLyric(bare);
  print('[lyric] lines=${lyric.lines.length}（B 站无歌词接口，恒空）');
  notes.add('fetchLyric 恒空：${lyric.lines.isEmpty}');

  print('');
  print('== 速记 ==');
  for (final n in notes) {
    print('  $n');
  }
  print('== done ==');
}

/// 带 Source 下发的防盗链头请求直链，确认可达（B1 实测 206）。
Future<void> _checkReachable(
  String url,
  Map<String, String> headers,
  List<String> notes,
  String form,
) async {
  try {
    final resp = await Dio(BaseOptions(
      headers: headers,
      // 只要头：取 1 字节证明链路通，不真下整段。
      responseType: ResponseType.stream,
      validateStatus: (_) => true,
    )).get<void>(url, options: Options(
      headers: {...headers, 'Range': 'bytes=0-0'},
    ));
    print('  [http] $form status=${resp.statusCode}');
    notes.add('直链可达（$form）：HTTP ${resp.statusCode}（带 Referer/UA）');
  } catch (e) {
    print('  [http] $form 请求失败：$e');
    notes.add('直链不可达（$form）：$e');
  }
}

class _Args {
  _Args({required this.suites, required this.keyword});

  final List<String> suites;
  final String keyword;

  static _Args parse(List<String> args) {
    final suites = <String>[];
    var keyword = '周杰伦';
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--suite') {
        suites.addAll(args[++i].split(',').where((s) => s.isNotEmpty));
      } else if (a == '--keyword') {
        keyword = args[++i];
      }
    }
    return _Args(
      suites: suites.isEmpty ? const ['search', 'playurl'] : suites,
      keyword: keyword,
    );
  }
}
