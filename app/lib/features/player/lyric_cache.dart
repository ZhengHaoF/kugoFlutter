import '../../core/models/track.dart';

/// 歌词结果 LRU 缓存 + 在途请求去重（对齐 EchoMusic `lyricResultCache` /
/// `inflightLyricHash`）。
///
/// 键是 [Track.identityKey]（`platform:id`）。为什么需要它：取词链是
/// 「搜候选 → 下 KRC/LRC 解密」，一次几跳网络；没有缓存时来回切「上一首 /
/// 下一首」会把整条链重跑一遍。
///
/// 只缓存**非空**结果 —— 空结论交给
/// `PlayerController.ensureLyricsForCurrent(retryIfEmpty: true)` 的「每曲补试
/// 一次」语义处理（网络恢复后还能再试）；把空结论缓存住会把这条路堵死。
class LyricCache {
  LyricCache({this.capacity = kLyricCacheCapacity}) : assert(capacity > 0);

  /// 一次会话内最多记住多少首曲目的歌词。32 与 EchoMusic 的同名常量对齐，
  /// 足够覆盖「前一 / 前二首」来回切的实际使用。
  static const int kLyricCacheCapacity = 32;

  final int capacity;

  /// 插入序即 LRU 序（Dart Map 保持插入顺序）：读命中把键挪到队尾，
  /// 超容量时从队首淘汰。
  final Map<String, List<LyricLine>> _results = {};

  /// 同键在途请求：切歌瞬间可能有多个调用点（起播 + 播放页 watch）同时触发，
  /// 合并成一次网络请求。
  final Map<String, Future<List<LyricLine>>> _inflight = {};

  /// 已缓存条数（测试 / 诊断用）。
  int get length => _results.length;

  /// 是否有在途请求（测试 / 诊断用）。
  bool get hasInflight => _inflight.isNotEmpty;

  /// 命中返回缓存行；未命中返回 null。命中会把它标记为最近使用。
  List<LyricLine>? get(String key) {
    final hit = _results.remove(key);
    if (hit == null) return null;
    _results[key] = hit;
    return hit;
  }

  /// 写入结果。空结果不入缓存（见类注释）；超出容量淘汰最久未用的条目。
  void put(String key, List<LyricLine> lines) {
    if (key.isEmpty || lines.isEmpty) return;
    _results.remove(key);
    _results[key] = lines;
    while (_results.length > capacity) {
      _results.remove(_results.keys.first);
    }
  }

  /// 「命中 / 在途 / 新请求」三态合一。
  ///
  /// 同键并发只调用一次 [loader]；[loader] 抛错时原样上抛且不缓存，
  /// 调用方可以重试。
  Future<List<LyricLine>> load(
    String key,
    Future<List<LyricLine>> Function() loader,
  ) {
    final cached = get(key);
    if (cached != null) return Future.value(cached);
    final flying = _inflight[key];
    if (flying != null) return flying;

    final future = loader().then(
      (lines) {
        _inflight.remove(key);
        put(key, lines);
        return lines;
      },
      onError: (Object error, StackTrace stack) {
        _inflight.remove(key);
        return Future<List<LyricLine>>.error(error, stack);
      },
    );
    _inflight[key] = future;
    return future;
  }

  void clear() {
    _results.clear();
    _inflight.clear();
  }
}
