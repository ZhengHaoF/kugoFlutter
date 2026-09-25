import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/fm_mode.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
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

  @override
  Future<List<Track>> nextFmTracks({int remain = 5}) async {
    fetchCalls++;
    remainSongcnts.add(remain);
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
