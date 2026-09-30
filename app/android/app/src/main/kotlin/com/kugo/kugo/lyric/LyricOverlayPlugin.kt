package com.kugo.kugo.lyric

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `kugo/lyric_overlay` MethodChannel：Dart 桥 ↔ 原生悬浮窗。
 *
 * Dart → Native：show / hide / updateSnapshot / resetPosition / applyBounds /
 *                canDrawOverlays / openOverlaySettings
 * Native → Dart：command (tap/close/toggleLock/playPause/next/previous/bounds)
 */
class LyricOverlayPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingShowSnapshot: LyricSnapshot? = null

    init {
        channel.setMethodCallHandler(this)
        LyricOverlayHost.setCommandListener { method, data ->
            val args = mutableMapOf<String, Any?>("m" to method)
            if (data.isNotEmpty()) args["d"] = data
            channel.invokeMethod("command", args)
        }
        LyricOverlayHost.onBoundsChanged = { data ->
            channel.invokeMethod(
                "command",
                mapOf("m" to "bounds", "d" to data),
            )
        }
    }

    fun dispose() {
        LyricOverlayHost.setCommandListener(null)
        LyricOverlayHost.onBoundsChanged = null
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canDrawOverlays" -> {
                result.success(LyricOverlayHost.canDrawOverlays(context))
            }
            "openOverlaySettings" -> {
                openOverlaySettings()
                result.success(true)
            }
            "show" -> {
                val snap = LyricWire.parseSnapshot(call.argument<Any>("snapshot"))
                pendingShowSnapshot = snap
                val bx = (call.argument<Number>("boundsX") as? Number)?.toInt()
                val by = (call.argument<Number>("boundsY") as? Number)?.toInt()
                if (LyricOverlayHost.canDrawOverlays(context)) {
                    val ok = LyricOverlayHost.show(context, snap, bx, by)
                    result.success(ok)
                } else {
                    result.success(false)
                }
            }
            "updateSnapshot" -> {
                val snap = LyricWire.parseSnapshot(call.argument<Any>("snapshot"))
                if (LyricOverlayHost.isShowing) {
                    LyricOverlayHost.update(snap)
                } else {
                    pendingShowSnapshot = snap
                }
                result.success(true)
            }
            "hide" -> {
                LyricOverlayHost.hide()
                result.success(true)
            }
            "resetPosition" -> {
                LyricOverlayHost.resetPosition()
                result.success(LyricOverlayHost.bounds())
            }
            "applyBounds" -> {
                val x = (call.argument<Number>("x") ?: 0).toInt()
                val y = (call.argument<Number>("y") ?: 0).toInt()
                LyricOverlayHost.applyBounds(x, y)
                result.success(true)
            }
            "getBounds" -> {
                result.success(LyricOverlayHost.bounds())
            }
            "isShowing" -> {
                result.success(LyricOverlayHost.isShowing)
            }
            else -> result.notImplemented()
        }
    }

    private fun openOverlaySettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // 部分 ROM 不支持直接跳悬浮窗权限页，退回应用详情。
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                context.startActivity(fallback)
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        const val CHANNEL = "kugo/lyric_overlay"

        @Volatile
        private var instance: LyricOverlayPlugin? = null

        fun register(activity: Activity, messenger: BinaryMessenger) {
            instance?.dispose()
            instance = LyricOverlayPlugin(activity.applicationContext, messenger)
        }

        fun dispose() {
            instance?.dispose()
            instance = null
        }
    }
}
