package com.bdaynabday.extracter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process in the foreground while files are transcribed, so Android
 * neither freezes nor kills it when the user switches apps, and holds a partial
 * wake lock so the CPU keeps working with the screen off. The transcription
 * itself still runs in the native engine; this service only shows progress.
 *
 * Started once while the app is visible (background starts are not allowed on
 * Android 12+); progress updates only re-post the notification.
 */
class TranscriptionService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(this, Content.fromIntent(intent))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, foregroundType())
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Extracter:transcription").apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
        }
        // Not sticky: without the app's isolate there is nobody to report to.
        return START_NOT_STICKY
    }

    // Android 15 limits media-processing services to 6 hours a day.
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    /** What the notification says; [permille] < 0 shows an indeterminate bar. */
    data class Content(val channelName: String, val title: String, val text: String, val permille: Int) {
        fun toIntent(context: Context): Intent = Intent(context, TranscriptionService::class.java)
            .putExtra(EXTRA_CHANNEL, channelName)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_TEXT, text)
            .putExtra(EXTRA_PERMILLE, permille)

        companion object {
            fun fromIntent(intent: Intent?) = Content(
                channelName = intent?.getStringExtra(EXTRA_CHANNEL) ?: "Transcription",
                title = intent?.getStringExtra(EXTRA_TITLE) ?: "Extracter",
                text = intent?.getStringExtra(EXTRA_TEXT) ?: "",
                permille = intent?.getIntExtra(EXTRA_PERMILLE, -1) ?: -1,
            )
        }
    }

    companion object {
        const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "transcription"
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000
        private const val EXTRA_CHANNEL = "channel"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PERMILLE = "permille"

        private fun foregroundType(): Int =
            if (Build.VERSION.SDK_INT >= 35) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC

        fun buildNotification(context: Context, content: Content): Notification {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, content.channelName, NotificationManager.IMPORTANCE_LOW),
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            return builder
                .setSmallIcon(R.mipmap.ic_launcher_monochrome)
                .setContentTitle(content.title)
                .setContentText(content.text)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setProgress(1000, content.permille.coerceIn(0, 1000), content.permille < 0)
                .build()
        }
    }
}
