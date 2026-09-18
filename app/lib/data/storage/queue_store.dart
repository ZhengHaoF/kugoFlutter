import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';
import 'kugo_db.dart';

/// Queue + play-history persistence backed by Drift (SQLite).
///
/// Keeps the old sync-looking API used by player/settings/history by
/// priming in-memory caches on [open] (and after writes).
/// Legacy SharedPreferences data is imported once.
class QueueStore {
  QueueStore._(this._db);

  final KugoDb _db;

  static KugoDb? _dbCache;
  static Future<QueueStore>? _opening;

  ({List<Track> queue, int index, String mode})? _queueCache;
  List<Track> _historyCache = const [];

  static Future<QueueStore> open() {
    return _opening ??= () async {
      final prefs = await SharedPreferences.getInstance();
      final db = _dbCache ??= KugoDb();
      await db.migrateFromPrefs(prefs);
      final store = QueueStore._(db);
      await store.prime();
      return store;
    }();
  }

  Future<void> prime() async {
    try {
      _queueCache = await _db.readQueue();
      _historyCache = await _db.readHistory();
    } catch (_) {
      _queueCache = null;
      _historyCache = const [];
    }
  }

  Future<void> saveQueue(List<Track> queue, int index, String mode) async {
    await _db.writeQueue(queue, index, mode);
    _queueCache = (queue: queue, index: index, mode: mode);
  }

  /// Sync snapshot (caches filled by [open]/[saveQueue]/[prime]).
  ({List<Track> queue, int index, String mode})? loadQueue() => _queueCache;

  Future<({List<Track> queue, int index, String mode})?>
      loadQueueAsync() async {
    final q = await _db.readQueue();
    _queueCache = q;
    return q;
  }

  Future<void> appendHistory(Track track) async {
    await _db.appendHistory(track);
    final next = [track, ..._historyCache.where((t) => t.id != track.id)];
    _historyCache =
        next.length > 200 ? next.sublist(0, 200) : List.unmodifiable(next);
  }

  List<Track> loadHistory() => _historyCache;

  Future<List<Track>> loadHistoryAsync() async {
    final h = await _db.readHistory();
    _historyCache = h;
    return h;
  }

  Future<void> clearAll() async {
    await _db.clearAll();
    _queueCache = null;
    _historyCache = const [];
  }
}
