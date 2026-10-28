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
 * Keeps the process in the foreground while files are transcribed or a model is
 * downloaded and the app is not on screen, so Android neither freezes nor kills
 * it, and holds a partial wake lock so the CPU keeps working with the screen off.
 * The work itself still runs in the app; this service only shows progress.
 *
 * Started as the activity stops (the last moment Android 12+ allows it) and
 * stopped when it is visible again; progress updates only re-post the notification.
 */
class TranscriptionService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val content = Content.fromIntent(intent)
        val notification = buildNotification(this, content)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, foregroundType(content.kinds))
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

    // Android 15 limits media-processing and data-sync services to 6 hours a day.
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    /**
     * What the notification says; [permille] < 0 shows an indeterminate bar.
     * [publicTitle] replaces [title] on a lock screen that hides sensitive content.
     * [kinds] names the running work ("transcription", "download").
     */
    data class Content(
        val channelName: String,
        val title: String,
        val publicTitle: String,
        val text: String,
        val permille: Int,
        val kinds: List<String>,
    ) {
        fun toIntent(context: Context): Intent = Intent(context, TranscriptionService::class.java)
            .putExtra(EXTRA_CHANNEL, channelName)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_PUBLIC_TITLE, publicTitle)
            .putExtra(EXTRA_TEXT, text)
            .putExtra(EXTRA_PERMILLE, permille)
            .putExtra(EXTRA_KINDS, kinds.toTypedArray())

        companion object {
            fun fromIntent(intent: Intent?) = Content(
                channelName = intent?.getStringExtra(EXTRA_CHANNEL) ?: "Transcription",
                title = intent?.getStringExtra(EXTRA_TITLE) ?: "Extracter",
                publicTitle = intent?.getStringExtra(EXTRA_PUBLIC_TITLE) ?: "Extracter",
                text = intent?.getStringExtra(EXTRA_TEXT) ?: "",
                permille = intent?.getIntExtra(EXTRA_PERMILLE, -1) ?: -1,
                kinds = intent?.getStringArrayExtra(EXTRA_KINDS)?.toList() ?: emptyList(),
            )
        }
    }

    companion object {
        const val NOTIFICATION_ID = 1001
        /** High importance, so the notification pops down and keeps a status-bar icon. */
        private const val CHANNEL_ID = "background_work"

        /** The first, low-importance channel; importance can't be raised, so it is replaced. */
        private const val OLD_CHANNEL_ID = "transcription"
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000
        private const val EXTRA_CHANNEL = "channel"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_PUBLIC_TITLE = "publicTitle"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PERMILLE = "permille"
        private const val EXTRA_KINDS = "kinds"

        /** Transcription is media processing (Android 15+); a model download is data sync. */
        private fun foregroundType(kinds: List<String>): Int {
            val mediaProcessing = Build.VERSION.SDK_INT >= 35 && "transcription" in kinds
            val dataSync = "download" in kinds || !mediaProcessing
            var type = 0
            if (mediaProcessing) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            if (dataSync) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            return type
        }

        fun buildNotification(context: Context, content: Content): Notification {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.deleteNotificationChannel(OLD_CHANNEL_ID)
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, content.channelName, NotificationManager.IMPORTANCE_HIGH).apply {
                        // Pops down without a sound or vibration; it only reports progress.
                        setSound(null, null)
                        enableVibration(false)
                    },
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            // Without a file name, for a lock screen that hides sensitive content.
            val lockScreen = progressBuilder(context, content, open).setContentTitle(content.publicTitle).build()
            return progressBuilder(context, content, open)
                .setContentTitle(content.title)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(lockScreen)
                .build()
        }

        // Notification.Builder(context) and setPriority are the pre-Android 8 path.
        @Suppress("DEPRECATION")
        private fun progressBuilder(context: Context, content: Content, open: PendingIntent): Notification.Builder {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }
            // The user has just left the app: show progress now, not after Android's 10-second delay.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return builder
                .setSmallIcon(R.mipmap.ic_launcher_monochrome)
                .setContentText(content.text)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setPriority(Notification.PRIORITY_HIGH)
                .setProgress(1000, content.permille.coerceIn(0, 1000), content.permille < 0)
        }
    }
}
