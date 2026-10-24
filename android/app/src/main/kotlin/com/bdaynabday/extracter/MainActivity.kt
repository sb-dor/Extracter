package com.bdaynabday.extracter

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** True while the background-work notification is shown (files are queued or running). */
    private var working = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val content = TranscriptionService.Content(
                        channelName = call.argument<String>("channel") ?: "Transcription",
                        title = call.argument<String>("title") ?: "Extracter",
                        text = call.argument<String>("text") ?: "",
                        permille = call.argument<Int>("permille") ?: -1,
                    )
                    result.success(show(content))
                }
                "hide" -> {
                    working = false
                    stopService(TranscriptionService.Content.fromIntent(null).toIntent(this))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Starts the service the first time, then only refreshes its notification. */
    private fun show(content: TranscriptionService.Content): Boolean {
        if (!working) {
            requestNotificationPermission()
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(content.toIntent(this))
                } else {
                    startService(content.toIntent(this))
                }
            } catch (e: IllegalStateException) {
                // Background start refused (Android 12+): keep working without it.
                return false
            }
            working = true
            return true
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(TranscriptionService.NOTIFICATION_ID, TranscriptionService.buildNotification(this, content))
        return true
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        // Android itself stops asking after the user declines twice.
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
    }

    // Back on the first screen would finish the activity and end the Dart side
    // of a running transcription; while working, send the app to the background.
    override fun popSystemNavigator(): Boolean {
        if (!working) return false
        moveTaskToBack(true)
        return true
    }

    companion object {
        private const val CHANNEL = "extracter/background_work"
    }
}
