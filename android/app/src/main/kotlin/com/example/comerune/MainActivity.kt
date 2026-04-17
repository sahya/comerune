package com.example.comerune

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.comerune.speech.infrastructure.plugin.CommentSpeechPlugin

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.comerune/cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register CommentSpeechPlugin for VoiceVox TTS
        flutterEngine.plugins.add(CommentSpeechPlugin())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getCookies") {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("INVALID_ARGUMENT", "url is required", null)
                        return@setMethodCallHandler
                    }
                    val cookies = CookieManager.getInstance().getCookie(url)
                    result.success(cookies ?: "")
                } else {
                    result.notImplemented()
                }
            }
    }
}
