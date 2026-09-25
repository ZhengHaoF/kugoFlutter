// 酷狗「游客态」可用性探针。
//
// 目的：回答「没登录酷狗时，搜索/热搜/榜单/每日推荐/FM/播放 到底能不能用」，
// 给「(源 × 功能) 是否需要登录」的显隐矩阵提供事实依据。
//
// 与 windows_audio_probe.dart 的区别：那个探针要登录态（B 段），本探针刻意
// **不 seed 任何 token**，全部走匿名请求，即产品里「游客继续，先听歌」的状态。
//
// 用法（必须走 flutter test：日推/FM/播放要 Flutter binding）：
//   flutter test --no-pub tool/probe_kugou_guest.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/sources/kugou/kugou_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单条探针结果，最后汇总成矩阵。
final Map<String, String> _matrix = {};

Future<void> _probe<T>(
  String key,
  Future<T> Function() run,
  String Function(T value) summary,
) async {
  final sw = Stopwatch()..start();
  try {
    final value = await run();
    sw.stop();
    final cost = '${sw.elapsedMilliseconds}ms'.padLeft(8);
    final msg = summary(value);
    _matrix[key] = msg;
    print('[${key.padRight(9)}] OK   $cost  $msg');
  } catch (e) {
    sw.stop();
    final cost = '${sw.elapsedMilliseconds}ms'.padLeft(8);
    final msg = e.toString().split('\n').first.trim();
    _matrix[key] = 'FAIL: $msg';
    print('[${key.padRight(9)}] FAIL $cost  $msg');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认把 HttpClient 换成「一律返回 400」的假实现，这里还原真网络。
  HttpOverrides.global = null;
  // 空 prefs == 无 token == 游客态。
  SharedPreferences.setMockInitialValues({});

  test('kugou guest matrix', () async {
    final src = KugouSource();

    print('== kugou guest probe (no token) ==');

    await _probe(
      'search',
      () => src.searchSongs('晴天', pageSize: 3),
      (r) => 'items=${r.items.length} total=${r.total}'
          '${r.items.isEmpty ? '' : ' first=${r.items.first.name}'}',
    );

    await _probe(
      'hot',
      () => src.hotKeywords(count: 10),
      (r) => 'count=${r.length}${r.isEmpty ? '' : ' first=${r.first}'}',
    );

    var firstBoardId = '';
    await _probe(
      'rankBoards',
      () => src.rankBoards(),
      (r) {
        if (r.isNotEmpty) firstBoardId = r.first.id;
        return 'boards=${r.length}'
            '${r.isEmpty ? '' : ' first=${r.first.name}(${r.first.id})'}';
      },
    );

    if (firstBoardId.isNotEmpty) {
      await _probe(
        'rankTracks',
        () => src.rankTracks(firstBoardId, page: 1),
        (r) => 'tracks=${r.length}${r.isEmpty ? '' : ' first=${r.first.name}'}',
      );
    } else {
      print('[rankTracks] SKIP      无可用榜单 id');
    }

    await _probe(
      'daily',
      () => src.dailyRecommend(),
      (r) => 'tracks=${r.tracks.length}'
          '${r.isEmpty ? '' : ' first=${r.tracks.first.name}'}',
    );

    await _probe(
      'fm',
      () => src.nextFmTracks(remain: 3),
      (r) => 'tracks=${r.length}${r.isEmpty ? '' : ' first=${r.first.name}'}',
    );

    await _probe(
      'quality',
      () async {
        final r = await src.searchSongs('晴天', pageSize: 1);
        if (r.items.isEmpty) return null;
        return src.fetchQualityCatalog(r.items.first);
      },
      (r) => r == null
          ? 'SKIP 搜索无结果'
          : 'goods=${r.goods.length} complete=${r.catalogComplete}',
    );

    await _probe(
      'play',
      () async {
        final r = await src.searchSongs('晴天', pageSize: 1);
        if (r.items.isEmpty) return null;
        return src.resolvePlayUrl(r.items.first);
      },
      (r) => r == null
          ? 'SKIP 搜索无结果'
          : 'url=${r.url.isEmpty ? '(空)' : 'len=${r.url.length}'}',
    );

    print('== done ==');
  });
}
