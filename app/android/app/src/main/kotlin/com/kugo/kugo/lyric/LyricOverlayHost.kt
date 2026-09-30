package com.kugo.kugo.lyric

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager

/**
 * 悬浮歌词宿主：用 Application Context 管理 TYPE_APPLICATION_OVERLAY。
 *
 * 不另起第二个前台服务——进程由 audio_service 的 mediaPlayback FGS 保活，
 * 歌词 overlay 只是挂在进程上的一个系统窗口。
 */
object LyricOverlayHost {
    private var view: LyricOverlayView? = null
    private var wm: WindowManager? = null
    private var appContext: Context? = null
    private var commandListener: ((String, Map<String, Any?>) -> Unit)? = null

    var onBoundsChanged: ((Map<String, Any?>) -> Unit)? = null

    val isShowing: Boolean get() = view != null

    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    fun setCommandListener(listener: ((String, Map<String, Any?>) -> Unit)?) {
        commandListener = listener
    }

    /**
     * 显示悬浮窗。已有则只更新内容。
     * @return true=成功；false=无悬浮窗权限。
     */
    fun show(context: Context, snapshot: LyricSnapshot, boundsX: Int? = null, boundsY: Int? = null): Boolean {
        appContext = context.applicationContext
        if (!canDrawOverlays(context)) return false

        val existing = view
        if (existing != null) {
            existing.applySnapshot(snapshot)
            existing.setClickThrough(snapshot.locked)
            return true
        }

        val windowManager =
            context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = context.resources.displayMetrics.density
        val width = (320 * density).toInt().coerceAtLeast(280)
        val height = (72 * density).toInt().coerceAtLeast(56)

        val params = WindowManager.LayoutParams(
            width,
            height,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = boundsX ?: 0
            y = boundsY ?: (48 * density).toInt()
            if (snapshot.locked) {
                flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            }
        }

        val v = LyricOverlayView(context.applicationContext) { method, data ->
            when (method) {
                "bounds" -> onBoundsChanged?.invoke(data)
                else -> commandListener?.invoke(method, data)
            }
        }
        v.layoutParamsRef = params
        v.windowManagerRef = windowManager
        v.applySnapshot(snapshot)

        return try {
            windowManager.addView(v, params)
            view = v
            wm = windowManager
            true
        } catch (e: Exception) {
            false
        }
    }

    fun update(snapshot: LyricSnapshot) {
        val v = view ?: return
        v.applySnapshot(snapshot)
        v.setClickThrough(snapshot.locked)
    }

    fun hide() {
        val v = view ?: return
        val manager = wm ?: return
        try {
            v.removeCallbacks(null)
            manager.removeViewImmediate(v)
        } catch (_: Exception) {
        }
        view = null
        wm = null
    }

    fun resetPosition() {
        view?.resetToTopCenter()
    }

    fun bounds(): Map<String, Any?> {
        val v = view ?: return emptyMap()
        val lp = v.layoutParamsRef ?: return emptyMap()
        return mapOf(
            "x" to lp.x.toFloat(),
            "y" to lp.y.toFloat(),
            "width" to lp.width.toFloat(),
            "height" to lp.height.toFloat(),
        )
    }

    fun applyBounds(x: Int, y: Int) {
        val v = view ?: return
        val manager = wm ?: return
        val lp = v.layoutParamsRef ?: return
        lp.x = x
        lp.y = y
        try {
            manager.updateViewLayout(v, lp)
        } catch (_: Exception) {
        }
    }
}
