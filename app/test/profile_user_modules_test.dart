import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kugo/core/models/track.dart';
import 'fakes/fake_audio_player.dart';
import 'package:kugo/data/storage/kugo_db.dart';
import 'package:kugo/data/storage/queue_store.dart';
import 'package:kugo/features/history/history_page.dart';
import 'package:kugo/features/likes/likes_controller.dart';
import 'package:kugo/features/likes/likes_page.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/profile/profile_page.dart';
import 'package:kugo/shared/widgets/common.dart';

Track _testTrack(String id, String name, String artist) {
  return Track(
    id: id,
    name: name,
    artist: artist,
    album: 'Test Album',
    coverUrl: '',
    durationMs: 180000,
    hash: 'hash_$id',
    albumId: '1',
    mixSongId: 'mix_$id',
  );
}

void main() {
  late KugoDb db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = KugoDb.forTesting(NativeDatabase.memory());
    QueueStore.setDbForTesting(db);
  });

  tearDown(() {
    QueueStore.setDbForTesting(null);
    db.close();
  });

  group('LikesPage interactive features', () {
    testWidgets('search and sorting work correctly', (tester) async {
      final engine = FakeAudioPlayer();
      final t1 = _testTrack('1', '晴天', '周杰伦');
      final t2 = _testTrack('2', '稻香', '周杰伦');
      final t3 = _testTrack('3', '七里香', '周杰伦');

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
          likesProvider.overrideWith(() {
            final n = LikesNotifier();
            return n;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Populate likes
      await container.read(likesProvider.notifier).toggle(t1);
      await container.read(likesProvider.notifier).toggle(t2);
      await container.read(likesProvider.notifier).toggle(t3);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LikesPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 首 · 默认排序'), findsOneWidget);
      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('稻香'), findsOneWidget);
      expect(find.text('七里香'), findsOneWidget);

      // Tap search icon to open search
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), '晴天');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TrackTile, '晴天'), findsOneWidget);
      expect(find.widgetWithText(TrackTile, '稻香'), findsNothing);
      expect(find.widgetWithText(TrackTile, '七里香'), findsNothing);
      expect(find.text('找到 1 首 / 共 3 首'), findsOneWidget);

      // Close search
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('稻香'), findsOneWidget);
    });
  });

  group('HistoryPage interactive features', () {
    testWidgets('loads entries and can switch between records and stats',
        (tester) async {
      final engine = FakeAudioPlayer();
      final store = await QueueStore.open();
      await store.clearHistory();
      await store.appendHistory(_testTrack('h1', '夜曲', '周杰伦'));
      await store.appendHistory(_testTrack('h2', '东风破', '周杰伦'));

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HistoryPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Records tab by default
      expect(find.text('夜曲'), findsOneWidget);
      expect(find.text('东风破'), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);

      // Switch to stats tab
      await tester.tap(find.text('听歌统计'));
      await tester.pumpAndSettle();

      expect(find.text('近 7 天听歌频次'), findsOneWidget);
      expect(find.text('听歌时段偏好'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('常听歌手 TOP 榜'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('常听歌手 TOP 榜'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
    });
  });

  group('ProfilePage entry tiles', () {
    testWidgets('已砍掉的假入口不再出现，页面仍可渲染到底部', (tester) async {
      // 用高视口让整页在一次布局内全部构建 —— 否则懒构建的 ListView
      // 会让 findsNothing 因「没滚到」而假通过。
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final engine = FakeAudioPlayer();
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(
            () => PlayerController(engine: engine),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 真实入口仍在。页尾的「关于」也在同一屏内 → 证明整页确已布局，
      // 下面的 findsNothing 不是「没滚到」导致的假通过。
      expect(find.text('我的歌单'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);

      // 「本地音乐」/「下载管理」是只弹「开发中」的假入口，已明确砍掉。
      // 若将来重做，请删掉下面两条断言并补真实能力测试。
      expect(find.text('本地音乐'), findsNothing);
      expect(find.text('下载管理'), findsNothing);
    });
  });
}
