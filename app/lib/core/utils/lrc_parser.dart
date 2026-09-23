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

int findLyricIndex(List<LyricLine> lines, int positionMs) {
  if (lines.isEmpty) return -1;
  var active = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].timeMs <= positionMs) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}
