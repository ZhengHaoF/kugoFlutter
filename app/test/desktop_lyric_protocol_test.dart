import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_protocol.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_store.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_style.dart';
import 'package:kugo/core/models/track.dart';

void main() {
  group('desktop lyric protocol', () {
    test('snapshot wire roundtrip keeps lyrics and settings', () {
      const snap = DesktopLyricSnapshot(
        trackId: 'kugou:1',
        title: '夜曲',
        artist: '周杰伦',
        isPlaying: true,
        positionMs: 1234,
        durationMs: 200000,
        lyricsReady: true,
        lyricHash: 42,
        revision: 3,
        translation: false,
        romanization: true,
        fontScale: 1.2,
        locked: true,
        offsetMs: 500,
        lyrics: [
          LyricLine(
            timeMs: 1000,
            endMs: 4000,
            text: '第一行',
            translated: 'line one',
            romanized: 'di yi hang',
            chars: [
              LyricChar(text: '第', startMs: 1000, endMs: 2000),
              LyricChar(text: '一', startMs: 2000, endMs: 3000),
            ],
          ),
        ],
      );

      final back = DesktopLyricSnapshot.fromWire(snap.toWire());
      expect(back.trackId, 'kugou:1');
      expect(back.title, '夜曲');
      expect(back.artist, '周杰伦');
      expect(back.isPlaying, isTrue);
      expect(back.positionMs, 1234);
      expect(back.durationMs, 200000);
      expect(back.lyricsReady, isTrue);
      expect(back.revision, 3);
      expect(back.translation, isFalse);
      expect(back.romanization, isTrue);
      expect(back.fontScale, 1.2);
      expect(back.locked, isTrue);
      expect(back.offsetMs, 500);
      expect(back.lyrics, hasLength(1));
      final line = back.lyrics.single;
      expect(line.text, '第一行');
      expect(line.translated, 'line one');
      expect(line.romanized, 'di yi hang');
      expect(line.chars, hasLength(2));
      expect(line.chars.first.text, '第');
      expect(back.effectivePositionMs, 1734);
    });

    test('snapshot wire roundtrip keeps desktop lyric style', () {
      const style = DesktopLyricStyle(
        sungColor: 0xFFFF0000,
        unsungColor: 0xFF00FF00,
        strokeColor: 0xFF123456,
        strokeWidth: 2.5,
        bgColor: 0xFFABCDEF,
        bgOpacity: 0.4,
        bgRadius: 20,
        fontScale: 1.35,
        fontWeight: 1.6,
      );
      final back = DesktopLyricSnapshot.fromWire(
        const DesktopLyricSnapshot(style: style).toWire(),
      );
      expect(back.style, style);
    });

    test('style fromWire falls back to defaults for dirty values', () {
      // clampDouble 的语义是「越界/脏数据 → 回默认」，不是夹取到边界。
      const def = DesktopLyricStyle();
      final s = DesktopLyricStyle.fromWire({
        'sungColor': 'not-a-number',
        'strokeWidth': -3,
        'bgOpacity': 2,
        'bgRadius': -1,
        'fontScale': 0.1,
        'fontWeight': 5,
      });
      expect(s.sungColor, def.sungColor);
      expect(s.strokeWidth, def.strokeWidth);
      expect(s.bgOpacity, def.bgOpacity);
      expect(s.bgRadius, def.bgRadius);
      expect(s.fontScale, def.fontScale);
      expect(s.fontWeight, def.fontWeight);
    });

    test('position-only push can omit lyrics without losing hash identity', () {
      const full = DesktopLyricSnapshot(
        trackId: 't',
        revision: 1,
        lyrics: [LyricLine(timeMs: 0, text: 'a')],
      );
      final wire = full.toWire();
      wire['lyrics'] = const [];
      wire['lyricsOmitted'] = true;
      final partial = DesktopLyricSnapshot.fromWire(wire);
      expect(partial.lyrics, isEmpty);
      expect(partial.revision, 1);
      expect(partial.trackId, 't');
    });

    test('desktopLyricHash is stable for same content and differs otherwise', () {
      final a = [
        const LyricLine(timeMs: 0, text: 'hello'),
        const LyricLine(timeMs: 10, text: 'world'),
      ];
      final b = [
        const LyricLine(timeMs: 0, text: 'hello'),
        const LyricLine(timeMs: 10, text: 'world'),
      ];
      final c = [
        const LyricLine(timeMs: 0, text: 'hello'),
        const LyricLine(timeMs: 10, text: 'WORLD'),
      ];
      expect(desktopLyricHash(a), desktopLyricHash(b));
      expect(desktopLyricHash(a), isNot(desktopLyricHash(c)));
    });

    test('bounds wire clamps insane sizes', () {
      final b = DesktopLyricBounds.fromWire({
        'x': 10.0,
        'y': 20.0,
        'width': 99999.0,
        'height': 1.0,
      });
      expect(b.x, 10.0);
      expect(b.width, 1600.0);
      expect(b.height, 60.0);
      expect(b.hasPosition, isTrue);
    });
  });
}
