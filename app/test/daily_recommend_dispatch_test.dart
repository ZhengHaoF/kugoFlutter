import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/data/mock_data.dart';
import 'package:kugo/core/models/daily_recommend.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/music_platform.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/recommend/daily_recommend_page.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 计数的日推源：验证「按源取数」而不是直连酷狗。
class _DailyFake extends FakeMusicSource {
  _DailyFake({required super.platform, required List<Track> tracks}) {
    dailyResult = DailyRecommendResult(tracks: tracks, personalized: true);
  }

  int calls = 0;

  @override
  Future<DailyRecommendResult> dailyRecommend() async {
    calls += 1;
    return dailyResult;
  }
}

Track _track(String name) => MockData.dailyTracks.first.copyWith(name: name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> pumpPage(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DailyRecommendPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  ({_DailyFake kugou, _DailyFake netease}) twoSources() {
    final kugou = _DailyFake(
      platform: MusicPlatform.kugou,
      tracks: [_track('酷狗日推歌')],
    );
    final netease = _DailyFake(
      platform: MusicPlatform.netease,
      tracks: [_track('网易日推歌')],
    );
    musicSourceRegistry = MusicSourceRegistry([kugou, netease]);
    return (kugou: kugou, netease: netease);
  }

  testWidgets('两源启用：显示切源栏（无「全部」），按默认源取数', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);

    expect(find.byType(SourceFilterBar), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    expect(find.text('网易日推歌'), findsOneWidget);
    expect(find.text('酷狗日推歌'), findsNothing);
    expect(find.text('为你量身定制的每日歌单'), findsOneWidget);
    expect(find.text('1 首 · 个性化推荐'), findsOneWidget);
    expect(sources.netease.calls, 1);
    expect(sources.kugou.calls, 0);
  });

  testWidgets('切到酷狗：重新取数并换成酷狗日推', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou', 'netease'],
      'settings.defaultSource': 'netease',
    });

    await pumpPage(tester, container);
    await tester.tap(find.text('酷狗'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('酷狗日推歌'), findsOneWidget);
    expect(find.text('网易日推歌'), findsNothing);
    expect(sources.kugou.calls, 1);
  });

  testWidgets('单源启用：隐藏切源栏', (tester) async {
    final sources = twoSources();
    final container = await containerWith({
      'settings.enabledSources': ['kugou'],
      'settings.defaultSource': 'kugou',
    });

    await pumpPage(tester, container);

    expect(find.byType(SourceFilterBar), findsNothing);
    expect(find.text('酷狗日推歌'), findsOneWidget);
    expect(sources.kugou.calls, 1);
    expect(sources.netease.calls, 0);
  });

  testWidgets('无具备日推能力的可用源：出停用空态', (tester) async {
    // 只注册酷狗源，却只启用网易云 → 无源可用。
    musicSourceRegistry = MusicSourceRegistry([
      _DailyFake(platform: MusicPlatform.kugou, tracks: const []),
    ]);
    final container = await containerWith({
      'settings.enabledSources': ['netease'],
    });

    await pumpPage(tester, container);

    expect(find.byType(SourceDisabledView), findsOneWidget);
    expect(find.text('网易云音源已停用'), findsOneWidget);
  });
}
