package com.example.comerune

import android.content.Intent
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val COOKIE_CHANNEL = "com.example.comerune/cookies"
    private val FOREGROUND_SERVICE_CHANNEL = "com.example.comerune/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COOKIE_CHANNEL)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        val title = call.argument<String>("title") ?: "comerune"
                        val body = call.argument<String>("body") ?: "接続中..."
                        val intent = Intent(this, ForegroundService::class.java).apply {
                            action = ForegroundService.ACTION_START
                            putExtra(ForegroundService.EXTRA_TITLE, title)
                            putExtra(ForegroundService.EXTRA_BODY, body)
                        }
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "updateNotification" -> {
                        val title = call.argument<String>("title") ?: "comerune"
                        val body = call.argument<String>("body") ?: "接続中..."
                        val intent = Intent(this, ForegroundService::class.java).apply {
                            action = ForegroundService.ACTION_UPDATE
                            putExtra(ForegroundService.EXTRA_TITLE, title)
                            putExtra(ForegroundService.EXTRA_BODY, body)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "stopService" -> {
                        val intent = Intent(this, ForegroundService::class.java).apply {
                            action = ForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
