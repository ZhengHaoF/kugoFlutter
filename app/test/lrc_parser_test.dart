import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/utils/lrc_parser.dart';

void main() {
  test('parse basic lrc', () {
    const raw = '''
[00:00.00]夜空中最亮的星
[00:04.00]能否听清
[00:08.50]那仰望的人
''';
    final lines = parseLrc(raw);
    expect(lines.length, 3);
    expect(lines[0].timeMs, 0);
    expect(lines[0].text, '夜空中最亮的星');
    expect(lines[1].timeMs, 4000);
    expect(lines[2].timeMs, 8500);
  });

  test('find active lyric index', () {
    final lines = parseLrc('''
[00:00.00]a
[00:04.00]b
[00:08.00]c
''');
    expect(findLyricIndex(lines, 0), 0);
    expect(findLyricIndex(lines, 3999), 0);
    expect(findLyricIndex(lines, 4000), 1);
    expect(findLyricIndex(lines, 99999), 2);
  });
}
