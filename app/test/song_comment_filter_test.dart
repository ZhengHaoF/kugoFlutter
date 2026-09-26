import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/comment.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/source/capabilities.dart';
import 'package:kugo/core/source/registry.dart';
import 'package:kugo/features/player/player_controller.dart';
import 'package:kugo/features/song/song_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_player.dart';
import 'fakes/fake_music_source.dart';

/// 评论源：**「全部」档带筛选项、分类/热词档不带** —— 复刻酷狗的真实口径
/// （筛选项只有 `cmtlist` 给，分类/热词接口不返回）。
///
/// 这正是「点 chip 后 chips 行消失、无法取消筛选」那个 bug 的成因，
/// 所以用它来钉住「筛选项必须是页面状态」这条约束。
class _CommentFakeSource extends FakeMusicSource implements CommentReadSource {
  final List<String> calls = [];

  @override
  String lastError = '';

  Comment _c(String id) => Comment(id: id, user: 'u', content: 'c-$id');

  CommentPage _page(String tag, {required bool withFilters}) => CommentPage(
    items: [_c('$tag-1'), _c('$tag-2')],
    total: 100,
    childrenId: 'pool',
    maxPage: 5,
    classifyList: withFilters
        ? const [CommentFilterOption(id: '13', label: '歌曲相关')]
        : const [],
    hotwordList: withFilters
        ? const [CommentFilterOption(id: '晴天', label: '晴天')]
        : const [],
  );

  @override
  Future<CommentPage> songComments(
    Track track, {
    int page = 1,
    int pageSize = 20,
    CommentSort sort = CommentSort.all,
  }) async {
    calls.add('song:${sort.name}:$page');
    if (sort != CommentSort.all) return _page('hot', withFilters: false);
    return _page('all', withFilters: page == 1);
  }

  @override
  Future<CommentPage> classifyComments(
    Track track, {
    required String typeId,
    int page = 1,
    int pageSize = 20,
  }) async {
    calls.add('classify:$typeId:$page');
    return _page('classify', withFilters: false);
  }

  @override
  Future<CommentPage> hotwordComments(
    Track track, {
    required String hotWord,
    int page = 1,
    int pageSize = 20,
  }) async {
    calls.add('hotword:$hotWord:$page');
    return _page('hotword', withFilters: false);
  }

  @override
  Future<List<Comment>> featuredComments({
    required Track track,
    required String childrenId,
    int page = 1,
    int pageSize = 10,
  }) async => const [];

  @override
  Future<List<Comment>> floorReplies({
    required Track track,
    required String childrenId,
    required String rootCommentId,
    int page = 1,
    int pageSize = 20,
  }) async => const [];

  @override
  Future<int?> commentCount(Track track) async => 100;
}

/// 两帧：一帧发起请求、一帧收结果。**不用 `pumpAndSettle`** ——
/// 页面的 loading 态是 `CircularProgressIndicator`（无限动画），settle 会超时。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<_CommentFakeSource> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'kugo_device_dfid_registered': true,
    'kugo_device_dfid': 'test-dfid',
    'kugo_device_guid': 'test-guid',
  });
  final source = _CommentFakeSource();
  musicSourceRegistry = MusicSourceRegistry([source]);

  final container = ProviderContainer(
    overrides: [
      playerControllerProvider.overrideWith(
        () => PlayerController(engine: FakeAudioPlayer()),
      ),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: const SongDetailPage(id: '32100650', name: '晴天', artist: '周杰伦'),
      ),
    ),
  );
  await _settle(tester);
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('点分类 chip 后 chips 行仍在，再点同一个可取消（回归：无法取消筛选）', (tester) async {
    final source = await _pump(tester);

    // 首屏「全部」档带出筛选项。
    expect(find.text('歌曲相关'), findsOneWidget);
    expect(find.text('#晴天'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // 点分类 chip → 改走分类接口。
    await tester.tap(find.text('歌曲相关'));
    await _settle(tester);

    expect(source.calls, contains('classify:13:1'));
    // **关键回归**：分类接口不返回筛选项，但 chips 行不能消失，
    // 否则那个 chip 再也点不到 → 只能退出重进（用户报的现象）。
    expect(find.text('歌曲相关'), findsOneWidget);
    expect(find.text('#晴天'), findsOneWidget);
    // 选中态给出「可关闭」提示。
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // 再点同一个 chip → 取消筛选，回到「全部」档。
    await tester.tap(find.text('歌曲相关'));
    await _settle(tester);

    expect(source.calls.where((c) => c.startsWith('song:all')), hasLength(2));
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('歌曲相关'), findsOneWidget);
  });

  testWidgets('热词 chip 同样可选中 / 取消，且与分类互斥', (tester) async {
    final source = await _pump(tester);

    await tester.tap(find.text('#晴天'));
    await _settle(tester);
    expect(source.calls, contains('hotword:晴天:1'));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // 切到分类：热词应被清掉（二者同属「全部」档的单选筛选）。
    await tester.tap(find.text('歌曲相关'));
    await _settle(tester);
    expect(source.calls, contains('classify:13:1'));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('切到「最热」档：chips 行隐藏，切回「全部」仍在（筛选项没被清）', (tester) async {
    final source = await _pump(tester);

    await tester.tap(find.text('最热'));
    await _settle(tester);
    expect(source.calls, contains('song:hottest:1'));
    expect(find.text('歌曲相关'), findsNothing);

    await tester.tap(find.text('全部'));
    await _settle(tester);
    // 「最热」的响应不带筛选项（真实口径），但选项留在页面状态里，切回即可用。
    expect(find.text('歌曲相关'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
