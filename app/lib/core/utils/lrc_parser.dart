import '../../core/models/track.dart';

/// Minimal LRC parser supporting [mm:ss.xx] / [mm:ss.xxx] tags.
List<LyricLine> parseLrc(String raw) {
  final timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final matches = timeTag.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line
        .replaceAll(timeTag, '')
        .replaceAll(RegExp(r'^\s+|\s+$'), '');
    if (text.isEmpty) continue;
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3) ?? '0';
      var frac = 0;
      if (fracRaw.length == 1) {
        frac = int.parse(fracRaw) * 100;
      } else if (fracRaw.length == 2) {
        frac = int.parse(fracRaw) * 10;
      } else {
        frac = int.parse(fracRaw.substring(0, 3));
      }
      final ms = min * 60000 + sec * 1000 + frac;
      lines.add(LyricLine(timeMs: ms, text: text));
    }
  }
  lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  // 回填 endMs：用下一行起点，末行 +3s（无精确时长）。
  for (var i = 0; i < lines.length; i++) {
    final start = lines[i].timeMs;
    final end = i + 1 < lines.length
        ? lines[i + 1].timeMs
        : start + 3000;
    lines[i] = LyricLine(
      timeMs: start,
      endMs: end > start ? end : start + 1,
      text: lines[i].text,
    );
  }
  return lines;
}

/// Index of the line whose timestamp is <= [positionMs], or `-1` when even the
/// first line has not started yet.
///
/// Binary search: the old linear scan ran per visible lyric row on **every**
/// position tick (O(rows × lines) per frame) and once per engine sample in the
/// controller. [lines] must be sorted by [LyricLine.timeMs] ascending — the
/// parsers sort before returning.
int findLyricIndex(List<LyricLine> lines, int positionMs) {
  var low = 0;
  var high = lines.length - 1;
  var active = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lines[mid].timeMs <= positionMs) {
      active = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return active;
}

/// [findLyricIndex] clamped to `0`, i.e. the index a lyrics view highlights.
int activeLyricIndex(List<LyricLine> lines, int positionMs) {
  if (lines.isEmpty) return 0;
  final found = findLyricIndex(lines, positionMs);
  return found < 0 ? 0 : found;
}
