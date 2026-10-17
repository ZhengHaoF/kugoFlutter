import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overtone/core/models/playback_source.dart';
import 'package:overtone/core/models/track.dart';
import 'package:overtone/core/source/music_source.dart';
import 'package:overtone/data/storage/overtone_db.dart';
import 'package:overtone/data/storage/queue_store.dart';
import 'package:overtone/features/player/player_controller.dart';
import 'package:overtone/features/player/shuffle_order.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 10000,
    );

/// 非 demo 曲目（http 封面）：冷启动恢复的过滤器只放行这类。
Track _http(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'https://example.invalid/$id.jpg',
      durationMs: 10000,
    );

List<String> _idsOf(PlayerState s) =>
    [for (final t in s.queue) t.id];

ProviderContainer _containerWithFake() {
  final engine = FakeAudioPlayer();
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(() => PlayerController(engine: engine)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('queue advance and wrap by listLoop', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a'), _t('b')], startIndex: 0);
    expect(container.read(playerControllerProvider).current?.id, 'a');

    controller.seekTo(3000);
    expect(container.read(playerControllerProvider).positionMs, 3000);

    await controller.next();
    final afterNext = container.read(playerControllerProvider);
    expect(afterNext.current?.id, 'b');
    expect(afterNext.positionMs, 0);

    await controller.next();
    expect(container.read(playerControllerProvider).current?.id, 'a');
  });

  test('seek clamps to duration', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.seekTo(999999);
    expect(container.read(playerControllerProvider).positionMs, 10000);

    controller.seekTo(-100);
    expect(container.read(playerControllerProvider).positionMs, 0);
  });

  test('toggle play pauses timer state', () async {
    final container = _containerWithFake();
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
  });

  test('user pause wins over late engine playing=true', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).display,
        PlayerDisplayState.paused);

    // Late engine event must not flip the icon against explicit pause.
    await engine.play();
    expect(container.read(playerControllerProvider).display,
        PlayerDisplayState.paused);
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
  });

  test('demo track toggle after pause resumes without resolve', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    await controller.playQueue([_t('a')]);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
    controller.togglePlay();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);
  });

  test('hash track fails resolve cleanly without inventing play', () async {
    final engine = FakeAudioPlayer();
    final source = FakeMusicSource()
      ..nextPlayUrl = null
      ..playError = const NotFound('offline');
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine, source: source),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);

    final hashed = Track(
      id: 'h1',
      name: 'h1',
      artist: 'a',
      album: 'b',
      coverUrl: 'https://example.com/h1.jpg',
      durationMs: 10000,
      hash: 'hash_h1',
    );
    await controller.playQueue([hashed]);
    final state = container.read(playerControllerProvider);
    // Offline / blocked network → error, must not fake-playing forever.
    expect(state.isPlaying, isFalse);
    expect(engine.lastUrl, isNull);
    expect(
      state.display == PlayerDisplayState.error ||
          state.display == PlayerDisplayState.loading,
      isTrue,
    );
  });

  group('shuffle', () {
    setUp(() => debugShuffleRandom = Random(20240517));
    tearDown(() => debugShuffleRandom = null);

    test('entering shuffle pins the current track and permutes the rest',
        () async {
      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);

      final ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      await controller.playQueue(ids.map(_t).toList(), startIndex: 3);
      expect(controller.snapshot.current?.id, 'd');

      controller.setMode(PlayerLoopMode.shuffle);
      final s = controller.snapshot;
      expect(s.mode, PlayerLoopMode.shuffle);
      // 不跳歌：当前曲目与游标都留在原位。
      expect(s.currentIndex, 3);
      expect(s.current?.id, 'd');
      // 同一批曲目的一个排列（固定种子下确实重排了）。
      expect(_idsOf(s), unorderedEquals(ids));
      expect(_idsOf(s), isNot(equals(ids)));
    });

    test('next() walks the whole shuffled queue once, then re-shuffles',
        () async {
      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);

      final ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      await controller.playQueue(ids.map(_t).toList());
      controller.setMode(PlayerLoopMode.shuffle);

      final played = <String>[controller.snapshot.current!.id];
      for (var i = 0; i < ids.length - 1; i++) {
        await controller.next();
        played.add(controller.snapshot.current!.id);
      }
      // 一整轮随机播放：每首恰好一次——不重复、不遗漏。
      expect(played, hasLength(ids.length));
      expect(played.toSet(), ids.toSet());

      // 环绕：重洗后从 0 开始，且不会立即重播刚播完那首。
      final last = controller.snapshot.current!.id;
      await controller.next();
      final s = controller.snapshot;
      expect(s.currentIndex, 0);
      expect(s.current?.id, isNot(last));
      expect(_idsOf(s).toSet(), ids.toSet());
    });

    test('previous() returns to the track played before in shuffle order',
        () async {
      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);

      await controller.playQueue(['a', 'b', 'c', 'd'].map(_t).toList());
      controller.setMode(PlayerLoopMode.shuffle);
      final first = controller.snapshot.current!.id;
      await controller.next();
      final second = controller.snapshot.current!.id;
      expect(second, isNot(first));

      await controller.previous();
      expect(controller.snapshot.current?.id, first);
    });

    test('FM queue refuses shuffle and never reorders', () async {
      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);

      await controller.playQueue(
        ['a', 'b', 'c'].map(_t).toList(),
        source: PlaybackQueueSource.fm,
      );
      controller.setMode(PlayerLoopMode.shuffle);
      var s = controller.snapshot;
      expect(s.mode, PlayerLoopMode.listLoop);
      expect(_idsOf(s), ['a', 'b', 'c']);

      // 随机模式下进来的 FM 队列也保持推荐序。
      controller.setMode(PlayerLoopMode.shuffle); // 仍然进不去
      controller.setMode(PlayerLoopMode.listLoop);
      await controller.playQueue(
        ['x', 'y', 'z'].map(_t).toList(),
        source: PlaybackQueueSource.fm,
      );
      s = controller.snapshot;
      expect(_idsOf(s), ['x', 'y', 'z']);
    });

    test('playQueue under shuffle pins the picked track', () async {
      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);

      await controller.playQueue(['a', 'b', 'c'].map(_t).toList());
      controller.setMode(PlayerLoopMode.shuffle);

      final ids = ['w', 'x', 'y', 'z'];
      await controller.playQueue(ids.map(_t).toList(), startIndex: 2);
      final s = controller.snapshot;
      expect(s.mode, PlayerLoopMode.shuffle); // 模式跨队列保留
      expect(s.currentIndex, 2);
      expect(s.current?.id, 'y'); // 点中的那首钉在起点
      expect(_idsOf(s), unorderedEquals(ids));
    });

    test('restore re-shuffles a persisted shuffle queue; FM claim rolls back',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final db = OvertoneDb.forTesting(NativeDatabase.memory());
      QueueStore.setDbForTesting(db);
      addTearDown(() async {
        QueueStore.setDbForTesting(null);
        await db.close();
      });

      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      await db.writeQueue(ids.map(_http).toList(), 2, 'shuffle');

      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);
      await controller.restoreOrSeed();
      // 恢复路径里挂着未await的歌词/落盘，排空再断言。
      await pumpEventQueue();

      var s = controller.snapshot;
      expect(s.mode, PlayerLoopMode.shuffle);
      expect(s.currentIndex, 2);
      expect(s.current?.id, 'c'); // 钉住的还是原来那首
      expect(_idsOf(s), unorderedEquals(ids));
      expect(_idsOf(s), isNot(equals(ids))); // 旧数据也被洗了

      // FM 认领：回滚原顺序 + mode 降级，会话（游标/当前曲目）无损。
      controller.markQueueSource(PlaybackQueueSource.fm);
      await pumpEventQueue();
      s = controller.snapshot;
      expect(s.queueSource, PlaybackQueueSource.fm);
      expect(s.mode, PlayerLoopMode.listLoop);
      expect(_idsOf(s), equals(ids));
      expect(s.currentIndex, 2);
      expect(s.current?.id, 'c');
    });

    test('restore keeps a non-shuffle queue untouched', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final db = OvertoneDb.forTesting(NativeDatabase.memory());
      QueueStore.setDbForTesting(db);
      addTearDown(() async {
        QueueStore.setDbForTesting(null);
        await db.close();
      });

      final ids = ['a', 'b', 'c', 'd'];
      await db.writeQueue(ids.map(_http).toList(), 1, 'listLoop');

      final container = _containerWithFake();
      final controller = container.read(playerControllerProvider.notifier);
      await controller.restoreOrSeed();
      await pumpEventQueue();

      final s = controller.snapshot;
      expect(s.mode, PlayerLoopMode.listLoop);
      expect(_idsOf(s), equals(ids));
      expect(s.currentIndex, 1);
    });
  });
}
