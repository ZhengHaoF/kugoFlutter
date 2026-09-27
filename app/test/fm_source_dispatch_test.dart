import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/music_source.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/auth/auth_token_holder.dart';
import 'package:kugo/features/fm/fm_controller.dart';
import 'package:kugo/features/fm/fm_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 网易语义的 FM 源：只有 [PersonalFmSource]，**没有**档位轴（HeartRadioSource），
/// 且一次只回 1 首 —— 用来验证控制器层拼装批量与 UI 隐藏档位控件。
class _NeteaseFm extends FakeMusicSource {
  _NeteaseFm({required super.platform});

  int fetchCalls = 0;
  final List<int> remainSongcnts = [];

  /// 非空时挂住取数（验证切源「先停后切」的加载窗口）。
  Completer<void>? gate;

  /// 非空时 `nextFmTracks` 抛出它（验证取数失败时停在新源报错）。
  SourceFailure? failure;

  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async {
    fetchCalls++;
    remainSongcnts.add(remain);
    final f = failure;
    if (f != null) throw f;
    final g = gate;
    if (g != null) await g.future;
    return [
      Track(
        id: 'ncm-fm-$fetchCalls',
        name: '网易FM第$fetchCalls首',
        artist: '网易歌手',
        album: '网易专辑',
        coverUrl: 'http://cover/ncm-$fetchCalls',
        durationMs: 180000,
        platform: MusicPlatform.netease,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AuthTokenHolder.instance.clear());

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        playerControllerProvider
            .overrideWith(() => PlayerController(engine: FakeAudioPlayer())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.notifier).ensureRestored();
    return container;
  }

  /// 两源都在册：酷狗（有档位轴、关键词兜底）/ 网易（无档位轴、一次 1 首）。
  ({ScriptedFmSource kugou, _NeteaseFm netease}) twoSources() {
    final kugou = ScriptedFmSource(platform: MusicPlatform.kugou);
    final netease = _NeteaseFm(platform: MusicPlatform.netease);
    musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
    return (kugou: kugou, netease: netease);
  }

  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FmPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 起播涉及 SharedPreferences 等真实异步：必须走 [WidgetTester.runAsync]，
  /// FakeAsync 时钟不会自己推进。
  Future<void> startFm(WidgetTester tester, ProviderContainer container) async {
    await tester.runAsync(
      () => container.read(fmControllerProvider.notifier).start(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('两源启用：出切源栏（无「全部」），按设置默认源取数', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);

    expect(find.byType(SourceFilterBar), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    // 默认源是网易云：只有它在取数（一次 1 首 → 控制器拼到批量）。
    expect(container.read(fmControllerProvider).source, MusicPlatform.netease);
    expect(sources.netease.fetchCalls, greaterThan(0));
    expect(sources.kugou.fetchCalls, 0);
    expect(sources.kugou.searchCalls, isEmpty);
  });

  testWidgets('点击酷狗 chip：结束当前会话并以酷狗重开（不混源）', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);
    final neteaseCalls = sources.netease.fetchCalls;

    await tester.tap(find.text('酷狗'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(fmControllerProvider).source, MusicPlatform.kugou);
    // 新会话的歌全部来自酷狗：未登录走关键词兜底，网易不再被请求。
    expect(sources.kugou.searchCalls, isNotEmpty);
    expect(sources.netease.fetchCalls, neteaseCalls);
  });

  testWidgets('单源启用：隐藏切源栏', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou'],
    });

    await pumpPage(tester, container);
    await startFm(tester, container);

    expect(find.byType(SourceFilterBar), findsNothing);
    expect(container.read(fmControllerProvider).source, MusicPlatform.kugou);
    expect(sources.kugou.searchCalls, isNotEmpty);
    expect(sources.netease.fetchCalls, 0);
  });

  testWidgets('无具备 FM 能力的可用源：出停用空态', (tester) async {
    // 只注册酷狗源，却只启用网易云 → 无源可用。
    musicSourceRegistry = MusicSourceRegistry([
      ScriptedFmSource(platform: MusicPlatform.kugou),
    ]);
    final container = await containerWith({
      'settings.enabledSources': ['netease'],
    });

    await pumpPage(tester, container);

    expect(find.byType(SourceDisabledView), findsOneWidget);
    expect(find.text('网易云音源已停用'), findsOneWidget);
  });

  testWidgets('网易源：隐藏档位/曲库轴，角标按源写成「网易云私人 FM」',
      (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);

    // 档位轴（红心/小众/速览）与歌池轴（Alpha/Beta/Gamma）整块不挂。
    for (final m in FmMode.values) {
      expect(find.text(m.label), findsNothing, reason: '网易源没有档位轴');
    }
    for (final p in FmSongPool.values) {
      expect(find.text(p.label), findsNothing, reason: '网易源没有曲库轴');
    }
    expect(find.text('来源：网易云私人 FM'), findsOneWidget);
  });

  testWidgets('网易一次只回 1 首：控制器拼装到目标批量', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);

    // 10 次调用（kFmSeedBatch / kFmSeedBatchMaxCalls），每首独立 id。
    expect(sources.netease.fetchCalls, 10);
    expect(container.read(playerControllerProvider).queue.length, 10);
    // 首轮要歌必须 remain=0（>4 时服务端只回会话元数据）。
    expect(sources.netease.remainSongcnts.first, 0);
  });

  testWidgets('切源先停后切：取数窗口旧队列已停，新队列到位才起播', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);
    // 起播后队列里全是酷狗关键词兜底的歌。
    expect(container.read(playerControllerProvider).queue, isNotEmpty);
    expect(
      container.read(playerControllerProvider).queue.first.platform,
      MusicPlatform.kugou,
    );

    // 网易取数挂住：观察切换窗口内的状态。
    final gate = Completer<void>();
    sources.netease.gate = gate;

    await tester.tap(find.text('网易云'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));

    // 旧队列当场停掉并清空：不会出现「旧源的歌挂新源角标」。
    expect(container.read(fmControllerProvider).source, MusicPlatform.netease);
    expect(container.read(fmControllerProvider).loading, isTrue);
    expect(container.read(playerControllerProvider).queue, isEmpty);
    // 「接下来」面板说正在续接，不说「歌池见底了」。
    expect(find.text('正在续接歌池…'), findsOneWidget);

    // 放行取数：新队列（网易一次 1 首拼到批量）起播。
    gate.complete();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));

    final queue = container.read(playerControllerProvider).queue;
    expect(queue.length, 10);
    expect(queue.every((t) => t.platform == MusicPlatform.netease), isTrue);
  });

  testWidgets('切源取数失败：停在新源并报错，旧队列不续播', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);
    final oldNames = container
        .read(playerControllerProvider)
        .queue
        .map((t) => t.name)
        .toList();

    sources.netease.failure = const LoginRequired('需要登录网易云账号');

    await tester.tap(find.text('网易云'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));

    // 选择停在新源、失败原因如实报出；旧队列已停，不会「旧歌新角标」续播。
    expect(container.read(fmControllerProvider).source, MusicPlatform.netease);
    expect(container.read(playerControllerProvider).queue, isEmpty);
    for (final name in oldNames.take(4)) {
      expect(find.text(name), findsNothing);
    }
    expect(find.text('需要登录网易云账号'), findsOneWidget);
  });

  testWidgets('设置里停用当前会话源：先停后切换剩余源重开', (tester) async {
    twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'kugou',
    });

    await pumpPage(tester, container);
    await startFm(tester, container);
    expect(
      container.read(playerControllerProvider).queue.first.platform,
      MusicPlatform.kugou,
    );

    // 设置里停用酷狗 → 会话源不再可用，用剩余源重开（先停后切）。
    await tester.runAsync(
      () => container
          .read(settingsControllerProvider.notifier)
          .setEnabledSources(const {MusicPlatform.netease}),
    );
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(fmControllerProvider).source, MusicPlatform.netease);
    final queue = container.read(playerControllerProvider).queue;
    expect(queue.length, 10);
    expect(queue.every((t) => t.platform == MusicPlatform.netease), isTrue);
  });

  test('会话源落盘可读回；旧数据缺 source 时留 null（交给默认源解析）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await fmSessionStore.save(
      const FmSession(active: true, source: MusicPlatform.netease),
    );
    expect(fmSessionStore.loadSync(prefs)?.source, MusicPlatform.netease);

    // 旧版本写下的数据没有 source 字段。
    await prefs.setString(
      'fm.session',
      '{"mode":"heart","pool":"taste","pendingMode":"heart",'
      '"pendingPool":"taste","disliked":[],"usedQueries":[],"fromServer":false}',
    );
    expect(fmSessionStore.loadSync(prefs)?.source, isNull);
  });
}
