import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_protocol.dart';
import 'package:kugo/features/desktop_lyric/lyric_window/lyric_window_controller.dart';
import 'package:kugo/features/desktop_lyric/lyric_window/lyric_window_view.dart';

void main() {
  testWidgets('unlock button stays inside the native polling hot region', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 88);
    tester.view.devicePixelRatio = 1;
    const channel = MethodChannel('kugo/desktop_lyric_host');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getPosition') {
            return {'x': 0, 'y': 0, 'width': 720, 'height': 88};
          }
          if (call.method == 'getCursorPos') return {'x': 680, 'y': 70};
          return null;
        });
    final controller = DesktopLyricController.withSnapshot(
      const DesktopLyricSnapshot(locked: true),
    )..markWindowReady();
    try {
      await tester.pumpWidget(
        MaterialApp(home: DesktopLyricView(controller: controller)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      final center = tester.getCenter(find.byTooltip('解锁'));
      expect(center.dx, greaterThanOrEqualTo(720 - 80));
      expect(center.dy, greaterThanOrEqualTo(88 - 46));
      expect(center.dy, lessThan(88));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
