import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/desktop_capabilities.dart';
import 'package:kugo/core/platform.dart';
import 'package:kugo/core/theme/kugo_theme.dart';
import 'package:kugo/features/cloud/cloud_upload_picker.dart';
import 'package:kugo/features/settings/settings_controller.dart';
import 'package:kugo/shared/tray/close_behavior_dialog.dart';
import 'package:kugo/shared/tray/desktop_tray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Linux X11, Wayland and unknown backend are separate capabilities', () {
    for (final backend in ['x11', 'wayland', 'unknown']) {
      final c = DesktopCapabilities.linux(backend);
      expect(c.desktopLyrics, backend == 'x11');
      expect(c.trayTooltip, isFalse);
      expect(c.absolutePosition, backend == 'x11');
      expect(c.alwaysOnTop, backend == 'x11');
    }
  });

  test('old close-to-tray preference cannot hide a window without a host', () {
    expect(safeCloseBehavior(CloseBehavior.tray, false), CloseBehavior.ask);
    expect(safeCloseBehavior(CloseBehavior.tray, true), CloseBehavior.tray);
    expect(safeCloseBehavior(CloseBehavior.quit, false), CloseBehavior.quit);
  });

  testWidgets(
    'no-tray close dialog keeps cancel/quit and removes hide option',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKugoTheme(Brightness.dark),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showCloseBehaviorDialog(context, trayAvailable: false),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('最小化到托盘'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('退出应用'), findsOneWidget);
    },
  );

  test(
    'Linux tray avoids unsupported tooltip/popup methods and uses PNG',
    () async {
      if (!isLinuxPlatform) return;
      final calls = <String>[];
      final previous = DesktopCapabilities.current;
      DesktopCapabilities.current = DesktopCapabilities.linux('x11');
      const channel = MethodChannel('tray_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'setContextMenu') {
              expect(call.arguments.toString(), contains('desktop_lyric'));
            }
            return true;
          });
      final tray = DesktopTray(
        onShowWindow: () {},
        onTogglePlayback: () {},
        onPrevious: () {},
        onNext: () {},
        onSetMode: (_) {},
        onVolumeDelta: (_) {},
        onToggleDesktopLyric: () {},
        onQuit: () {},
      );
      try {
        await tray.init();
        tray.onTrayIconRightMouseDown();
        expect(calls, ['setIcon', 'setContextMenu']);
        expect(resolveTrayIconPath(), endsWith('tray_icon.png'));
      } finally {
        await tray.destroy();
        DesktopCapabilities.current = previous;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );

  test(
    'missing file-dialog executable returns a readable error, not an exception',
    () async {
      final errors = <String>[];
      final result = await pickCloudUploadFiles(
        errors: errors,
        picker: () async => throw StateError('no executable'),
      );
      expect(result, isEmpty);
      expect(errors.single, contains('zenity'));
      expect(await pickCloudUploadFiles(picker: () async => null), isEmpty);
    },
  );
}
