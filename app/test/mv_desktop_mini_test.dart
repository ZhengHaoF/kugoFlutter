import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/mv/mv_desktop_mini.dart';

void main() {
  group('MvDesktopMini — 桌面迷你窗窗口参数', () {
    test('尺寸下限常量与 DesktopShell.boot 的 900×640 对齐', () {
      // 退出迷你态要把 boot 时设定的下限还原回去，两边必须是同一个值。
      expect(MvDesktopMini.shellMinimumSize, const Size(900, 640));
      expect(MvDesktopMini.miniMinimumSize.width, lessThan(900));
      expect(MvDesktopMini.miniMinimumSize.height, lessThan(640));
      expect(MvDesktopMini.width, greaterThan(0));
    });

    test('无窗口插件环境（测试/未初始化）下 enter/exit 静默降级、不抛', () async {
      // enter 失败返回 null → 页面留在全页播放，不进迷你态。
      final prev = await MvDesktopMini.enter(16 / 9);
      expect(prev, isNull);
      // exit 对 null 也要安全（幂等）。
      await MvDesktopMini.exit(null);
    });
  });
}