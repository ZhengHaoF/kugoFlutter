import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/core/models/track.dart';
import 'package:kugo/features/desktop_lyric/lyric_window/lyric_window_controller.dart';

List<LyricLine> _lines() => const [
      LyricLine(timeMs: 0, endMs: 4000, text: '第一行'),
      LyricLine(
        timeMs: 4000,
        endMs: 8000,
        text: '第二行',
        translated: 'second line',
      ),
      LyricLine(timeMs: 8000, endMs: 12000, text: '第三行'),
    ];

Object _sig({
  int activeIndex = 0,
  List<LyricLine>? lyrics,
  String title = '歌名',
  String artist = '歌手',
  bool isPlaying = true,
  bool locked = false,
  bool translation = true,
  double fontScale = 1.0,
}) {
  return visibleLyricSignature(
    title: title,
    artist: artist,
    isPlaying: isPlaying,
    locked: locked,
    translation: translation,
    fontScale: fontScale,
    activeIndex: activeIndex,
    lyrics: lyrics ?? _lines(),
  );
}

/// 桌面歌词窗在播放中每 100ms 无条件 notifyListeners，导致整个独立引擎窗口
/// 每秒重建 10 次——即使跨行、标题、播放态全都没变。改为按「可见内容指纹」
/// 去重后，这些用例就是那条回归防线。
void main() {
  test('same line and shape produce an identical signature', () {
    // 游标在同一行内推进（行号不变）→ 不应触发重建。
    expect(_sig(activeIndex: 1), _sig(activeIndex: 1));
  });

  test('advancing to the next line changes the signature', () {
    expect(_sig(activeIndex: 1), isNot(_sig(activeIndex: 2)));
  });

  test('first line is a distinct state from "before any line"', () {
    // findLyricIndex 在首行之前返回 -1，此时显示的是标题占位。
    expect(_sig(activeIndex: -1), isNot(_sig(activeIndex: 0)));
  });

  test('shape and metadata changes all invalidate the signature', () {
    final base = _sig(activeIndex: 1);
    expect(_sig(activeIndex: 1, title: '另一首'), isNot(base));
    expect(_sig(activeIndex: 1, artist: '另一人'), isNot(base));
    expect(_sig(activeIndex: 1, isPlaying: false), isNot(base));
    expect(_sig(activeIndex: 1, locked: true), isNot(base));
    expect(_sig(activeIndex: 1, translation: false), isNot(base));
    expect(_sig(activeIndex: 1, fontScale: 1.3), isNot(base));
  });

  test('next-line preview is part of the signature', () {
    // 主行下方显示「译文优先，否则下一行」；改动下一行必须触发重建。
    final lines = [
      const LyricLine(timeMs: 0, endMs: 1000, text: '第一行'),
      const LyricLine(timeMs: 1000, endMs: 2000, text: '第二行'),
      const LyricLine(timeMs: 2000, endMs: 3000, text: '第三行'),
    ];
    final withoutTr = _sig(activeIndex: 0, lyrics: lines);
    final withTr = _sig(
      activeIndex: 0,
      lyrics: [
        const LyricLine(
          timeMs: 0,
          endMs: 1000,
          text: '第一行',
          translated: 'first',
        ),
        ...lines.skip(1),
      ],
    );
    expect(withTr, isNot(withoutTr));
  });

  test('empty lyrics keep a stable signature across cursor movement', () {
    expect(
      _sig(activeIndex: -1, lyrics: const []),
      _sig(activeIndex: -1, lyrics: const []),
    );
  });
}
