import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/shared/branding/app_logo.dart';
import 'package:kugo/shared/branding/window_icon.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Window icon uses the CURRENT executable bundle and sends setIcon',
    () async {
      const channel = MethodChannel('window_manager');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await applyWindowsWindowIcon();
      expect(received?.method, 'setIcon');
      expect(
        (received?.arguments as Map)['iconPath'],
        p.join(
          p.dirname(Platform.resolvedExecutable),
          'data',
          'flutter_assets',
          windowsAppIconAsset,
        ),
      );
    },
  );

  test('Runtime ICO exactly matches the embedded and tray G artwork', () {
    final runtime = File(windowsAppIconAsset).readAsBytesSync();
    expect(
      runtime,
      File('windows/runner/resources/app_icon.ico').readAsBytesSync(),
    );
    expect(runtime, File('assets/tray_icon.ico').readAsBytesSync());
    expect(
      File('pubspec.yaml').readAsStringSync(),
      allOf(contains('- $appLogoAsset'), contains('- $windowsAppIconAsset')),
    );
  });
}
