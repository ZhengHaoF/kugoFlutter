import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/search/search_history_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  SearchHistoryNotifier notifierOf(ProviderContainer c) =>
      c.read(searchHistoryProvider.notifier);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  test('record：最新搜索排在最前', () async {
    await notifierOf(container).record('周杰伦');
    await notifierOf(container).record('林俊杰');
    expect(container.read(searchHistoryProvider), ['林俊杰', '周杰伦']);
  });

  test('record：重复关键词去重并置顶', () async {
    await notifierOf(container).record('a');
    await notifierOf(container).record('b');
    await notifierOf(container).record('a');
    expect(container.read(searchHistoryProvider), ['a', 'b']);
  });

  test('record：去首尾空白，空串忽略', () async {
    await notifierOf(container).record('   ');
    await notifierOf(container).record('  周杰伦  ');
    expect(container.read(searchHistoryProvider), ['周杰伦']);
  });

  test('record：超过上限时截断，保留最近 $kMaxSearchHistory 条', () async {
    for (var i = 0; i < kMaxSearchHistory + 5; i++) {
      await notifierOf(container).record('kw$i');
    }
    final list = container.read(searchHistoryProvider);
    expect(list.length, kMaxSearchHistory);
    expect(list.first, 'kw${kMaxSearchHistory + 4}');
    expect(list.contains('kw4'), isFalse);
  });

  test('remove：只删指定的一条', () async {
    await notifierOf(container).record('a');
    await notifierOf(container).record('b');
    await notifierOf(container).remove('a');
    expect(container.read(searchHistoryProvider), ['b']);
    // 删不存在的关键词无副作用。
    await notifierOf(container).remove('missing');
    expect(container.read(searchHistoryProvider), ['b']);
  });

  test('clear：清空全部', () async {
    await notifierOf(container).record('a');
    await notifierOf(container).record('b');
    await notifierOf(container).clear();
    expect(container.read(searchHistoryProvider), isEmpty);
  });

  test('持久化：新容器能读回历史', () async {
    await notifierOf(container).record('周杰伦');
    await notifierOf(container).record('林俊杰');

    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await notifierOf(fresh).unawaitedLoad();
    expect(fresh.read(searchHistoryProvider), ['林俊杰', '周杰伦']);
  });

  test('持久化：clear 后新容器读回为空', () async {
    await notifierOf(container).record('a');
    await notifierOf(container).clear();

    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await notifierOf(fresh).unawaitedLoad();
    expect(fresh.read(searchHistoryProvider), isEmpty);
  });

  test('损坏的存储不崩，历史为空', () async {
    SharedPreferences.setMockInitialValues({'search.history.v1': 'not json'});
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await notifierOf(fresh).unawaitedLoad();
    expect(fresh.read(searchHistoryProvider), isEmpty);
  });
}