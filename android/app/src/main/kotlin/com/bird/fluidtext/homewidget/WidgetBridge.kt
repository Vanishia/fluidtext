package com.bird.fluidtext.homewidget

import android.app.PendingIntent
import android.app.ActivityOptions
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class WidgetBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "fluidtext/home_widget")
    private var pendingCard: Map<String, Any>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingCard" -> {
                    result.success(pendingCard)
                    pendingCard = null
                }
                "initialize" -> {
                    val path = call.argument<String>("databasePath")
                    // Only accept a database inside this application's own private directory.
                    val root = File(context.applicationInfo.dataDir).canonicalFile
                    val database = path?.let { File(it).canonicalFile }
                    if (database == null || !database.path.startsWith(root.path + File.separator) || !database.isFile) {
                        result.error("invalid_database", "Library database is unavailable", null)
                    } else {
                        RandomCardWidgetProvider.requestRefresh(context, database.path)
                        result.success(null)
                    }
                }
                "refresh" -> { refresh(); result.success(null) }
                "requestPin" -> {
                    val manager = AppWidgetManager.getInstance(context)
                    val supported = Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported
                    val options = if (Build.VERSION.SDK_INT >= 35) {
                        ActivityOptions.makeBasic().apply {
                            @Suppress("DEPRECATION")
                            setPendingIntentCreatorBackgroundActivityStartMode(
                                if (Build.VERSION.SDK_INT >= 36)
                                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_IF_VISIBLE
                                else ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                            )
                        }.toBundle()
                    } else null
                    result.success(supported && manager.requestPinAppWidget(
                        ComponentName(context, RandomCardWidgetProvider::class.java), null,
                        // Pin requests skip the provider's configure activity. The launcher
                        // supplies the allocated widget ID to this explicit callback instead.
                        PendingIntent.getActivity(
                            context, 0,
                            Intent(context, RandomCardWidgetSettingsActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE or
                                PendingIntent.FLAG_ONE_SHOT,
                            options,
                        ),
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleIntent(intent: Intent) {
        if (intent.action != RandomCardWidgetProvider.ACTION_OPEN_CARD) return
        val id = intent.getLongExtra("cardId", 0)
        val bookId = intent.getLongExtra("bookId", 0)
        val hash = intent.getStringExtra("contentHash")
        // Consume the intent once; recreation must not reopen the same sheet.
        intent.action = null
        if (id <= 0 || bookId <= 0 || hash == null) return
        pendingCard = mapOf("cardId" to id, "bookId" to bookId, "contentHash" to hash)
        channel.invokeMethod("cardAvailable", null)
    }

    fun refresh() = RandomCardWidgetProvider.requestRefresh(context)
}
