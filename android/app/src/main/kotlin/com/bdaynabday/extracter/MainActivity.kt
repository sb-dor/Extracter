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
    /** Latest progress of the running work (transcription, model download), or null when idle. */
    private var content: TranscriptionService.Content? = null

    /** False between onStop and onStart: the progress notification is shown only then. */
    private var visible = false

    /** True while the foreground service (and its notification) is running. */
    private var serviceRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    update(
                        TranscriptionService.Content(
                            channelName = call.argument<String>("channel") ?: "Extracter",
                            title = call.argument<String>("title") ?: "Extracter",
                            publicTitle = call.argument<String>("publicTitle") ?: "Extracter",
                            text = call.argument<String>("text") ?: "",
                            permille = call.argument<Int>("permille") ?: -1,
                            kinds = call.argument<List<String>>("kinds") ?: emptyList(),
                        ),
                    )
                    result.success(null)
                }
                "clear" -> {
                    content = null
                    stopBackgroundService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun update(next: TranscriptionService.Content) {
        // Asked while the app is still on screen, before the first notification is due.
        if (content == null && visible) requestNotificationPermission()
        content = next
        if (!visible) startOrUpdateBackgroundService(next)
    }

    override fun onStart() {
        super.onStart()
        visible = true
        // Back on screen: the app shows progress itself, so the notification goes away.
        stopBackgroundService()
    }

    override fun onStop() {
        super.onStop()
        if (isChangingConfigurations) return
        visible = false
        // Leaving the screen is the moment Android 12+ still allows a foreground-service start.
        content?.let(::startOrUpdateBackgroundService)
    }

    /** Starts the service on the way to the background, then only refreshes its notification. */
    private fun startOrUpdateBackgroundService(content: TranscriptionService.Content) {
        if (serviceRunning) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(TranscriptionService.NOTIFICATION_ID, TranscriptionService.buildNotification(this, content))
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(content.toIntent(this))
            } else {
                startService(content.toIntent(this))
            }
            serviceRunning = true
        } catch (e: IllegalStateException) {
            // Background start refused (Android 12+): the work runs until Android suspends the app.
        }
    }

    private fun stopBackgroundService() {
        if (!serviceRunning) return
        serviceRunning = false
        stopService(TranscriptionService.Content.fromIntent(null).toIntent(this))
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        // Android itself stops asking after the user declines twice.
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
    }

    // Back on the first screen would finish the activity and end the Dart side
    // of running work; while working, send the app to the background instead.
    override fun popSystemNavigator(): Boolean {
        if (content == null) return false
        moveTaskToBack(true)
        return true
    }

    companion object {
        private const val CHANNEL = "extracter/background_work"
    }
}
