import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/storage/kugo_db.dart';

/// Play-history counting backs the「最近播放」badge on the profile page.
/// A plain `loadHistoryAsync().length` would drag up to 200 tracks through
/// Dart objects just to render one number, so the count goes to SQL.
void main() {
  late KugoDb db;

  setUp(() => db = KugoDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Track t(String id) => Track(
        id: id,
        name: 'name $id',
        artist: 'artist',
        album: 'album',
        coverUrl: '',
        durationMs: 1000,
      );

  test('countHistory is 0 on an empty database', () async {
    expect(await db.countHistory(), 0);
  });

  test('countHistory matches the sealed history length', () async {
    for (final id in ['a', 'b', 'c']) {
      await db.appendHistory(t(id));
    }
    expect(await db.countHistory(), 3);
    expect(await db.countHistory(), (await db.readHistory()).length);
  });

  test('replaying a track does not inflate the count', () async {
    await db.appendHistory(t('a'));
    await db.appendHistory(t('b'));
    await db.appendHistory(t('a'));
    // appendHistory deletes the prior row for the same trackId first.
    expect(await db.countHistory(), 2);
  });

  test('countHistory reflects clearAll', () async {
    await db.appendHistory(t('a'));
    expect(await db.countHistory(), 1);
    await db.clearAll();
    expect(await db.countHistory(), 0);
  });

  test('history is capped at 200 rows by appendHistory', () async {
    for (var i = 0; i < 205; i++) {
      await db.appendHistory(t('t$i'));
    }
    expect(await db.countHistory(), 200);
  });
}
