import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/models/track.dart';

/// KRC 容器：`krc1` 魔数 + 16 字节循环 XOR + zlib。
///
/// 公开下载口 `lyrics.kugou.com/download?fmt=krc` 返回 base64 后的该容器；
/// 解密结果是明文 KRC 文本（可含 `[language:…]` 译文/音译块）。
const List<int> _krcKey = <int>[
  0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47, //
  0x51, 0x36, 0x31, 0x2D, 0xCE, 0xD2, 0x6E, 0x69, //
];

/// 解密 KRC 容器为明文歌词文本。失败返回 null。
String? decryptKrc(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final Uint8List body;
  if (bytes.length >= 4 &&
      bytes[0] == 0x6B &&
      bytes[1] == 0x72 &&
      bytes[2] == 0x63 &&
      bytes[3] == 0x31) {
    body = Uint8List.sublistView(bytes, 4);
  } else {
    // 已是明文或非标准封装，直接当文本试。
    try {
      final text = utf8.decode(bytes);
      return text.contains('[') ? text : null;
    } catch (_) {
      return null;
    }
  }

  final dec = Uint8List(body.length);
  for (var i = 0; i < body.length; i++) {
    dec[i] = body[i] ^ _krcKey[i & 15];
  }

  try {
    final out = ZLibDecoder().convert(dec);
    return utf8.decode(out);
  } catch (_) {
    return null;
  }
}

class KrcParseResult {
  const KrcParseResult({
    required this.lines,
    this.hasTranslation = false,
    this.hasRomanization = false,
  });

  final List<LyricLine> lines;
  final bool hasTranslation;
  final bool hasRomanization;
}

class _LangBlock {
  const _LangBlock({this.translation, this.romanization});

  final List<List<String>>? translation;
  final List<List<String>>? romanization;

  static const empty = _LangBlock();
}

/// 解析明文 KRC（含可选 `[language:…]`）。
///
/// 行：`[start,dur]<off,dur,0>字<off,dur,0>字…`
/// language：base64(JSON) → `content:[{type:0|1, lyricContent:[[…],…]}]`
///   type=1 译文，type=0 音译；与主歌词按行序号对齐。
KrcParseResult parseKrc(String raw) {
  final cleaned = raw.replaceFirst('﻿', '').trim();
  if (cleaned.isEmpty) return const KrcParseResult(lines: []);

  final sourceLines = cleaned.split(RegExp(r'\r?\n'));
  String? languageLine;
  for (final l in sourceLines) {
    if (l.startsWith('[language:')) {
      languageLine = l;
      break;
    }
  }
  final lang =
      languageLine == null ? _LangBlock.empty : _decodeLanguageLine(languageLine);

  final charRe = RegExp(r'<(\d+),(\d+),\d+>([^<]*)');
  final parsed = <_KrcDraft>[];

  for (final sourceLine in sourceLines) {
    if (sourceLine.startsWith('[language:')) continue;
    final krcMatch = RegExp(r'^\[(\d+),(\d+)\](.*)$').firstMatch(sourceLine);
    if (krcMatch == null) continue;

    final lineStart = int.parse(krcMatch.group(1)!);
    final lineDur = int.parse(krcMatch.group(2)!);
    final content = krcMatch.group(3) ?? '';
    final chars = <LyricChar>[];

    for (final m in charRe.allMatches(content)) {
      final text = m.group(3) ?? '';
      if (text.isEmpty) continue;
      final offset = int.parse(m.group(1)!);
      final dur = int.parse(m.group(2)!);
      final start = lineStart + offset;
      final end = start + (dur > 0 ? dur : 1);
      chars.add(LyricChar(text: text, startMs: start, endMs: end));
    }

    // 无逐字标签时按整行兜底，保证 timeMs 可用。
    final plain = content.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    if (chars.isEmpty && plain.isEmpty) continue;
    if (chars.isEmpty) {
      chars.add(LyricChar(
        text: plain,
        startMs: lineStart,
        endMs: lineStart + (lineDur > 0 ? lineDur : 1),
      ));
    }

    final text = chars.map((c) => c.text).join();
    parsed.add(_KrcDraft(
      timeMs: chars.first.startMs,
      endMs: chars.last.endMs,
      text: text,
      chars: chars,
    ));
  }

  final translations = lang.translation;
  final romanizations = lang.romanization;
  final lines = <LyricLine>[];
  var hasTranslation = false;
  var hasRomanization = false;

  for (var i = 0; i < parsed.length; i++) {
    final d = parsed[i];
    final translated = _rowText(translations, i);
    final romanized = _rowText(romanizations, i);
    if (translated != null) hasTranslation = true;
    if (romanized != null) hasRomanization = true;
    lines.add(LyricLine(
      timeMs: d.timeMs,
      endMs: d.endMs,
      text: d.text,
      chars: d.chars,
      translated: translated,
      romanized: romanized,
    ));
  }

  return KrcParseResult(
    lines: lines,
    hasTranslation: hasTranslation,
    hasRomanization: hasRomanization,
  );
}

class _KrcDraft {
  const _KrcDraft({
    required this.timeMs,
    required this.endMs,
    required this.text,
    required this.chars,
  });

  final int timeMs;
  final int endMs;
  final String text;
  final List<LyricChar> chars;
}

_LangBlock _decodeLanguageLine(String line) {
  try {
    var code = line.substring('[language:'.length);
    if (code.endsWith(']')) code = code.substring(0, code.length - 1);
    final cleaned = code.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    final pad = (4 - cleaned.length % 4) % 4;
    final padded = cleaned + ('=' * pad);
    final jsonStr = utf8.decode(base64.decode(padded));
    final data = jsonDecode(jsonStr);
    if (data is! Map) return _LangBlock.empty;

    List<List<String>>? translation;
    List<List<String>>? romanization;
    final content = data['content'];
    if (content is List) {
      for (final sec in content) {
        if (sec is! Map) continue;
        final type = sec['type'];
        final rows = _asRows(sec['lyricContent']);
        if (rows == null) continue;
        if (type == 1) translation = rows;
        if (type == 0) romanization = rows;
      }
    }
    return _LangBlock(translation: translation, romanization: romanization);
  } catch (_) {
    return _LangBlock.empty;
  }
}

List<List<String>>? _asRows(dynamic lyricContent) {
  if (lyricContent is! List || lyricContent.isEmpty) return null;
  final rows = <List<String>>[];
  for (final row in lyricContent) {
    if (row is List) {
      rows.add(row.map((e) => e.toString()).toList());
    } else {
      rows.add([row.toString()]);
    }
  }
  return rows;
}

String? _rowText(List<List<String>>? rows, int index) {
  if (rows == null || index < 0 || index >= rows.length) return null;
  final joined = rows[index].join().trim();
  // 纯空白行视为「本行无译文」，避免副行占位。
  return joined.isEmpty ? null : joined;
}
