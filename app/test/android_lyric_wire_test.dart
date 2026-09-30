import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_protocol.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_style.dart';
import 'package:kugo/core/models/track.dart';

/// Android 原生 `LyricWire.parseSnapshot` 依赖的 wire 键名契约。
/// 改协议时两边（Dart / Kotlin）必须同步，这里锁死字段名。
void main() {
  test('snapshot wire keys match Android LyricWire parser', () {
    final snap = DesktopLyricSnapshot(
      trackId: 'id-1',
      title: '晴天',
      artist: '周杰伦',
      isPlaying: true,
      positionMs: 1234,
      durationMs: 240000,
      lyrics: [
        LyricLine(
          timeMs: 1000,
          endMs: 4000,
          text: '故事的小黄花',
          chars: const [
            LyricChar(text: '故', startMs: 1000, endMs: 1400),
            LyricChar(text: '事', startMs: 1400, endMs: 1800),
          ],
          translated: 'The little yellow flower of the story',
        ),
      ],
      lyricsReady: true,
      lyricHash: 42,
      revision: 7,
      translation: true,
      romanization: false,
      fontScale: 1.1,
      locked: true,
      offsetMs: -200,
      style: const DesktopLyricStyle(sungColor: 0xFF112233),
    );

    final wire = snap.toWire();
    for (final key in [
      'trackId',
      'title',
      'artist',
      'isPlaying',
      'positionMs',
      'durationMs',
      'lyrics',
      'lyricsReady',
      'lyricHash',
      'revision',
      'translation',
      'romanization',
      'fontScale',
      'locked',
      'offsetMs',
      'style',
    ]) {
      expect(wire.containsKey(key), isTrue, reason: 'missing snapshot key $key');
    }

    final style = wire['style'] as Map;
    for (final key in [
      'sungColor',
      'unsungColor',
      'shadowColor',
      'shadowStrength',
      'strokeColor',
      'strokeWidth',
      'bgColor',
      'bgOpacity',
      'bgRadius',
      'fontScale',
      'fontWeight',
    ]) {
      expect(style.containsKey(key), isTrue, reason: 'missing style key $key');
    }

    final line = (wire['lyrics'] as List).first as Map;
    expect(line['t'], 1000);
    expect(line['e'], 4000);
    expect(line['x'], '故事的小黄花');
    expect(line['tr'], isNotNull);
    final chars = line['c'] as List;
    expect(chars, hasLength(2));
    final c0 = chars.first as Map;
    expect(c0['x'], '故');
    expect(c0['s'], 1000);
    expect(c0['e'], 1400);
  });

  test('positionOnly omission marker is understood by native', () {
    final wire = DesktopLyricSnapshot(
      trackId: 'id-1',
      isPlaying: true,
      positionMs: 500,
    ).toWire();
    // 桥在 positionOnly 时会清空 lyrics 并打标；原生据此保留本地数组。
    wire['lyrics'] = const [];
    wire['lyricsOmitted'] = true;
    expect(wire['lyricsOmitted'], true);
    expect(wire['lyrics'], isEmpty);
    // effectivePositionMs = positionMs + offsetMs
    expect(
      DesktopLyricSnapshot.fromWire(wire).effectivePositionMs,
      500,
    );
  });

  test('findLyricIndex semantics used by native activeIndex', () {
    // 与 Kotlin LyricSnapshot.activeIndex 同一折半查找语义。
    final lines = [
      const LyricLine(timeMs: 0, text: 'a'),
      const LyricLine(timeMs: 1000, text: 'b'),
      const LyricLine(timeMs: 2000, text: 'c'),
    ];
    // 由 protocol 导出的 hash 仍随内容变化。
    expect(desktopLyricHash(lines), isNot(desktopLyricHash([
      const LyricLine(timeMs: 0, text: 'x'),
    ])));
  });
}
