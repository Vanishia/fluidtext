package com.bird.fluidtext

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Posts the persistent "importing" notification so an in-flight EPUB import
 * stays visible (and the process slightly harder to kill) while the user
 * switches apps. Deliberately not a foreground service: imports are fast and
 * the app cleans up half-imported books on next launch.
 *
 * The same channel also drives the one-shot "creating search index"
 * notification (id 4202, shown during the FTS backfill after an upgrade).
 *
 * The separate migration channel drives [MigrationForegroundService], which
 * is a real foreground service because a killed migration forces a full
 * retry of the one-shot data migration.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "fluidtext/import_notifications"
        private const val MIGRATION_CHANNEL_NAME = "fluidtext/migration_service"
        private const val NOTIFICATION_CHANNEL_ID = "book_import"
        private const val SEARCH_INDEX_CHANNEL_ID = "search_index"
        private const val IMPORT_NOTIFICATION_ID = 4201
        private const val SEARCH_INDEX_NOTIFICATION_ID = 4202
        private const val PERMISSION_REQUEST_CODE = 7101
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                val notificationId =
                    call.argument<Int>("id") ?: IMPORT_NOTIFICATION_ID
                when (call.method) {
                    "ensurePermission" -> ensureNotificationPermission(result)
                    "showProgress" -> {
                        val title = call.argument<String>("title") ?: "正在导入"
                        val text = call.argument<String>("text") ?: ""
                        val percent = call.argument<Int>("percent") ?: -1
                        showNotification(title, text, percent, ongoing = true, notificationId)
                        result.success(null)
                    }
                    "showCompleted" -> {
                        val text = call.argument<String>("text") ?: "已完成"
                        val title =
                            if (notificationId == SEARCH_INDEX_NOTIFICATION_ID) "搜索索引"
                            else "导入已完成"
                        showNotification(title, text, percent = -1, ongoing = false, notificationId)
                        result.success(null)
                    }
                    "cancel" -> {
                        notificationManager().cancel(notificationId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIGRATION_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermission" -> ensureNotificationPermission(result)
                    "start" -> {
                        val title = call.argument<String>("title") ?: "正在迁移数据"
                        val text = call.argument<String>("text") ?: ""
                        MigrationForegroundService.start(this, title, text)
                        result.success(null)
                    }
                    "update" -> {
                        val title = call.argument<String>("title") ?: "正在迁移数据"
                        val text = call.argument<String>("text") ?: ""
                        val percent = call.argument<Int>("percent") ?: -1
                        MigrationForegroundService.update(this, title, text, percent)
                        result.success(null)
                    }
                    "stop" -> {
                        MigrationForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(true)
            return
        }
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun showNotification(
        title: String,
        text: String,
        percent: Int,
        ongoing: Boolean,
        notificationId: Int,
    ) {
        val manager = notificationManager()
        val channelId =
            if (notificationId == SEARCH_INDEX_NOTIFICATION_ID) SEARCH_INDEX_CHANNEL_ID
            else NOTIFICATION_CHANNEL_ID
        if (Build.VERSION.SDK_INT >= 26) {
            val channelLabel =
                if (notificationId == SEARCH_INDEX_NOTIFICATION_ID) "搜索索引" else "书籍导入"
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    channelLabel,
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val launchIntent = Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder =
            if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, channelId)
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
        manager.notify(notificationId, builder.build())
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
