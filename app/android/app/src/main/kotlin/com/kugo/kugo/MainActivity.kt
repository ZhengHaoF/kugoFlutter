package com.kugo.kugo

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import com.kugo.kugo.lyric.LyricOverlayPlugin

// Required by audio_service for media notification / lock-screen controls.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LyricOverlayPlugin.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LyricOverlayPlugin.dispose()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
