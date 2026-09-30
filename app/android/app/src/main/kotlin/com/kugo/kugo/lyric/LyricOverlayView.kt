package com.kugo.kugo.lyric

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import kotlin.math.abs
import kotlin.math.max

/**
 * 悬浮歌词 View：当前行卡拉 OK 扫光 + 下一行预览。
 *
 * 绘制语义对齐 Dart `karaoke_sweep_line.dart`：
 * 底层未唱整行 + 上层已唱按扫光边界 clip；KRC 逐字插值，LRC 整行线性扫。
 */
class LyricOverlayView(context: Context, private val onCommand: (String, Map<String, Any?>) -> Unit) :
    View(context) {

    private var snapshot = LyricSnapshot()
    private var anchorWallMs = System.currentTimeMillis()
    private var anchorPosMs = 0

    private val density = context.resources.displayMetrics.density

    private val basePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
    }
    private val sungPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
    }
    private val strokePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        textAlign = Paint.Align.LEFT
    }
    private val nextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.LEFT
    }
    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var layoutText: String? = null
    private var layoutWidth = 0f
    private var prefixWidths: FloatArray = FloatArray(0)
    private var baseTextWidth = 0f

    private var locked = false
    private var downRawX = 0f
    private var downRawY = 0f
    private var downParamsX = 0
    private var downParamsY = 0
    private var dragging = false
    private var longPressFired = false
    private val longPressRunnable = Runnable {
        if (!dragging) {
            longPressFired = true
            onCommand("longPress", emptyMap())
        }
    }

    var layoutParamsRef: WindowManager.LayoutParams? = null
    var windowManagerRef: WindowManager? = null

    fun applySnapshot(snap: LyricSnapshot) {
        val trackChanged = snap.trackId != snapshot.trackId
        val revChanged = snap.revision != snapshot.revision
        snapshot = if (snap.lyricsOmitted && !trackChanged && !revChanged) {
            snap.copy(lyrics = snapshot.lyrics)
        } else if (snap.lyricsOmitted && (trackChanged || revChanged)) {
            snap.copy(lyrics = emptyList())
        } else {
            snap
        }
        locked = snapshot.locked
        // 对时锚点：本地 Ticker 自走，主窗 400ms 校准。
        anchorWallMs = System.currentTimeMillis()
        anchorPosMs = snapshot.effectivePositionMs
        invalidate()
    }

    fun currentPositionMs(): Int {
        if (!snapshot.isPlaying) return anchorPosMs
        val elapsed = (System.currentTimeMillis() - anchorWallMs).toInt()
        return anchorPosMs + elapsed
    }

    private fun style() = snapshot.style

    private fun fontSize(): Float =
        24f * density * style().fontScale.coerceIn(0.6f, 2f)

    private fun nextFontSize(): Float = fontSize() * 0.72f

    private fun applyPaintStyle(p: TextPaint, color: Int, size: Float) {
        val st = style()
        p.color = color
        p.textSize = size
        p.typeface = Typeface.create(Typeface.DEFAULT, st.resolveFontWeight(), false)
        p.letterSpacing = 0.3f / 24f
        if (st.hasShadow) {
            val s = st.shadowStrength.coerceIn(0f, 3f)
            val alpha = (0x85 * s).toInt().coerceIn(0, 255)
            val shadowColor = (st.shadowColor and 0x00FFFFFF) or (alpha shl 24)
            p.setShadowLayer(10f * s * density, 0f, 2f * s * density, shadowColor)
        } else {
            p.clearShadowLayer()
        }
    }

    private fun rebuildLayout(text: String, maxWidth: Float) {
        if (layoutText == text && layoutWidth == maxWidth) return
        layoutText = text
        layoutWidth = maxWidth
        val st = style()
        applyPaintStyle(basePaint, st.unsungColor, fontSize())
        applyPaintStyle(sungPaint, st.sungColor, fontSize())
        strokePaint.color = st.strokeColor
        strokePaint.textSize = fontSize()
        strokePaint.typeface = Typeface.create(Typeface.DEFAULT, st.resolveFontWeight(), false)
        strokePaint.strokeWidth = st.strokeWidth * density
        strokePaint.strokeJoin = Paint.Join.ROUND
        strokePaint.strokeCap = Paint.Cap.ROUND
        strokePaint.clearShadowLayer()

        val widths = FloatArray(text.length)
        var x = 0f
        for (i in text.indices) {
            val w = basePaint.measureText(text, i, i + 1)
            widths[i] = x
            x += w
        }
        prefixWidths = widths
        baseTextWidth = basePaint.measureText(text)
    }

    /** 扫光边界 x（相对文本左缘），算法与 Dart `_computeSweepX` 一致。 */
    private fun computeSweepX(): Float {
        val idx = snapshot.activeIndex(currentPositionMs())
        if (idx < 0 || idx >= snapshot.lyrics.size) return 0f
        val line = snapshot.lyrics[idx]
        if (line.text.isEmpty() || baseTextWidth <= 0f) return 0f
        val pos = currentPositionMs()

        if (!line.hasCharTiming) {
            val start = line.timeMs
            val end = line.endMs ?: (start + 3000)
            if (pos <= start) return 0f
            if (pos >= end) return baseTextWidth
            return baseTextWidth * (pos - start) / (end - start)
        }

        val chars = line.chars
        if (pos <= chars.first().startMs) return 0f

        var lo = 0
        var hi = chars.size - 1
        var found = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (chars[mid].startMs <= pos) {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if (found < 0) return 0f

        val cur = chars[found]
        val nextStart = if (found + 1 < chars.size) chars[found + 1].startMs else cur.endMs
        val w0 = if (found < prefixWidths.size) prefixWidths[found] else baseTextWidth
        val w1 = if (found + 1 < prefixWidths.size) prefixWidths[found + 1] else baseTextWidth
        if (pos >= nextStart && pos >= cur.endMs) return w1.coerceIn(0f, baseTextWidth)

        val dur = cur.endMs - cur.startMs
        val f = if (dur > 0) (pos - cur.startMs).toFloat() / dur else 1f
        return (w0 + (w1 - w0) * f).coerceIn(0f, baseTextWidth)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val st = style()
        val padH = 12f * density
        val padV = 8f * density
        val w = width.toFloat()
        val h = height.toFloat()
        val contentW = (w - padH * 2).coerceAtLeast(0f)

        if (st.hasBackground) {
            val alpha = (st.bgOpacity * 255).toInt().coerceIn(0, 255)
            bgPaint.color = (st.bgColor and 0x00FFFFFF) or (alpha shl 24)
            canvas.drawRoundRect(
                RectF(0f, 0f, w, h),
                st.bgRadius * density,
                st.bgRadius * density,
                bgPaint,
            )
        }

        val idx = snapshot.activeIndex(currentPositionMs())
        val current = if (idx in snapshot.lyrics.indices) snapshot.lyrics[idx] else null
        val next = if (idx + 1 in snapshot.lyrics.indices) snapshot.lyrics[idx + 1] else null

        val titleLine = current?.text?.takeIf { it.isNotEmpty() }
            ?: snapshot.title.takeIf { it.isNotEmpty() }
            ?: "桌面歌词"

        rebuildLayout(titleLine, contentW)

        val mainSize = fontSize()
        val baselineMain = padV + mainSize * 0.92f

        // 描边
        if (st.hasStroke) {
            canvas.drawText(titleLine, padH, baselineMain, strokePaint)
        }

        // 未唱整行
        canvas.drawText(titleLine, padH, baselineMain, basePaint)

        // 已唱扫光
        val sweepX = computeSweepX()
        if (sweepX > 0.5f) {
            canvas.save()
            canvas.clipRect(padH, 0f, padH + sweepX, h)
            canvas.drawText(titleLine, padH, baselineMain, sungPaint)
            canvas.restore()
        }

        // 下一行 / 译文
        val subText = when {
            snapshot.translation && !current?.translated.isNullOrEmpty() ->
                current!!.translated!!
            next != null && next.text.isNotEmpty() -> next.text
            snapshot.artist.isNotEmpty() -> snapshot.artist
            else -> null
        }
        if (subText != null) {
            applyPaintStyle(nextPaint, st.unsungColor, nextFontSize())
            nextPaint.alpha = 190
            val baselineNext = baselineMain + mainSize * 0.95f
            if (baselineNext < h - 2f * density) {
                canvas.drawText(subText, padH, baselineNext, nextPaint)
            }
        }

        // 播放中且有词时持续重绘（扫光 60fps 由 Choreographer 驱动）
        if (snapshot.isPlaying && current != null && current.text.isNotEmpty()) {
            postInvalidateOnAnimation()
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (locked) {
            // 锁定：不处理手势，点击穿透由 FLAG_NOT_TOUCHABLE 控制。
            return false
        }
        val lp = layoutParamsRef ?: return false
        val wm = windowManagerRef ?: return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = event.rawX
                downRawY = event.rawY
                downParamsX = lp.x
                downParamsY = lp.y
                dragging = false
                longPressFired = false
                // 长按 = 下一首（锁定穿透时到不了这里）。
                removeCallbacks(longPressRunnable)
                postDelayed(longPressRunnable, 480)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - downRawX
                val dy = event.rawY - downRawY
                if (!dragging && (abs(dx) > 8f * density || abs(dy) > 8f * density)) {
                    dragging = true
                }
                if (dragging) {
                    lp.x = downParamsX + dx.toInt()
                    lp.y = downParamsY + dy.toInt()
                    try {
                        wm.updateViewLayout(this, lp)
                    } catch (_: Exception) {
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(longPressRunnable)
                if (dragging) {
                    onCommand(
                        "bounds",
                        mapOf(
                            "x" to lp.x.toFloat(),
                            "y" to lp.y.toFloat(),
                            "width" to lp.width.toFloat(),
                            "height" to lp.height.toFloat(),
                        ),
                    )
                    dragging = false
                } else if (event.actionMasked == MotionEvent.ACTION_UP && !longPressFired) {
                    // 轻点：播放/暂停
                    onCommand("tap", emptyMap())
                }
                longPressFired = false
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    /** 锁定态切换 FLAG_NOT_TOUCHABLE，实现点击穿透。 */
    fun setClickThrough(enabled: Boolean) {
        val lp = layoutParamsRef ?: return
        val wm = windowManagerRef ?: return
        lp.flags = if (enabled) {
            lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        }
        try {
            wm.updateViewLayout(this, lp)
        } catch (_: Exception) {
        }
    }

    fun resetToTopCenter() {
        val lp = layoutParamsRef ?: return
        val wm = windowManagerRef ?: return
        lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        lp.x = 0
        lp.y = (48 * density).toInt()
        try {
            wm.updateViewLayout(this, lp)
        } catch (_: Exception) {
        }
        onCommand(
            "bounds",
            mapOf(
                "x" to lp.x.toFloat(),
                "y" to lp.y.toFloat(),
                "width" to lp.width.toFloat(),
                "height" to lp.height.toFloat(),
            ),
        )
    }

    companion object {
        fun defaultWidth(context: Context): Int =
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                320f,
                context.resources.displayMetrics,
            ).toInt().coerceAtLeast(280)

        fun defaultHeight(context: Context): Int =
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                72f,
                context.resources.displayMetrics,
            ).toInt().coerceAtLeast(56)
    }
}
