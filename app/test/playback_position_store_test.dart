import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/data/storage/playback_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存 / 读取 roundtrip', () async {
    await PlaybackPositionStore.save('kugou:1', 65432);
    expect(await PlaybackPositionStore.load('kugou:1'), 65432);
  });

  test('曲目身份不一致 → null（不能把上一首的位置套到这一首）', () async {
    await PlaybackPositionStore.save('kugou:1', 65432);
    expect(await PlaybackPositionStore.load('kugou:2'), isNull);
  });

  test('无记录 / 零位 / 负位 → null', () async {
    expect(await PlaybackPositionStore.load('kugou:1'), isNull);
    await PlaybackPositionStore.save('kugou:1', 0);
    expect(await PlaybackPositionStore.load('kugou:1'), isNull);
    await PlaybackPositionStore.save('kugou:1', -10);
    expect(await PlaybackPositionStore.load('kugou:1'), isNull);
  });

  test('负位按 0 落盘（int key 不接受负数）', () async {
    await PlaybackPositionStore.save('kugou:1', -10);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('playback.position.ms'), 0);
  });

  test('空 key 不写入', () async {
    await PlaybackPositionStore.save('', 100);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('playback.position.key'), isNull);
  });

  test('clear 清掉', () async {
    await PlaybackPositionStore.save('kugou:1', 12345);
    await PlaybackPositionStore.clear();
    expect(await PlaybackPositionStore.load('kugou:1'), isNull);
  });
}
