import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android legacy icons decode at all five density sizes', () async {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in sizes.entries) {
      final image = await decode(
        File(
          'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        ).readAsBytesSync(),
      );
      expect(image.width, entry.value);
      expect(image.height, entry.value);
      final rgba = (await image.toByteData())!;
      for (var offset = 3; offset < rgba.lengthInBytes; offset += 4) {
        expect(
          rgba.getUint8(offset),
          255,
          reason: 'Legacy icon must have an opaque background',
        );
      }
      image.dispose();
    }
  });

  test(
    'Adaptive foreground and themed monochrome stay inside the safe zone',
    () async {
      for (final name in ['foreground', 'monochrome']) {
        final image = await decode(
          File(
            'android/app/src/main/res/drawable-nodpi/ic_launcher_$name.png',
          ).readAsBytesSync(),
        );
        expect(image.width, 432);
        expect(image.height, 432);
        final rgba = (await image.toByteData())!;
        var visible = 0;
        for (var y = 0; y < 432; y++) {
          for (var x = 0; x < 432; x++) {
            final offset = (y * 432 + x) * 4;
            final alpha = rgba.getUint8(offset + 3);
            if (alpha == 0) continue;
            visible++;
            expect(x, inInclusiveRange(84, 347));
            expect(y, inInclusiveRange(84, 347));
            final dx = x - 215.5;
            final dy = y - 215.5;
            expect(dx * dx + dy * dy, lessThanOrEqualTo(132 * 132));
            if (name == 'monochrome') {
              expect(rgba.getUint8(offset), 0);
              expect(rgba.getUint8(offset + 1), 0);
              expect(rgba.getUint8(offset + 2), 0);
            }
          }
        }
        expect(visible, greaterThan(1000));
        image.dispose();
      }
    },
  );

  test(
    'Android adaptive XML and launcher manifest reference the new assets',
    () {
      final v26 = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      final v33 = File(
        'android/app/src/main/res/mipmap-anydpi-v33/ic_launcher.xml',
      ).readAsStringSync();
      for (final xml in [v26, v33]) {
        expect(xml, contains('@color/icon_background'));
        expect(xml, contains('@drawable/ic_launcher_foreground'));
      }
      expect(v33, contains('@drawable/ic_launcher_monochrome'));
      expect(
        File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
        contains('name="icon_background"'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('@mipmap/ic_launcher'),
      );
    },
  );

  test(
    'Windows launcher and tray ICO contain every expected decodable PNG frame',
    () async {
      const expected = [16, 20, 24, 32, 40, 48, 64, 128, 256];
      for (final path in [
        'windows/runner/resources/app_icon.ico',
        'assets/tray_icon.ico',
      ]) {
        final bytes = File(path).readAsBytesSync();
        final data = ByteData.sublistView(bytes);
        expect(data.getUint16(0, Endian.little), 0);
        expect(data.getUint16(2, Endian.little), 1);
        expect(data.getUint16(4, Endian.little), expected.length);
        for (var index = 0; index < expected.length; index++) {
          final entry = 6 + index * 16;
          final size = bytes[entry] == 0 ? 256 : bytes[entry];
          expect(size, expected[index]);
          expect(bytes[entry + 1] == 0 ? 256 : bytes[entry + 1], size);
          expect(data.getUint16(entry + 6, Endian.little), 32);
          final length = data.getUint32(entry + 8, Endian.little);
          final offset = data.getUint32(entry + 12, Endian.little);
          expect(offset + length, lessThanOrEqualTo(bytes.length));
          final image = await decode(
            Uint8List.sublistView(bytes, offset, offset + length),
          );
          expect(image.width, size);
          expect(image.height, size);
          image.dispose();
        }
      }
    },
  );

  test('Master and tray PNG are nonempty transparent square assets', () async {
    for (final entry in {
      'branding/icon-g-master.png': 1024,
      'assets/tray_icon.png': 64,
    }.entries) {
      final image = await decode(File(entry.key).readAsBytesSync());
      expect(image.width, entry.value);
      expect(image.height, entry.value);
      final rgba = (await image.toByteData())!;
      expect(rgba.getUint8(3), 0);
      var opaque = 0;
      for (var offset = 3; offset < rgba.lengthInBytes; offset += 4) {
        if (rgba.getUint8(offset) > 0) opaque++;
      }
      expect(opaque, greaterThan(100));
      image.dispose();
    }
  });
}
