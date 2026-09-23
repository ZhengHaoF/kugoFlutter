import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/core/utils/krc_parser.dart';
import 'package:kugo/core/utils/lrc_parser.dart';

/// Build a `krc1` container the way Kugou download returns it.
Uint8List packKrc(String plain) {
  const key = <int>[
    0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47,
    0x51, 0x36, 0x31, 0x2D, 0xCE, 0xD2, 0x6E, 0x69,
  ];
  final zipped = ZLibEncoder().convert(utf8.encode(plain));
  final body = Uint8List(zipped.length);
  for (var i = 0; i < zipped.length; i++) {
    body[i] = zipped[i] ^ key[i & 15];
  }
  return Uint8List.fromList([...utf8.encode('krc1'), ...body]);
}

String encodeLanguage({
  List<List<String>>? translation,
  List<List<String>>? romanization,
}) {
  final content = <Map<String, dynamic>>[
    if (romanization != null) {'type': 0, 'lyricContent': romanization},
    if (translation != null) {'type': 1, 'lyricContent': translation},
  ];
  final jsonStr = jsonEncode({'content': content, 'version': 1});
  final b64 = base64.encode(utf8.encode(jsonStr));
  return '[language:$b64]';
}

void main() {
  group('parseLrc', () {
    test('parses time tags and back-fills endMs', () {
      final lines = parseLrc(
        '[00:01.00]第一行\n[00:03.50]第二行\n[00:05.00]第三行',
      );
      expect(lines.length, 3);
      expect(lines[0].text, '第一行');
      expect(lines[0].timeMs, 1000);
      expect(lines[0].endMs, 3500);
      expect(lines[2].endMs, 8000);
    });

    test('findLyricIndex walks by time', () {
      final lines = parseLrc('[00:01.00]a\n[00:02.00]b');
      expect(findLyricIndex(lines, 0), -1);
      expect(findLyricIndex(lines, 1000), 0);
      expect(findLyricIndex(lines, 2500), 1);
    });
  });

  group('decryptKrc + parseKrc', () {
    test('round-trips word timing', () {
      const plain = '[offset:0]\n'
          '[29140,3200]<0,440,0>故<440,480,0>事<920,320,0>的<1240,970,0>小'
          '<2210,450,0>黄<2660,540,0>花';
      final text = decryptKrc(packKrc(plain));
      expect(text, isNotNull);

      final result = parseKrc(text!);
      expect(result.lines, hasLength(1));
      final line = result.lines.single;
      expect(line.text, '故事的小黄花');
      expect(line.hasCharTiming, isTrue);
      expect(line.chars, hasLength(6));
      expect(line.chars.first.text, '故');
      expect(line.chars.first.startMs, 29140);
      expect(line.chars.first.endMs, 29580);
      expect(line.timeMs, 29140);
      expect(line.endMs, 29140 + 3200 > 32340 ? line.endMs : 32340);
      // sung count before any char
      expect(line.sungCharCount(29139), 0);
      expect(line.sungCharCount(29140), 1); // 故 started
      expect(line.sungCharCount(29600), 2); // 故 done, 事 started
      expect(line.sungCharCount(50000), 6);
    });

    test('language block yields translation and romanization rows', () {
      final lang = encodeLanguage(
        translation: [
          [' '],
          ['要是这是场梦'],
        ],
        romanization: [
          ['yo ne ', 'tsu '],
          ['yu me '],
        ],
      );
      final plain = '$lang\n'
          '[0,100]<0,50,0>あ<50,50,0>り\n'
          '[200,100]<0,50,0>ゆ<50,50,0>め';
      final result = parseKrc(plain);
      expect(result.lines, hasLength(2));
      expect(result.hasTranslation, isTrue);
      expect(result.hasRomanization, isTrue);
      expect(result.lines[0].translated, isNull); // blank row
      expect(result.lines[0].romanized, 'yo ne tsu');
      expect(result.lines[1].translated, '要是这是场梦');
      expect(result.lines[1].romanized, 'yu me');
      expect(result.lines[1].text, 'ゆめ');
    });

    test('LRC-only line inside KRC falls back to whole-line char', () {
      final result = parseKrc('[1500,800]整行无逐字');
      expect(result.lines, hasLength(1));
      final line = result.lines.single;
      expect(line.text, '整行无逐字');
      expect(line.chars, hasLength(1));
      expect(line.chars.single.startMs, 1500);
      expect(line.chars.single.endMs, 2300);
    });

    test('plain LRC text is rejected by decryptKrc unless bracketed', () {
      // Non-krc1 payload that is UTF-8 LRC-like is accepted as text.
      final raw = Uint8List.fromList(utf8.encode('[00:01.00]hi'));
      final text = decryptKrc(raw);
      expect(text, contains('hi'));
    });
  });

  group('LyricLine.sungCharCount', () {
    test('without chars uses line start', () {
      const line = LyricLine(timeMs: 1000, text: 'abc');
      expect(line.sungCharCount(500), 0);
      expect(line.sungCharCount(1000), 3);
      expect(line.hasCharTiming, isFalse);
    });
  });
}
