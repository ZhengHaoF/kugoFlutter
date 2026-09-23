import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/player/audio_service_handler.dart';
import 'package:kugo/features/player/player_controller.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_lyric_play_repos.dart';

Track _t(String id) => Track(
      id: id,
      name: id,
      artist: 'artist',
      album: 'album',
      coverUrl: 'mock://$id',
      durationMs: 10000,
    );

void main() {
  test('system media pause/stop actually pause the player', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // Regression: pause() used to be a copy of play() and did nothing here.
    await handler.pause();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);

    await handler.play();
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    await handler.stop();
    expect(container.read(playerControllerProvider).isPlaying, isFalse);
  });

  test('handler broadcasts duration, buffered position and seek action',
      () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    final state = handler.playbackState.value;
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.systemActions, contains(MediaAction.seek));
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 10));
    expect(
      () => state.position,
      returnsNormally,
      reason: 'handler must expose a monotonic media position',
    );
  });

  test('media position never goes backwards between pushes', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t(_songId)]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // Android's AVRCP target permanently stops emitting
    // EVENT_PLAYBACK_POS_CHANGED once two consecutive reads are equal, so every
    // position handed to the platform has to move strictly forward.
    await _exercisePositionPushes(engine, handler);
  });

  test('track switch resets media position despite leftover engine samples',
      () async {
    // Car head units read PlaybackState.updatePosition. If a leftover sample
    // from the previous source (10s into song A) re-anchors the media tick
    // while song B's URL is still resolving, song B's progress bar starts at
    // 10s. This is the regression that made FM/list skips look "mixed".
    final engine = FakeAudioPlayer();
    final play = FakePlayRepository();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider.overrideWith(
          () => PlayerController(engine: engine, playRepo: play),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    Track hashed(String id, String hash) => Track(
          id: id,
          name: id,
          artist: 'artist',
          album: 'album',
          coverUrl: 'https://example.com/$id.jpg',
          durationMs: 30000,
          hash: hash,
        );

    await controller.playQueue(
      [hashed('a', 'hash_a'), hashed('b', 'hash_b')],
      startIndex: 0,
    );
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // Song A is 10s in.
    engine.emitPosition(const Duration(milliseconds: 10000));
    await Future<void>.delayed(Duration.zero);
    expect(controller.position.value, 10000);

    // Hold URL resolve open so we can inject the previous source's leftovers.
    final gate = Completer<void>();
    play.gate = gate.future;
    final nextFuture = controller.next();
    await Future<void>.delayed(Duration.zero);

    engine.emitPosition(const Duration(milliseconds: 10000));
    engine.emitPosition(const Duration(milliseconds: 10200));
    await Future<void>.delayed(Duration.zero);

    gate.complete();
    await nextFuture;

    expect(container.read(playerControllerProvider).current?.id, 'b');
    // Leftovers during the switch must not drag the live cursor.
    expect(controller.position.value, 0);
    // Platform cursor is forced back to 0 with the new source.
    expect(handler.playbackState.value.updatePosition.inMilliseconds, 0);

    // One media tick later the car must still be near the start of song B —
    // without the fix the tick extrapolates from the leftover 10s base.
    engine.emitPosition(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final afterTick = handler.playbackState.value.updatePosition.inMilliseconds;
    expect(afterTick, lessThan(2000),
        reason: 'media tick continued from the previous track ($afterTick ms)');
  });

  test('swiping the notification away keeps the session usable', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a'), _t('b')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    // BaseAudioHandler.onNotificationDeleted() delegates to stop(), which drops
    // the service and deactivates the MediaSession for good. The next play()
    // would then have a dead session: no notification, no head-unit progress.
    await handler.onNotificationDeleted();
    final afterSwipe = handler.playbackState.value;
    expect(afterSwipe.playing, isFalse);
    expect(afterSwipe.processingState, AudioProcessingState.idle);
    expect(handler.mediaItem.value?.title, 'a',
        reason: 'metadata must survive a notification swipe');

    // The session has to come back for the next track.
    await handler.play();
    final resumed = handler.playbackState.value;
    expect(resumed.processingState, AudioProcessingState.ready);
    expect(resumed.playing, isTrue);
    expect(resumed.androidCompactActionIndices, [0, 1, 2],
        reason: 'carousel layout must stay fixed across a stop/start cycle');
  });

  test('carousel keeps a fixed 3-slot shape across play/pause', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    final shapes = <List<int>?>[];
    final controls = <List<MediaAction>>[];
    final sub = handler.playbackState.listen((state) {
      shapes.add(state.androidCompactActionIndices);
      controls.add([for (final c in state.controls) c.action]);
    });
    addTearDown(sub.cancel);

    await controller.playQueue([_t('a')]);
    await handler.pause();
    await handler.play();

    // A head unit caches the action list positionally; if the declared count
    // changes on pause the car's slots desynchronise and transport commands
    // (and the progress notifications they piggyback on) stop arriving.
    final declared = shapes.whereType<List<int>>().toSet();
    expect(declared, {
      const [0, 1, 2]
    }, reason: 'compact slot layout changed at runtime: $shapes');
    final last = controls.last;
    expect(last, [
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
    ]);
  });

  // ── 通知栏/锁屏「歌曲信息卡」验收（docs/gap-vs-echomusic.md §三）─────────
  // 前置：测试环境已视为「通知权限已授予」（Q9）；主路径在 mediaLyricSubtitle
  // 关闭时断言（Q10-D）。实现与锁屏共用 MediaItem/PlaybackState（Q6-B）。

  test('notification card MediaItem carries song identity (acceptance C)', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    final track = Track(
      id: 'song_1',
      name: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      coverUrl: 'https://img.example/cover_qingtian.jpg',
      durationMs: 269000,
    );
    await controller.playQueue([track]);

    final item = handler.mediaItem.value;
    expect(item, isNotNull, reason: '播放中系统媒体卡必须有 MediaItem');
    expect(item!.title, '晴天');
    // 主验收：歌词副标题关闭时 artist 必须等于 track.artist（Q10-D）。
    expect(item.artist, '周杰伦');
    expect(item.album, '叶惠美');
    expect(item.duration, const Duration(milliseconds: 269000));
    // Q5-B：artUri 非空且指向该曲 cover；实机大图渲染另作抽测。
    expect(item.artUri, isNotNull);
    expect(item.artUri.toString(), 'https://img.example/cover_qingtian.jpg');

    final state = handler.playbackState.value;
    final actions = [for (final c in state.controls) c.action];
    expect(state.processingState, AudioProcessingState.ready);
    expect(actions, contains(MediaAction.pause), reason: '播放中至少要有暂停');
    expect(state.systemActions, contains(MediaAction.playPause));
  });

  test('paused session still exposes card fields (acceptance lifecycle B)',
      () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    await handler.pause();

    final state = handler.playbackState.value;
    // Q4-B：有 track 且未 idle —— 暂停中卡片信息仍在，不得掉成 idle。
    expect(state.playing, isFalse);
    expect(state.processingState, AudioProcessingState.ready,
        reason: '暂停不得把会话标成 idle，否则锁屏/通知栏无卡片');
    expect(handler.mediaItem.value?.title, 'a');
    expect(handler.mediaItem.value?.artist, 'artist');
    final actions = [for (final c in state.controls) c.action];
    expect(actions, contains(MediaAction.play), reason: '暂停后仍要能播放');
  });

  test('stop() drops session to idle (card may disappear)', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    await handler.stop();

    // Q4-B：主动 stop 允许消失；产品不保证 stop 后通知栏仍有卡。
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
  });

  test('FM tracks use the same notification card path (acceptance A/FM)', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    // Q8-A：FM 无第二条通知链路，同一 PlayerController → KugoAudioHandler。
    final fmTrack = Track(
      id: 'fm_1',
      name: '夜曲',
      artist: '周杰伦',
      album: '十一月的萧邦',
      coverUrl: 'https://img.example/fm_yequ.jpg',
      durationMs: 226000,
      recDesc: '口味推荐',
    );
    await controller.playQueue([fmTrack]);

    final item = handler.mediaItem.value;
    expect(item?.title, '夜曲');
    expect(item?.artist, '周杰伦');
    expect(item?.artUri.toString(), 'https://img.example/fm_yequ.jpg');
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.ready);
  });

  test('stop() pauses the engine and holds the queue', () async {
    final engine = FakeAudioPlayer();
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: engine)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(playerControllerProvider.notifier);
    final handler = KugoAudioHandler(controller);
    controller.attachBridge(handler);

    await controller.playQueue([_t('a')]);
    expect(container.read(playerControllerProvider).isPlaying, isTrue);

    await handler.stop();

    // stop() used to only broadcast idle, leaving the engine playing behind a
    // session the system had already torn down.
    expect(controller.snapshot.isPlaying, isFalse);
    expect(controller.snapshot.display, PlayerDisplayState.idle);
    expect(container.read(playerControllerProvider).queue.length, 1,
        reason: 'queue is kept so the user can resume');
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.idle);
  });
}

const _songId = 'a';

/// Drive engine samples and timer pushes for a while, then assert the sequence
/// of positions handed to the platform was strictly increasing.
///
/// Android's AVRCP target permanently stops emitting
/// EVENT_PLAYBACK_POS_CHANGED once two consecutive reads return the same value,
/// so a position that stalls or steps backwards kills the car progress bar for
/// good. Asserting on the recorded sequence (rather than inside the listener)
/// keeps the failure message readable instead of retrying per event.
Future<void> _exercisePositionPushes(
  FakeAudioPlayer engine,
  KugoAudioHandler handler,
) async {
  final pushed = <int>[];
  final sub = handler.playbackState.listen(
    (state) => pushed.add(state.updatePosition.inMilliseconds),
  );
  addTearDown(sub.cancel);

  // ~4s of wall clock: long enough to cross several timer/stream mismatches.
  for (var tick = 0; tick < 40; tick++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    engine.emitPosition(Duration(milliseconds: tick * 100));
  }

  expect(pushed.length, greaterThan(1), reason: 'no position pushes recorded');
  for (var i = 1; i < pushed.length; i++) {
    if (pushed[i] <= pushed[i - 1]) {
      fail(
        'position stalled or went backwards at push #$i: '
        '${pushed[i - 1]}ms -> ${pushed[i]}ms\n'
        'full sequence: $pushed',
      );
    }
  }
}
