import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/playback_source.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 抽干微任务/定时器，让所有 `unawaited` 的后台取歌跑完。
Future<void> _drain([int rounds = 24]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

typedef _Rig = ({
  ProviderContainer container,
  ScriptedFmSource source,
  FakeAudioPlayer engine,
});

Future<_Rig> _rig({
  int perKeyword = 4,
  List<int> durations = const [],
  List<Track> fmServerTracks = const [],
  SourceFailure? fmServerFailure,
  bool loggedIn = false,
}) async {
  // start() 会 await AuthController.ensureReady()：prefs 里没有会话时会清掉
  // AuthTokenHolder，网关路径就永远进不去。登录用例必须先写好本地会话。
  SharedPreferences.setMockInitialValues({
    // 已注册设备身份：避免 restore/start 去打风控注册接口。
    'kugo_device_dfid_registered': true,
    'kugo_device_dfid': 'test-dfid',
    'kugo_device_guid': 'test-guid',
    if (loggedIn)
      'auth.user.v1':
          'userId=1001&token=valid_token&nickname=t&avatarUrl=&isVip=false&isLocalDemo=false&t1=',
  });
  final engine = FakeAudioPlayer();
  // 取数一律经全局注册表（控制器不再直连 Repository）。
  final source = ScriptedFmSource(
    perKeyword: perKeyword,
    durations: durations,
    serverTracks: fmServerTracks,
    serverFailure: fmServerFailure,
  );
  musicSourceRegistry = MusicSourceRegistry([source]);
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(() => PlayerController(engine: engine)),
    ],
  );
  return (container: container, source: source, engine: engine);
}

PlayerState _player(ProviderContainer c) => c.read(playerControllerProvider);
FmSession _fm(ProviderContainer c) => c.read(fmControllerProvider);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FM session start', () {
    test('start seeds from every keyword of the pool, not just one', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(r.source.searchCalls.toSet(), {'热门', '华语流行', '经典'});
      expect(_player(r.container).queue.length, 12);
      expect(_player(r.container).queueSource, PlaybackQueueSource.fm);
      expect(_fm(r.container).active, isTrue);
    });

    test('queue is handed to the player as an FM stream, not a playlist',
        () async {
      final r = await _rig();
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      final player = _player(r.container);
      expect(player.queueSource, PlaybackQueueSource.fm);
      expect(player.currentIndex, 0);
      expect(player.canStepBack, isFalse, reason: '会话第一首不能回退');
    });
  });

  group('FM axes', () {
    test('switching the pool is pending until the next track', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);

      await fm.start();
      await _drain();
      final before = _player(r.container).current!.id;

      fm.setPendingPool(FmSongPool.explore);

      // 待生效：会话状态变了，但队列/当前曲目都没动。
      expect(_fm(r.container).pendingPool, FmSongPool.explore);
      expect(_fm(r.container).hasPendingChange, isTrue);
      expect(_player(r.container).current!.id, before);
    });

    test('crossing to the next track applies the pending pool', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);

      await fm.start();
      await _drain();
      fm.setPendingPool(FmSongPool.explore);
      await r.container.read(playerControllerProvider.notifier).next();
      await _drain();

      expect(_fm(r.container).pool, FmSongPool.explore);
      expect(_fm(r.container).hasPendingChange, isFalse);
      expect(r.source.searchCalls, containsAll(['独立', '冷门', '爵士']));
    });

    test('applyPendingNow restarts the session immediately', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);

      await fm.start();
      await _drain();
      fm.setPendingMode(FmMode.niche);
      await fm.applyPendingNow();
      await _drain();

      expect(_fm(r.container).mode, FmMode.niche);
      expect(_player(r.container).currentIndex, 0);
      expect(
        r.source.searchCalls,
        containsAll(['小众', '独立', '冷门', '地下', '宝藏']),
      );
    });

    test('速览 keeps only short tracks when the pool allows it', () async {
      final r = await _rig(durations: const [10000, 5 * 60 * 1000]);
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);

      await fm.start(mode: FmMode.peek);
      await _drain();

      expect(_player(r.container).queue, isNotEmpty);
      expect(
        _player(r.container).queue.every((t) => t.durationMs <= 4 * 60 * 1000),
        isTrue,
      );
    });
  });

  group('FM dislike', () {
    test('removes the track from the live queue and advances', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);

      await fm.start();
      await _drain();
      final before = _player(r.container).current!.id;

      await fm.dislike();
      await _drain();

      expect(
        _player(r.container).queue.any((t) => t.id == before),
        isFalse,
        reason: '不喜欢的歌必须当场离开队列，播放器续播才碰不到它',
      );
      expect(_player(r.container).current!.id, isNot(before));
      expect(_fm(r.container).disliked, contains(before));
    });
  });

  group('FM stream never wraps', () {
    test('next() stops at the pool tail instead of looping to song 1',
        () async {
      final r = await _rig(perKeyword: 1); // 3 首，续流阈值 6 会触发追加
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);
      final player = r.container.read(playerControllerProvider.notifier);

      await fm.start();
      await _drain();

      // 一路推到池尾（追加会不断把歌补上，所以这里只验证「不会绕回第 0 首」）。
      final seen = <String>{};
      for (var i = 0; i < 12; i++) {
        seen.add(_player(r.container).current!.id);
        await player.next();
        await _drain();
      }

      expect(seen.length, greaterThan(1));
      // 队列是追加式增长；只要 currentIndex 没被重置成 0 之外的绕回即可。
      expect(_player(r.container).queueSource, PlaybackQueueSource.fm);
      expect(_fm(r.container).active, isTrue);
      expect(
        _player(r.container).queue.length >= seen.length,
        isTrue,
        reason: 'FM 是追加式增长，队列必须容纳得下听过的歌',
      );
    });
  });

  group('FM step back', () {
    test('disabled at the session head, then steps inside the pool', () async {
      final r = await _rig();
      addTearDown(r.container.dispose);
      final fm = r.container.read(fmControllerProvider.notifier);
      final player = r.container.read(playerControllerProvider.notifier);

      await fm.start();
      await _drain();
      expect(_player(r.container).canStepBack, isFalse);

      await player.next();
      await _drain();
      final second = _player(r.container).current!.id;
      expect(_player(r.container).canStepBack, isTrue);

      await fm.previous();
      await _drain();
      expect(_player(r.container).current!.id, isNot(second));
      expect(_player(r.container).canStepBack, isFalse);
    });
  });

  group('real-endpoint params', () {
    test('mode maps to the endpoint mode token', () {
      expect(FmMode.heart.modeParam, 'normal');
      expect(FmMode.niche.modeParam, 'small');
      expect(FmMode.peek.modeParam, 'peak');
    });

    test('song pool maps to the endpoint song_pool_id', () {
      expect(FmSongPool.taste.poolId, 0);
      expect(FmSongPool.style.poolId, 1);
      expect(FmSongPool.explore.poolId, 2);
    });

    test('the two axes stay independent', () {
      expect(FmMode.values.map((m) => m.modeParam).toSet(),
          {'normal', 'small', 'peak'});
      expect(FmSongPool.values.map((p) => p.poolId).toSet(), {0, 1, 2});
    });

    test('labels use the upstream codenames', () {
      expect([for (final p in FmSongPool.values) p.label],
          ['Alpha', 'Beta', 'Gamma']);
      expect(FmSongPool.explore.semantic, isEmpty);
    });
  });

  group('automatic real recommendation strategy', () {
    tearDown(() {
      AuthTokenHolder.instance.clear();
    });

    test('when logged in and the source returns tracks, uses them directly',
        () async {
      final serverTracks = List.generate(
        10,
        (i) => Track(
          id: 'rec-$i',
          name: '推荐曲目 $i',
          artist: '歌手',
          album: '专辑',
          coverUrl: 'http://cover/rec-$i',
          durationMs: 180000,
        ),
      );
      final r = await _rig(fmServerTracks: serverTracks, loggedIn: true);
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(r.source.fetchCalls, 1);
      expect(_fm(r.container).fromServer, isTrue);
      expect(_player(r.container).queue.map((t) => t.id), [
        for (var i = 0; i < 10; i++) 'rec-$i',
      ]);
      expect(r.source.searchCalls, isEmpty,
          reason: 'should not fall back to search keywords');
    });

    test('when logged in but the source fails, falls back to the keyword pool',
        () async {
      final r = await _rig(
        fmServerFailure: const UpstreamChanged('网关繁忙'),
        loggedIn: true,
      );
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(r.source.fetchCalls, 1);
      expect(_fm(r.container).fromServer, isFalse);
      expect(_fm(r.container).gatewayError, '网关繁忙');
      expect(r.source.searchCalls.toSet(), {'热门', '华语流行', '经典'});
      expect(_player(r.container).queue.isNotEmpty, isTrue);
    });

    test('when not logged in, directly uses the keyword pool without a request',
        () async {
      AuthTokenHolder.instance.clear();
      final r = await _rig();
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(r.source.fetchCalls, 0);
      expect(_fm(r.container).fromServer, isFalse);
      expect(r.source.searchCalls.toSet(), {'热门', '华语流行', '经典'});
    });

    test('fresh fetch sends remain=0 even with a leftover queue', () async {
      // 源收下了但没给歌（无异常、无曲目）：以前会因 remain_songcnt=25 被写成
      // 「私人FM加载失败」。
      final r = await _rig(loggedIn: true);
      addTearDown(r.container.dispose);

      // 先塞一条普通队列，模拟开 FM 前用户正在听别的歌单。
      final leftover = List.generate(
        26,
        (i) => Track(
          id: 'old-$i',
          name: 'old-$i',
          artist: 'a',
          album: 'b',
          coverUrl: 'http://c/$i',
          durationMs: 180000,
          hash: 'hash-$i',
        ),
      );
      await r.container
          .read(playerControllerProvider.notifier)
          .playQueue(leftover, source: PlaybackQueueSource.none);
      await _drain();

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(r.source.fetchCalls, 1);
      expect(
        r.source.remainSongcnts.single,
        0,
        reason: '开新会话必须明确要歌，不能把旧队列剩余数传上去',
      );
      expect(
        _fm(r.container).gatewayError,
        isEmpty,
        reason: '服务端收下但无新歌不能写成加载失败',
      );
      expect(_fm(r.container).fromServer, isFalse);
      expect(r.source.searchCalls.toSet(), {'热门', '华语流行', '经典'});
    });

    test('source-accepted empty page falls back without gatewayError', () async {
      final r = await _rig(loggedIn: true);
      addTearDown(r.container.dispose);

      await r.container.read(fmControllerProvider.notifier).start();
      await _drain();

      expect(_fm(r.container).fromServer, isFalse);
      expect(_fm(r.container).gatewayError, isEmpty);
      expect(_fm(r.container).error, isEmpty);
      expect(_player(r.container).queue.isNotEmpty, isTrue);
    });
  });
}
