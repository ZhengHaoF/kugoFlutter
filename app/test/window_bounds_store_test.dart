import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/tray/window_bounds_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主窗尺寸 / 位置持久化（f7fec6f 引入，此前零测试）。
///
/// window_manager 在 Windows 上不会自己记住窗口，所以自己存一份。
/// 关键性质：**只清坐标、保留尺寸与最大化标记**——用户关窗时是最大化的，
/// 恢复时只需要 maximize，bounds 用上一次非最大化的值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void seed(Map<String, Object> values) =>
      SharedPreferences.setMockInitialValues(values);

  Future<DesktopWindowBounds> load() => DesktopWindowBoundsStore.load();

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  group('load', () {
    test('全新安装给默认 1200×820，无坐标、未最大化', () async {
      seed({});
      final b = await load();
      expect(b.width, 1200);
      expect(b.height, 820);
      expect(b.x, isNull);
      expect(b.y, isNull);
      expect(b.maximized, isFalse);
      expect(b.hasPosition, isFalse);
    });

    test('读回落盘的坐标 / 尺寸 / 最大化', () async {
      seed({
        'window.bounds.x': 100.0,
        'window.bounds.y': 200.0,
        'window.bounds.w': 1440.0,
        'window.bounds.h': 900.0,
        'window.bounds.maximized': true,
      });
      final b = await load();
      expect(b.x, 100.0);
      expect(b.y, 200.0);
      expect(b.width, 1440.0);
      expect(b.height, 900.0);
      expect(b.maximized, isTrue);
      expect(b.hasPosition, isTrue);
    });

    test('尺寸缺失时回默认，不影响已存的坐标', () async {
      seed({
        'window.bounds.x': 10.0,
        'window.bounds.y': 20.0,
      });
      final b = await load();
      expect(b.x, 10.0);
      expect(b.y, 20.0);
      expect(b.width, 1200);
      expect(b.height, 820);
    });

    test('脏数据（字符串塞进 double 槽）不抛，回落默认', () async {
      seed({
        'window.bounds.w': 'not-a-double',
        'window.bounds.maximized': 'yes',
      });
      final b = await load();
      expect(b.width, 1200);
      expect(b.maximized, isFalse);
    });
  });

  group('save / load 往返', () {
    test('四个字段都落盘', () async {
      seed({});
      await DesktopWindowBoundsStore.save(
        const DesktopWindowBounds(x: 5, y: 6, width: 800, height: 600),
      );

      final p = await prefs();
      expect(p.getDouble('window.bounds.x'), 5);
      expect(p.getDouble('window.bounds.y'), 6);
      expect(p.getDouble('window.bounds.w'), 800);
      expect(p.getDouble('window.bounds.h'), 600);

      final b = await load();
      // DesktopWindowBounds 没有实现 ==（也不打算为测试加），逐字段比。
      expect(b.x, 5);
      expect(b.y, 6);
      expect(b.width, 800);
      expect(b.height, 600);
      expect(b.maximized, isFalse);
    });

    test('坐标为 null 时不写 x/y（尺寸照写）', () async {
      seed({});
      await DesktopWindowBoundsStore.save(
        const DesktopWindowBounds(width: 1024, height: 768, maximized: true),
      );

      final p = await prefs();
      expect(p.getDouble('window.bounds.x'), isNull);
      expect(p.getDouble('window.bounds.y'), isNull);
      expect(p.getDouble('window.bounds.w'), 1024);
      expect(p.getBool('window.bounds.maximized'), isTrue);
    });

    test('x 有 y 无时只写存在的那个', () async {
      seed({});
      await DesktopWindowBoundsStore.save(
        const DesktopWindowBounds(x: 42, width: 1000, height: 700),
      );
      final p = await prefs();
      expect(p.getDouble('window.bounds.x'), 42);
      expect(p.getDouble('window.bounds.y'), isNull);
    });
  });

  group('clearPosition', () {
    test('只清坐标，尺寸与最大化标记保留', () async {
      seed({});
      await DesktopWindowBoundsStore.save(
        const DesktopWindowBounds(
          x: 11,
          y: 22,
          width: 1600,
          height: 1000,
          maximized: true,
        ),
      );

      await DesktopWindowBoundsStore.clearPosition();

      final p = await prefs();
      expect(p.getDouble('window.bounds.x'), isNull);
      expect(p.getDouble('window.bounds.y'), isNull);
      // 尺寸和最大化必须留着。
      expect(p.getDouble('window.bounds.w'), 1600);
      expect(p.getDouble('window.bounds.h'), 1000);
      expect(p.getBool('window.bounds.maximized'), isTrue);

      final b = await load();
      expect(b.hasPosition, isFalse);
      expect(b.width, 1600);
      expect(b.maximized, isTrue);
    });

    test('无坐标时调用也不抛', () async {
      seed({});
      await DesktopWindowBoundsStore.clearPosition();
      expect((await load()).hasPosition, isFalse);
    });
  });

  group('DesktopWindowBounds', () {
    test('hasPosition 要求 x 和 y 都在', () {
      expect(const DesktopWindowBounds().hasPosition, isFalse);
      expect(const DesktopWindowBounds(x: 1).hasPosition, isFalse);
      expect(const DesktopWindowBounds(y: 1).hasPosition, isFalse);
      expect(const DesktopWindowBounds(x: 1, y: 2).hasPosition, isTrue);
    });

    test('默认值就是兜底尺寸', () {
      const b = DesktopWindowBounds();
      expect(b.width, 1200);
      expect(b.height, 820);
      expect(b.maximized, isFalse);
    });
  });
}
