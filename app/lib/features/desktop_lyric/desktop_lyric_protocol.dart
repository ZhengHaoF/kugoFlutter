import '../../core/models/track.dart';
import 'desktop_lyric_style.dart';

/// 桌面歌词子窗口 arguments 标识。
const String kDesktopLyricWindowArg = 'desktop_lyric';

/// 主窗 ↔ 歌词窗通信通道（bidirectional 配对）。
const String kDesktopLyricChannel = 'kugo/desktop_lyric';

/// 播放态快照：主窗组装后经 `snapshot` 推给歌词窗。
class DesktopLyricSnapshot {
  const DesktopLyricSnapshot({
    this.trackId = '',
    this.title = '',
    this.artist = '',
    this.isPlaying = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.lyrics = const [],
    this.lyricsReady = false,
    this.lyricHash = 0,
    this.revision = 0,
    this.translation = true,
    this.romanization = false,
    this.fontScale = 1.0,
    this.locked = false,
    this.offsetMs = 0,
    this.style = const DesktopLyricStyle(),
  });

  final String trackId;
  final String title;
  final String artist;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final List<LyricLine> lyrics;

  /// true = 歌词已加载（ready）；false = idle/loading/empty。
  final bool lyricsReady;

  /// 切歌/换词去重：内容指纹 + 递增 revision。
  final int lyricHash;
  final int revision;

  final bool translation;
  final bool romanization;
  final double fontScale;
  final bool locked;
  final int offsetMs;

  /// 外观（颜色 / 描边 / 背景 / 字重）。仅样式变化时也会触发推送。
  final DesktopLyricStyle style;

  /// 歌词窗本地游标 = positionMs + offsetMs。
  int get effectivePositionMs => positionMs + offsetMs;

  Map<String, Object?> toWire() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'isPlaying': isPlaying,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lyrics': [for (final l in lyrics) encodeLyricLine(l)],
        'lyricsReady': lyricsReady,
        'lyricHash': lyricHash,
        'revision': revision,
        'translation': translation,
        'romanization': romanization,
        'fontScale': fontScale,
        'locked': locked,
        'offsetMs': offsetMs,
      'style': style.toWire(),
      };

  static DesktopLyricSnapshot fromWire(Object? raw) {
    final m = (raw as Map?)?.cast<String, Object?>() ?? const {};
    return DesktopLyricSnapshot(
      trackId: m['trackId'] as String? ?? '',
      title: m['title'] as String? ?? '',
      artist: m['artist'] as String? ?? '',
      isPlaying: m['isPlaying'] as bool? ?? false,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      lyrics: [
        for (final item in (m['lyrics'] as List? ?? const []))
          decodeLyricLine(item),
      ],
      lyricsReady: m['lyricsReady'] as bool? ?? false,
      lyricHash: (m['lyricHash'] as num?)?.toInt() ?? 0,
      revision: (m['revision'] as num?)?.toInt() ?? 0,
      translation: m['translation'] as bool? ?? true,
      romanization: m['romanization'] as bool? ?? false,
      fontScale: (m['fontScale'] as num?)?.toDouble() ?? 1.0,
      locked: m['locked'] as bool? ?? false,
      offsetMs: (m['offsetMs'] as num?)?.toInt() ?? 0,
      style: DesktopLyricStyle.fromWire(m['style']),
    );
  }

  DesktopLyricSnapshot copyWith({
    String? trackId,
    String? title,
    String? artist,
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    List<LyricLine>? lyrics,
    bool? lyricsReady,
    int? lyricHash,
    int? revision,
    bool? translation,
    bool? romanization,
    double? fontScale,
    bool? locked,
    int? offsetMs,
    DesktopLyricStyle? style,
  }) {
    return DesktopLyricSnapshot(
      trackId: trackId ?? this.trackId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lyrics: lyrics ?? this.lyrics,
      lyricsReady: lyricsReady ?? this.lyricsReady,
      lyricHash: lyricHash ?? this.lyricHash,
      revision: revision ?? this.revision,
      translation: translation ?? this.translation,
      romanization: romanization ?? this.romanization,
      fontScale: fontScale ?? this.fontScale,
      locked: locked ?? this.locked,
      offsetMs: offsetMs ?? this.offsetMs,
      style: style ?? this.style,
    );
  }
}

Object encodeLyricLine(LyricLine line) => {
      't': line.timeMs,
      'e': line.endMs,
      'x': line.text,
      'c': [
        for (final c in line.chars)
          {'x': c.text, 's': c.startMs, 'e': c.endMs},
      ],
      'tr': line.translated,
      'ro': line.romanized,
    };

LyricLine decodeLyricLine(Object? raw) {
  final m = (raw as Map?)?.cast<String, Object?>() ?? const {};
  return LyricLine(
    timeMs: (m['t'] as num?)?.toInt() ?? 0,
    endMs: (m['e'] as num?)?.toInt(),
    text: m['x'] as String? ?? '',
    chars: [
      for (final c in (m['c'] as List? ?? const []))
        LyricChar(
          text: (c as Map)['x'] as String? ?? '',
          startMs: (c['s'] as num?)?.toInt() ?? 0,
          endMs: (c['e'] as num?)?.toInt() ?? 0,
        ),
    ],
    translated: m['tr'] as String?,
    romanized: m['ro'] as String?,
  );
}

/// 歌词线内容指纹（切歌/换词判定，不依赖对象 identity）。
int desktopLyricHash(List<LyricLine> lyrics) {
  var h = 0;
  for (final l in lyrics) {
    h = 0x1fffffff & (h + l.timeMs);
    h = 0x1fffffff & (h + l.text.hashCode);
    h = 0x1fffffff & (h + (l.translated?.hashCode ?? 0));
    h = 0x1fffffff & (h + (l.romanized?.hashCode ?? 0));
    h = 0x1fffffff & (h + l.chars.length);
  }
  return h;
}

/// 歌词窗 → 主窗命令。
abstract final class DesktopLyricCommand {
  static const ready = 'ready';
  static const playPause = 'playPause';
  static const next = 'next';
  static const previous = 'previous';
  static const close = 'close';
  static const toggleLock = 'toggleLock';
  static const bounds = 'bounds';
  static const closed = 'closed';
}
