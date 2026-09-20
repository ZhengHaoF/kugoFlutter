import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/api/kugo_client.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/data/repositories/search_repository.dart';
import 'package:kugo/features/fm/personal_fm_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';

/// Serves scripted song pages and records every keyword requested, so the FM
/// page's pool/refill behaviour can be asserted without touching the network.
class _FakeSearchRepo implements SearchRepository {
  _FakeSearchRepo({
    this.perKeyword = 4,
    this.keywordDelay = const {},
    this.durations = const [],
  });

  /// How many tracks each keyword yields.
  final int perKeyword;

  /// Per-track durations, cycled by index. Empty = [10000] for every track.
  final List<int> durations;

  /// Per-keyword artificial latency — used to force out-of-order responses.
  final Map<String, Duration> keywordDelay;

  final List<String> calls = [];

  /// Keywords that should throw instead of returning results.
  final Set<String> failing = {};

  /// Round counter per keyword so repeated draws return *different* tracks.
  final Map<String, int> _round = {};

  @override
  Future<List<Track>> searchSongs(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    calls.add(keyword);
    final delay = keywordDelay[keyword];
    if (delay != null) await Future<void>.delayed(delay);
    if (failing.contains(keyword)) throw KugoApiException('boom');
    final round = (_round[keyword] ?? 0) + 1;
    _round[keyword] = round;
    return List.generate(
      perKeyword,
      (i) => Track(
        id: '$keyword-$round-$i',
        name: '$keyword-$round-$i',
        artist: 'artist',
        album: 'album',
        coverUrl: 'http://cover/$keyword',
        durationMs: durations.isEmpty
            ? 10000
            : durations[i % durations.length],
      ),
    );
  }

  @override
  Future<SearchPageResult<Track>> searchSongsPage(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async =>
      SearchPageResult(items: await searchSongs(keyword, pageSize: pageSize));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

/// Flush pending async work without waiting for the vinyl animation to stop
/// (`_spin.repeat()` means `pumpAndSettle` would hang forever).
Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Everything a single FM test needs.
///
/// Teardown must run **inside** the test body: the Flutter test binding asserts
/// that no timers are pending once the tree is gone, and `addTearDown`
/// callbacks run after that check. The player controller starts a periodic demo
/// tick for tracks without a hash, so leaking it fails every test.
class _Harness {
  _Harness(
    this.tester,
    this.repo,
    this.engine,
    this.container, {
    this.useGateway = false,
  });

  final WidgetTester tester;
  final _FakeSearchRepo repo;
  final FakeAudioPlayer engine;
  final ProviderContainer container;
  final bool useGateway;

  PlayerState get state => container.read(playerControllerProvider);

  /// Body of the test, with guaranteed in-body teardown.
  Future<void> run(Future<void> Function(_Harness h) body) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
        home: PersonalFmPage(repository: repo, useGateway: useGateway),
      ),
      ),
    );
    await _settle(tester);
    try {
      await body(this);
    } finally {
      await close();
    }
  }

  /// Tap the "不喜欢" control (the label text is inside the tap target).
  Future<void> tapDislike() async {
    await tester.ensureVisible(find.text('不喜欢'));
    await tester.pump();
    await tester.tap(find.text('不喜欢'));
    await _settle(tester);
  }

  /// Tap a pool segment.
  Future<void> tapPool(String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    await _settle(tester);
  }

  /// Tap a mode segment (红心 / 小众 / 速览).
  Future<void> tapMode(String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    await _settle(tester);
  }

  /// Dispose the container and tear down the tree, then drain timers.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

_Harness _harness(
  WidgetTester tester, {
  int perKeyword = 4,
  Map<String, Duration> keywordDelay = const {},
  List<int> durations = const [],
  bool useGateway = false,
}) {
  SharedPreferences.setMockInitialValues({});
  final engine = FakeAudioPlayer();
  final container = ProviderContainer(
    overrides: [
      playerControllerProvider
          .overrideWith(() => PlayerController(engine: engine)),
    ],
  );
  return _Harness(
    tester,
    _FakeSearchRepo(
      perKeyword: perKeyword,
      keywordDelay: keywordDelay,
      durations: durations,
    ),
    engine,
    container,
    useGateway: useGateway,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FM pool', () {
    testWidgets('seeds from every keyword of the pool, not just one',
        (tester) async {
      await _harness(tester).run((h) async {
        // 口味 bundles 3 keywords × 4 tracks → 12 seeded.
        expect(h.repo.calls.toSet(), {'热门', '华语流行', '经典'});
        expect(h.state.queue.length, 12);
      });
    });

    testWidgets('switching pool re-queries with the new pool keywords',
        (tester) async {
      await _harness(tester).run((h) async {
        await h.tapPool('探索');

        expect(h.repo.calls, containsAll(['独立', '冷门', '爵士']));
        final first = h.state.queue.first.id;
        expect(
          first.startsWith('独立') ||
              first.startsWith('冷门') ||
              first.startsWith('爵士'),
          isTrue,
          reason: 'expected a 探索 track, got $first',
        );
      });
    });

    testWidgets('a slow response from a previous pool cannot clobber the new one',
        (tester) async {
      // 探索 is deliberately slower than 风格; without a request token the late
      // 探索 response would land last and overwrite 风格's results.
      await _harness(
        tester,
        keywordDelay: const {
          '独立': Duration(milliseconds: 400),
          '冷门': Duration(milliseconds: 400),
          '爵士': Duration(milliseconds: 400),
        },
      ).run((h) async {
        // Kick off 探索 (slow), then immediately switch to 风格 (fast).
        await tester.tap(find.text('探索'));
        await tester.pump();
        await h.tapPool('风格');
        await _settle(tester, frames: 30);

        final nowPlaying = h.state.current?.id ?? '';
        expect(
          nowPlaying.startsWith('独立') ||
              nowPlaying.startsWith('冷门') ||
              nowPlaying.startsWith('爵士'),
          isFalse,
          reason: 'stale 探索 response overwrote the 风格 pool: $nowPlaying',
        );
        expect(
          nowPlaying.startsWith('民谣') ||
              nowPlaying.startsWith('电子') ||
              nowPlaying.startsWith('轻音乐'),
          isTrue,
          reason: 'expected a 风格 track, got $nowPlaying',
        );
      });
    });
  });

  group('FM dislike', () {
    testWidgets('skips the disliked track instead of replaying it',
        (tester) async {
      await _harness(tester).run((h) async {
        final before = h.state.current?.id;
        expect(before, isNotNull);

        await h.tapDislike();

        final after = h.state.current?.id;
        expect(after, isNot(before), reason: 'dislike must advance the track');
        expect(h.state.queue, isNotEmpty);
      });
    });

    testWidgets('never re-serves a disliked track on a later refill',
        (tester) async {
      await _harness(tester, perKeyword: 2).run((h) async {
        final disliked = h.state.current!.id;
        await h.tapDislike();

        // Force several refills by disliking through the pool.
        for (var i = 0; i < 6; i++) {
          await h.tapDislike();
        }

        expect(
          h.state.queue.any((t) => t.id == disliked),
          isFalse,
          reason: 'disliked track $disliked came back',
        );
      });
    });
  });

  group('FM pool exhaustion', () {
    testWidgets('extends the pool at the end instead of wrapping to song 1',
        (tester) async {
      await _harness(tester, perKeyword: 1).run((h) async {
        final first = h.state.current!.id;
        final seeded = h.state.queue.length;
        expect(seeded, 3);

        // 口味 seeds 3 single-track keywords → advance 3 times to hit the end.
        for (var i = 0; i < 3; i++) {
          await h.tapDislike();
        }
        await _settle(tester, frames: 30);

        expect(
          h.state.queue.length,
          greaterThan(seeded),
          reason: 'pool should have been extended past its initial seed',
        );
        expect(
          h.state.current!.id,
          isNot(first),
          reason: 'wrapping back to the first track is the bug being fixed',
        );
      });
    });
  });

  group('FM follows the player cursor', () {
    testWidgets('displayed track tracks the player, even when changed elsewhere',
        (tester) async {
      await _harness(tester).run((h) async {
        expect(h.state.queue.length, greaterThan(2));

        // Simulate the user pressing "next" on the full player page / mini bar:
        // the FM page must follow rather than keep its own stale index.
        await h.container.read(playerControllerProvider.notifier).next();
        await _settle(tester);

        final playerCurrent = h.state.current!;
        expect(
          find.text(playerCurrent.name),
          findsOneWidget,
          reason: 'FM page did not follow the player to ${playerCurrent.name}',
        );
      });
    });
  });

  group('FM mode axis', () {
    testWidgets('小众 swaps in the niche keyword bundle', (tester) async {
      await _harness(tester).run((h) async {
        await h.tapMode('小众');

        expect(
          h.repo.calls,
          containsAll(['小众', '独立', '冷门', '地下', '宝藏']),
        );
        final first = h.state.current!.id;
        expect(
          first.startsWith('小众') ||
              first.startsWith('独立') ||
              first.startsWith('冷门') ||
              first.startsWith('地下') ||
              first.startsWith('宝藏'),
          isTrue,
          reason: 'expected a 小众 track, got $first',
        );
      });
    });

    testWidgets('速览 keeps only short tracks when the pool allows it',
        (tester) async {
      await _harness(
        tester,
        durations: const [10000, 5 * 60 * 1000],
      ).run((h) async {
        await h.tapMode('速览');
        await _settle(tester, frames: 30);

        expect(h.state.queue, isNotEmpty);
        expect(
          h.state.queue.every((t) => t.durationMs <= 4 * 60 * 1000),
          isTrue,
          reason: '速览 must not hand the player a 5-minute track',
        );
      });
    });

    testWidgets('mode switch does not leak the previous mode keywords',
        (tester) async {
      await _harness(tester).run((h) async {
        await h.tapMode('速览');
        await _settle(tester, frames: 20);

        expect(h.repo.calls, isNot(contains('小众')));
      });
    });
  });

  group('FM gateway opt-in', () {
    testWidgets('guest stays on the keyword pool and says so',
        (tester) async {
      // useGateway: true but nobody is logged in → the gateway is unusable, so
      // the page must fall back to the keyword pool AND label the source.
      await _harness(tester, useGateway: true).run((h) async {
        expect(h.state.queue, isNotEmpty);
        expect(
          find.textContaining('来源：关键词检索'),
          findsOneWidget,
          reason: 'the fallback source must be visible, not disguised',
        );
      });
    });

    testWidgets('source badge reports the pool it is drawing from',
        (tester) async {
      await _harness(tester).run((h) async {
        expect(find.textContaining('来源：关键词检索'), findsOneWidget);
        expect(find.textContaining('热门 / 华语流行'), findsOneWidget);
      });
    });
  });

  // `mode` / `song_pool_id` are the two axes the real endpoint understands
  // (KuGouMusicApi personal_fm.js). The UI must not invent its own values.
  group('FM real-endpoint params', () {
  test('mode maps to the endpoint mode token', () {
    expect(FmMode.heart.modeParam, 'normal');
    expect(FmMode.niche.modeParam, 'small');
    expect(FmMode.peek.modeParam, 'peak');
  });

  test('mode maps to the endpoint song_pool_id', () {
    expect(FmMode.heart.songPoolId, 0);
    expect(FmMode.niche.songPoolId, 1);
    expect(FmMode.peek.songPoolId, 2);
  });

  test('only 速览 carries the local short-track rule', () {
    expect(FmMode.peek.preferShort, isTrue);
    expect(FmMode.heart.preferShort, isFalse);
    expect(FmMode.niche.preferShort, isFalse);
  });

  test('song pool labels stay stable for the strategy switch', () {
    expect(
      [for (final p in FmSongPool.values) p.label],
      ['口味', '风格', '探索'],
    );
  });
});
}
