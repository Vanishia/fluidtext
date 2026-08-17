package com.bird.fluidtext

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

/**
 * Foreground service that keeps the process alive while the one-shot Isar →
 * SQLite data migration (or the pre-migration ZIP backup export) runs, so
 * the system does not kill the app under memory pressure when the user
 * switches away mid-migration.
 *
 * Unlike the EPUB import notification this is a real foreground service:
 * migration moves the whole user library and being killed forces a full
 * retry from the staging copies. The migration state machine keeps a kill
 * safe either way; this service just makes it unlikely.
 *
 * START_NOT_STICKY on purpose: if the process died the migration must be
 * recovered through the bootstrap state machine, not a zombie notification.
 */
class MigrationForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "data_migration"
        const val NOTIFICATION_ID = 4202
        const val ACTION_START = "com.bird.fluidtext.migration.START"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PERCENT = "percent"

        /**
         * Live instance used by MainActivity to update/stop the notification
         * without re-starting the service (starting services is restricted
         * while the app is in the background, exactly when updates matter).
         */
        @Volatile
        private var instance: MigrationForegroundService? = null

        /** Starts (or promotes) the foreground service from the activity. */
        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, MigrationForegroundService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                @Suppress("DEPRECATION")
                context.startService(intent)
            }
        }

        /** Updates the notification text/progress; no-op when not running. */
        fun update(context: Context, title: String, text: String, percent: Int) {
            instance?.postNotification(title, text, percent, ongoing = true)
        }

        /** Stops the service and removes its notification; always safe. */
        fun stop(context: Context) {
            val service = instance
            if (service != null) {
                @Suppress("DEPRECATION")
                service.stopForeground(true)
                service.stopSelf()
            } else {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE)
                        as NotificationManager
                manager.cancel(NOTIFICATION_ID)
            }
        }
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "正在迁移数据"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val percent = intent?.getIntExtra(EXTRA_PERCENT, -1) ?: -1
        val notification = buildNotification(title, text, percent, ongoing = true)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    /** Re-posts the ongoing notification with new text and progress. */
    fun postNotification(title: String, text: String, percent: Int, ongoing: Boolean) {
        notificationManager().notify(
            NOTIFICATION_ID,
            buildNotification(title, text, percent, ongoing),
        )
    }

    private fun buildNotification(
        title: String,
        text: String,
        percent: Int,
        ongoing: Boolean,
    ): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            notificationManager().createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "数据迁移",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val launchIntent = Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            1,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder =
            if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setAutoCancel(!ongoing)
        if (ongoing) {
            if (percent in 0..100) {
                builder.setProgress(100, percent, false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }
        return builder.build()
    }
}
