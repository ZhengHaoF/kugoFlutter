import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/track.dart';

part 'kugo_db.g.dart';

/// One row of the current play queue (ordered by [position]).
class QueueTracks extends Table {
  IntColumn get position => integer()();
  TextColumn get trackId => text()();
  TextColumn get name => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get coverUrl => text()();
  IntColumn get durationMs => integer()();
  TextColumn get hash => text()();
  TextColumn get albumId => text()();
  TextColumn get mixSongId => text()();
  TextColumn get quality => text()();
  BoolColumn get isVip => boolean()();

  @override
  Set<Column> get primaryKey => {position};
}

/// Singleton row (id=0): queue index + loop mode.
class QueueMeta extends Table {
  IntColumn get id => integer()();
  IntColumn get currentIndex => integer()();
  TextColumn get mode => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Play history, newest first via [playedAt].
class HistoryTracks extends Table {
  IntColumn get playedAt => integer()();
  TextColumn get trackId => text()();
  TextColumn get name => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get coverUrl => text()();
  IntColumn get durationMs => integer()();
  TextColumn get hash => text()();
  TextColumn get albumId => text()();
  TextColumn get mixSongId => text()();
  TextColumn get quality => text()();
  BoolColumn get isVip => boolean()();

  @override
  Set<Column> get primaryKey => {playedAt, trackId};
}

Track _trackFrom({
  required String id,
  required String name,
  required String artist,
  required String album,
  required String coverUrl,
  required int durationMs,
  required String hash,
  required String albumId,
  required String mixSongId,
  required String quality,
  required bool isVip,
}) {
  return Track(
    id: id,
    name: name,
    artist: artist,
    album: album,
    coverUrl: coverUrl,
    durationMs: durationMs,
    hash: hash,
    albumId: albumId,
    mixSongId: mixSongId,
    quality: quality,
    isVip: isVip,
  );
}

Track _prefsTrack(Map<String, dynamic> j) => _trackFrom(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      artist: j['artist']?.toString() ?? '',
      album: j['album']?.toString() ?? '',
      coverUrl: j['coverUrl']?.toString() ?? '',
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      hash: j['hash']?.toString() ?? '',
      albumId: j['albumId']?.toString() ?? '',
      mixSongId: j['mixSongId']?.toString() ?? '',
      quality: j['quality']?.toString() ?? 'SQ',
      isVip: j['isVip'] == true,
    );

List<Track> _decodePrefsList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = (jsonDecode(raw) as List).whereType<Map>().map((e) {
      return _prefsTrack(Map<String, dynamic>.from(e));
    }).where((t) => t.id.isNotEmpty || t.hash.isNotEmpty).toList();
    return list;
  } catch (_) {
    return const [];
  }
}

@DriftDatabase(tables: [QueueTracks, QueueMeta, HistoryTracks])
class KugoDb extends _$KugoDb {
  KugoDb([QueryExecutor? executor]) : super(executor ?? _open());

  KugoDb.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'kugo', 'kugo.sqlite'));
      await file.parent.create(recursive: true);
      return NativeDatabase.createInBackground(file);
    });
  }

  Future<void> writeQueue(List<Track> queue, int index, String mode) async {
    await transaction(() async {
      await delete(queueTracks).go();
      await batch((b) {
        b.insertAll(queueTracks, [
          for (var i = 0; i < queue.length; i++)
            QueueTracksCompanion.insert(
              position: Value(i),
              trackId: queue[i].id,
              name: queue[i].name,
              artist: queue[i].artist,
              album: queue[i].album,
              coverUrl: queue[i].coverUrl,
              durationMs: queue[i].durationMs,
              hash: queue[i].hash,
              albumId: queue[i].albumId,
              mixSongId: queue[i].mixSongId,
              quality: queue[i].quality,
              isVip: queue[i].isVip,
            ),
        ]);
      });
      await into(queueMeta).insertOnConflictUpdate(
        QueueMetaCompanion.insert(
          id: const Value(0),
          currentIndex: index,
          mode: mode,
        ),
      );
    });
  }

  Future<({List<Track> queue, int index, String mode})?> readQueue() async {
    final meta =
        await (select(queueMeta)..where((t) => t.id.equals(0))).getSingleOrNull();
    if (meta == null) return null;
    final rows = await (select(queueTracks)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    if (rows.isEmpty) return null;
    return (
      queue: [
        for (final row in rows)
          _trackFrom(
            id: row.trackId,
            name: row.name,
            artist: row.artist,
            album: row.album,
            coverUrl: row.coverUrl,
            durationMs: row.durationMs,
            hash: row.hash,
            albumId: row.albumId,
            mixSongId: row.mixSongId,
            quality: row.quality,
            isVip: row.isVip,
          ),
      ],
      index: meta.currentIndex,
      mode: meta.mode,
    );
  }

  Future<void> appendHistory(Track track) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await (delete(historyTracks)..where((t) => t.trackId.equals(track.id)))
          .go();
      await into(historyTracks).insert(
        HistoryTracksCompanion.insert(
          playedAt: now,
          trackId: track.id,
          name: track.name,
          artist: track.artist,
          album: track.album,
          coverUrl: track.coverUrl,
          durationMs: track.durationMs,
          hash: track.hash,
          albumId: track.albumId,
          mixSongId: track.mixSongId,
          quality: track.quality,
          isVip: track.isVip,
        ),
        mode: InsertMode.insertOrReplace,
      );
      final count = await historyTracks.count().getSingle();
      if (count > 200) {
        final old = await (select(historyTracks)
              ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
              ..limit(count - 200, offset: 200))
            .get();
        for (final row in old) {
          await (delete(historyTracks)
                ..where(
                  (t) =>
                      t.playedAt.equals(row.playedAt) &
                      t.trackId.equals(row.trackId),
                ))
              .go();
        }
      }
    });
  }

  Future<List<Track>> readHistory() async {
    final rows = await (select(historyTracks)
          ..orderBy([(t) => OrderingTerm.desc(t.playedAt)]))
        .get();
    return [
      for (final row in rows)
        _trackFrom(
          id: row.trackId,
          name: row.name,
          artist: row.artist,
          album: row.album,
          coverUrl: row.coverUrl,
          durationMs: row.durationMs,
          hash: row.hash,
          albumId: row.albumId,
          mixSongId: row.mixSongId,
          quality: row.quality,
          isVip: row.isVip,
        ),
    ];
  }

  Future<void> clearAll() async {
    await transaction(() async {
      await delete(queueTracks).go();
      await delete(queueMeta).go();
      await delete(historyTracks).go();
    });
  }

  /// One-time import from legacy SharedPreferences keys.
  Future<void> migrateFromPrefs(SharedPreferences prefs) async {
    const kQueue = 'player.queue.v1';
    const kIndex = 'player.index.v1';
    const kMode = 'player.mode.v1';
    const kHistory = 'player.history.v1';
    const kMigrated = 'player.drift_migrated.v1';
    if (prefs.getBool(kMigrated) == true) return;

    final hasLegacy = prefs.containsKey(kQueue) ||
        prefs.containsKey(kHistory) ||
        prefs.containsKey(kIndex);
    if (!hasLegacy) {
      await prefs.setBool(kMigrated, true);
      return;
    }

    final queue = _decodePrefsList(prefs.getString(kQueue));
    final history = _decodePrefsList(prefs.getString(kHistory));
    if (queue.isNotEmpty) {
      await writeQueue(
        queue,
        prefs.getInt(kIndex) ?? 0,
        prefs.getString(kMode) ?? 'listLoop',
      );
    }
    if (history.isNotEmpty) {
      for (final t in history) {
        await appendHistory(t);
      }
    }
    await prefs.setBool(kMigrated, true);
  }
}
