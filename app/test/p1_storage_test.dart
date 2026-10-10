import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/audio_quality.dart';
import 'package:kugo/core/models/cloud_models.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/data/storage/kugo_db.dart';
import 'package:kugo/data/storage/playback_position_store.dart';
import 'package:kugo/data/storage/queue_store.dart';
import 'package:kugo/data/storage/track_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Track _track({MusicPlatform platform = MusicPlatform.kugou}) => Track(
  id: '42',
  name: 'fixture',
  artist: 'artist',
  album: 'album',
  coverUrl: 'https://example.invalid/art.jpg',
  durationMs: 180000,
  platform: platform,
  hash: 'hash',
  albumId: 'albumId',
  mixSongId: 'mix',
  artistId: 'artistId',
  quality: 'SQ',
  isVip: true,
  availableQualities: const {AppQuality.standard, AppQuality.sq},
  relateGoods: const [RelateGood(hash: 'lossless', quality: 'flac', level: 5)],
  qualityCatalogComplete: true,
  recDesc: 'recommend',
  similarDesc: 'similar',
  language: '国语',
  cloudFileId: '123',
  cloudAudioSource: const CloudAudioSource(
    hash: 'cloud-hash',
    cloudFileId: '123',
    hashStd: 'standard',
    audioId: 'audio',
    albumAudioId: 'album-audio',
    bitrate: 4,
    size: 1024,
    ext: 'flac',
    name: 'cloud-name',
    matchBy: CloudMatchBy.hashStd,
  ),
);

void _expectComplete(Track actual, Track expected) {
  expect(actual.identityKey, expected.identityKey);
  expect(actual.name, expected.name);
  expect(actual.durationMs, expected.durationMs);
  expect(actual.hash, expected.hash);
  expect(actual.albumId, expected.albumId);
  expect(actual.mixSongId, expected.mixSongId);
  expect(actual.quality, expected.quality);
  expect(actual.isVip, expected.isVip);
  expect(encodeTrackMetadata(actual), encodeTrackMetadata(expected));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late KugoDb db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = KugoDb.forTesting(NativeDatabase.memory());
    QueueStore.setDbForTesting(db);
  });
  tearDown(() async {
    QueueStore.setDbForTesting(null);
    await db.close();
  });

  test('R07 SQLite retains identical ids from different platforms', () async {
    await db.appendHistory(_track());
    await db.appendHistory(_track(platform: MusicPlatform.netease));
    expect((await db.readHistory()).map((t) => t.identityKey).toSet(), {
      'kugou:42',
      'netease:42',
    });
    await db.appendHistory(_track().copyWith(name: 'replayed'));
    expect(await db.countHistory(), 2);
    expect(
      (await db.readHistory())
          .where((t) => t.platform == MusicPlatform.kugou)
          .single
          .name,
      'replayed',
    );
  });

  test('R07 store cache and deletion are scoped to platform', () async {
    final store = await QueueStore.open();
    await store.appendHistory(_track());
    await store.appendHistory(_track(platform: MusicPlatform.netease));
    expect(store.loadHistory(), hasLength(2));
    await store.deleteHistory('42', platform: MusicPlatform.netease);
    expect(store.loadHistory().single.identityKey, 'kugou:42');
    expect((await db.readHistory()).single.identityKey, 'kugou:42');
  });

  test(
    'R07 history primary key includes platform even for equal timestamps',
    () async {
      await db.appendHistory(_track());
      final row = await db
          .customSelect('SELECT * FROM history_tracks')
          .getSingle();
      final time = row.read<int>('played_at');
      await db.customStatement(
        'INSERT INTO history_tracks SELECT track_metadata, played_at, track_id, '
        "name, artist, album, cover_url, duration_ms, hash, album_id, mix_song_id, "
        "quality, is_vip, 'netease' FROM history_tracks",
      );
      expect(
        (await db.readHistoryEntries()).map((e) => e.playedAt),
        everyElement(time),
      );
      expect(await db.countHistory(), 2);
    },
  );

  test(
    'R08 queue and both history APIs preserve full route metadata',
    () async {
      final track = _track();
      await db.writeQueue([track], 0, 'shuffle');
      final queue = (await db.readQueue())!;
      expect(queue.mode, 'shuffle');
      _expectComplete(queue.queue.single, track);
      await db.appendHistory(track);
      _expectComplete((await db.readHistory()).single, track);
      _expectComplete((await db.readHistoryEntries()).single.track, track);
      expect(queue.queue.single.isCloudTrack, isTrue);
      expect(queue.queue.single.cloudAudioSource!.audioId, 'audio');
    },
  );

  test('R08 metadata tolerates invalid JSON and future quality values', () {
    final track = _track().copyWith(cloudFileId: '');
    expect(decodeTrackMetadata(track, '{broken'), same(track));
    expect(
      decodeTrackMetadata(
        track,
        '{"availableQualities":["future","sq"]}',
      ).availableQualities,
      {AppQuality.sq},
    );
    expect(jsonDecode(encodeTrackMetadata(track)), isNot(contains('url')));
  });

  for (final version in [1, 2]) {
    test('R07/R08 real v$version SQLite migration preserves queue and history', () async {
      final old = sqlite.sqlite3.openInMemory();
      final platform = version == 2
          ? ", platform_name TEXT NOT NULL DEFAULT 'kugou'"
          : '';
      const columns =
          'track_id TEXT NOT NULL, name TEXT NOT NULL, '
          'artist TEXT NOT NULL, album TEXT NOT NULL, cover_url TEXT NOT NULL, '
          'duration_ms INTEGER NOT NULL, hash TEXT NOT NULL, album_id TEXT NOT NULL, '
          'mix_song_id TEXT NOT NULL, quality TEXT NOT NULL, is_vip INTEGER NOT NULL';
      old.execute(
        'CREATE TABLE queue_tracks (position INTEGER NOT NULL, $columns$platform, PRIMARY KEY(position))',
      );
      old.execute(
        'CREATE TABLE history_tracks (played_at INTEGER NOT NULL, $columns$platform, PRIMARY KEY(played_at,track_id))',
      );
      old.execute(
        'CREATE TABLE queue_meta (id INTEGER NOT NULL PRIMARY KEY, current_index INTEGER NOT NULL, mode TEXT NOT NULL)',
      );
      final values =
          "42, 'legacy', 'artist', 'album', '', 60000, 'hash', '', '', 'SQ', 0${version == 2 ? ", 'netease'" : ''}";
      old.execute('INSERT INTO queue_tracks VALUES (0, $values)');
      old.execute('INSERT INTO history_tracks VALUES (1000, $values)');
      old.execute("INSERT INTO queue_meta VALUES (0,0,'listLoop')");
      old.execute('PRAGMA user_version = $version');
      final migrated = KugoDb.forTesting(NativeDatabase.opened(old));
      try {
        final legacy = (await migrated.readQueue())!.queue.single;
        expect(
          legacy.platform,
          version == 2 ? MusicPlatform.netease : MusicPlatform.kugou,
        );
        expect(legacy.name, 'legacy');
        expect(legacy.artistId, '');
        expect(legacy.isCloudTrack, isFalse);
        expect(
          (await migrated.readHistory()).single.identityKey,
          legacy.identityKey,
        );
        await migrated.writeQueue([_track()], 0, 'order');
        _expectComplete((await migrated.readQueue())!.queue.single, _track());
        await migrated.appendHistory(_track());
        await migrated.appendHistory(_track(platform: MusicPlatform.netease));
        expect(await migrated.countHistory(), 2);
      } finally {
        await migrated.close();
      }
    });
  }

  test(
    'R12 serialized position save/clear retains last requested identity',
    () async {
      await Future.wait([
        PlaybackPositionStore.save('kugou:42', 111),
        PlaybackPositionStore.clear(),
        PlaybackPositionStore.save('netease:42', 222),
      ]);
      expect(await PlaybackPositionStore.load('netease:42'), 222);
      expect(await PlaybackPositionStore.load('kugou:42'), isNull);
    },
  );
}
