package com.kugo.kugo.lyric

/**
 * 桌面歌词 wire 协议解析（与 Dart `desktop_lyric_protocol.dart` 对齐）。
 *
 * 快照字段见 `DesktopLyricSnapshot.toWire()`；行编码见 `encodeLyricLine()`。
 */
data class LyricChar(
    val text: String,
    val startMs: Int,
    val endMs: Int,
)

data class LyricLine(
    val timeMs: Int,
    val endMs: Int?,
    val text: String,
    val chars: List<LyricChar> = emptyList(),
    val translated: String? = null,
    val romanized: String? = null,
) {
    val hasCharTiming: Boolean get() = chars.isNotEmpty()
}

data class LyricStyle(
    val sungColor: Int = 0xFF2CE06B.toInt(),
    val unsungColor: Int = 0xFFFFFFFF.toInt(),
    val strokeColor: Int = 0xFF000000.toInt(),
    val strokeWidth: Float = 1.2f,
    val bgColor: Int = 0xFF000000.toInt(),
    val bgOpacity: Float = 0f,
    val bgRadius: Float = 14f,
    val fontScale: Float = 1f,
    val fontWeight: Float = 1f,
) {
    val hasBackground: Boolean get() = bgOpacity > 0.004f
    val hasStroke: Boolean get() = strokeWidth > 0.004f

    /** 1.0 → 700；映射到 400..900 的最近 Material 档位。 */
    fun resolveFontWeight(): Int {
        val w = (400f + (fontWeight.coerceIn(0f, 2f)) * 250f).coerceIn(400f, 900f)
        val steps = intArrayOf(400, 500, 600, 700, 800, 900)
        var best = steps[0]
        for (s in steps) {
            if (kotlin.math.abs(s - w) < kotlin.math.abs(best - w)) best = s
        }
        return best
    }
}

data class LyricSnapshot(
    val trackId: String = "",
    val title: String = "",
    val artist: String = "",
    val isPlaying: Boolean = false,
    val positionMs: Int = 0,
    val durationMs: Int = 0,
    val lyrics: List<LyricLine> = emptyList(),
    val lyricsReady: Boolean = false,
    val lyricHash: Int = 0,
    val revision: Int = 0,
    val translation: Boolean = true,
    val romanization: Boolean = false,
    val fontScale: Float = 1f,
    val locked: Boolean = false,
    val offsetMs: Int = 0,
    val style: LyricStyle = LyricStyle(),
    /** 主窗省略歌词数组（positionOnly 推送）时 true，保留本地 lyrics。 */
    val lyricsOmitted: Boolean = false,
) {
    val effectivePositionMs: Int get() = positionMs + offsetMs

    fun activeIndex(positionMs: Int): Int {
        if (lyrics.isEmpty()) return -1
        var low = 0
        var high = lyrics.size - 1
        var active = -1
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (lyrics[mid].timeMs <= positionMs) {
                active = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return active
    }
}

object LyricWire {
    fun parseSnapshot(raw: Any?): LyricSnapshot {
        val m = raw as? Map<*, *> ?: return LyricSnapshot()
        val lyricsRaw = m["lyrics"] as? List<*>
        val omitted = m["lyricsOmitted"] == true
        val lyrics = if (lyricsRaw == null) {
            emptyList()
        } else {
            lyricsRaw.mapNotNull { parseLine(it) }
        }
        return LyricSnapshot(
            trackId = m["trackId"] as? String ?: "",
            title = m["title"] as? String ?: "",
            artist = m["artist"] as? String ?: "",
            isPlaying = m["isPlaying"] == true,
            positionMs = (m["positionMs"] as? Number)?.toInt() ?: 0,
            durationMs = (m["durationMs"] as? Number)?.toInt() ?: 0,
            lyrics = lyrics,
            lyricsReady = m["lyricsReady"] == true,
            lyricHash = (m["lyricHash"] as? Number)?.toInt() ?: 0,
            revision = (m["revision"] as? Number)?.toInt() ?: 0,
            translation = m["translation"] as? Boolean ?: true,
            romanization = m["romanization"] == true,
            fontScale = (m["fontScale"] as? Number)?.toFloat() ?: 1f,
            locked = m["locked"] == true,
            offsetMs = (m["offsetMs"] as? Number)?.toInt() ?: 0,
            style = parseStyle(m["style"]),
            lyricsOmitted = omitted,
        )
    }

    fun parseLine(raw: Any?): LyricLine? {
        val m = raw as? Map<*, *> ?: return null
        val text = m["x"] as? String ?: return null
        val chars = (m["c"] as? List<*>).orEmpty().mapNotNull { c ->
            val cm = c as? Map<*, *> ?: return@mapNotNull null
            val ct = cm["x"] as? String ?: return@mapNotNull null
            LyricChar(
                text = ct,
                startMs = (cm["s"] as? Number)?.toInt() ?: 0,
                endMs = (cm["e"] as? Number)?.toInt() ?: 0,
            )
        }
        return LyricLine(
            timeMs = (m["t"] as? Number)?.toInt() ?: 0,
            endMs = (m["e"] as? Number)?.toInt(),
            text = text,
            chars = chars,
            translated = m["tr"] as? String,
            romanized = m["ro"] as? String,
        )
    }

    fun parseStyle(raw: Any?): LyricStyle {
        val m = raw as? Map<*, *> ?: return LyricStyle()
        return LyricStyle(
            sungColor = color(m["sungColor"], 0xFF2CE06B.toInt()),
            unsungColor = color(m["unsungColor"], 0xFFFFFFFF.toInt()),
            strokeColor = color(m["strokeColor"], 0xFF000000.toInt()),
            strokeWidth = clamp(m["strokeWidth"], 0f, 6f, 1.2f),
            bgColor = color(m["bgColor"], 0xFF000000.toInt()),
            bgOpacity = clamp(m["bgOpacity"], 0f, 1f, 0f),
            bgRadius = clamp(m["bgRadius"], 0f, 40f, 14f),
            fontScale = clamp(m["fontScale"], 0.6f, 2f, 1f),
            fontWeight = clamp(m["fontWeight"], 0f, 2f, 1f),
        )
    }

    private fun color(v: Any?, fallback: Int): Int =
        (v as? Number)?.toInt() ?: fallback

    private fun clamp(v: Any?, min: Float, max: Float, fallback: Float): Float {
        val n = (v as? Number)?.toFloat() ?: return fallback
        if (n < min || n > max) return fallback
        return n
    }
}
