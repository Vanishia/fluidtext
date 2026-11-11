package com.bird.fluidtext.homewidget

import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PersistableBundle
import android.util.Log
import android.widget.RemoteViews
import com.bird.fluidtext.MainActivity
import com.bird.fluidtext.R
import java.util.concurrent.Executors

class RandomCardWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        executor.execute {
            try {
                for (id in ids) {
                    schedule(context, id)
                    update(context, id)
                }
            } finally { pending.finish() }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH || intent.action == ACTION_SYNC ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val ids = if (intent.action == ACTION_REFRESH) {
                intArrayOf(intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))
            } else widgetIds(context)
            val pending = goAsync()
            executor.execute {
                try {
                    if (intent.action == ACTION_SYNC) {
                        intent.getStringExtra(EXTRA_DATABASE_PATH)?.let {
                            WidgetStore(context).databasePath = it
                        }
                    }
                    for (id in ids) if (ownsWidget(context, id)) {
                        schedule(context, id)
                        update(context, id, rotate = intent.action == ACTION_REFRESH)
                    }
                } finally { pending.finish() }
            }
        } else super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) {
            scheduler(context).cancel(jobId(id))
            WidgetStore(context).delete(id)
        }
    }

    override fun onRestored(context: Context, oldIds: IntArray, newIds: IntArray) {
        val store = WidgetStore(context)
        // Old/new IDs may overlap, including a widget retaining its ID.
        val configs = oldIds.map { store.config(it) }
        for (id in oldIds) {
            store.delete(id)
            scheduler(context).cancel(jobId(id))
        }
        newIds.forEachIndexed { index, id -> store.saveConfig(id, configs[index]) }
        // AppWidgetProvider dispatches onUpdate(newIds) after onRestored returns.
    }

    companion object {
        private const val ACTION_REFRESH = "com.bird.fluidtext.widget.REFRESH"
        private const val ACTION_SYNC = "com.bird.fluidtext.widget.SYNC"
        private const val EXTRA_DATABASE_PATH = "databasePath"
        const val ACTION_OPEN_CARD = "com.bird.fluidtext.widget.OPEN_CARD"
        internal val executor = Executors.newSingleThreadExecutor()

        internal fun widgetIds(context: Context): IntArray = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, RandomCardWidgetProvider::class.java))

        internal fun ownsWidget(context: Context, id: Int): Boolean =
            AppWidgetManager.getInstance(context).getAppWidgetInfo(id)?.provider ==
                ComponentName(context, RandomCardWidgetProvider::class.java)

        internal fun requestRefresh(context: Context, databasePath: String? = null) {
            // Platform SQLite must not share a process with Flutter's bundled SQLite:
            // their independent WAL/lock state can invalidate each other's mappings.
            // The receiver also owns all widget preferences, avoiding cross-process caches.
            context.sendBroadcast(Intent(context, RandomCardWidgetProvider::class.java).apply {
                action = ACTION_SYNC
                if (databasePath != null) putExtra(EXTRA_DATABASE_PATH, databasePath)
            })
        }

        internal fun update(context: Context, id: Int, rotate: Boolean = false) {
            if (!ownsWidget(context, id)) return
            val store = WidgetStore(context)
            val config = store.config(id)
            val previous = store.currentId(id)
            val due = config.intervalMinutes > 0 &&
                System.currentTimeMillis() - store.lastUpdate(id) >= config.intervalMinutes * 60_000L
            var message = "范围内暂无文字卡片，请调整选书或筛选条件"
            val card = try {
                WidgetLibrary(context).use { it.choose(config, previous, rotate || due) }
            } catch (error: Exception) {
                Log.w("FluidTextWidget", "Cannot read widget library", error)
                message = "请打开 FluidText 初始化书库，再点换一张"
                null
            }
            store.remember(id, card, rotate || due || previous != card?.id)
            val views = RemoteViews(context.packageName, R.layout.random_card_widget)
            views.setTextViewText(
                R.id.widget_content,
                card?.content?.replace(Regex("\\s+"), " ")?.trim() ?: message,
            )
            views.setTextViewText(R.id.widget_book_title, card?.title ?: "FluidText")

            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                action = ACTION_OPEN_CARD
                // Identity belongs to the rendered card, including for a click racing a refresh.
                data = Uri.parse("fluidtext-widget://card/$id/${card?.id ?: 0}/${card?.contentHash ?: "empty"}")
                if (card != null) {
                    putExtra("cardId", card.id)
                    putExtra("bookId", card.bookId)
                    putExtra("contentHash", card.contentHash)
                }
            }
            val openPending = PendingIntent.getActivity(
                context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openPending)
            views.setOnClickPendingIntent(R.id.widget_content, openPending)
            views.setOnClickPendingIntent(R.id.widget_book_title, openPending)
            views.setOnClickPendingIntent(
                R.id.widget_refresh,
                PendingIntent.getBroadcast(
                    context, id,
                    Intent(context, RandomCardWidgetProvider::class.java).apply {
                        action = ACTION_REFRESH
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_settings,
                PendingIntent.getActivity(
                    context, id,
                    Intent(context, RandomCardWidgetSettingsActivity::class.java)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            AppWidgetManager.getInstance(context).updateAppWidget(id, views)
        }

        private fun scheduler(context: Context) = context.getSystemService(JobScheduler::class.java)
        private fun jobId(id: Int) = 0x46540000 xor id

        internal fun schedule(context: Context, id: Int) {
            val scheduler = scheduler(context)
            val interval = WidgetStore(context).config(id).intervalMinutes * 60_000L
            if (interval == 0L) {
                scheduler.cancel(jobId(id))
                return
            }
            // Keep the original schedule when merely returning to the app.
            if (scheduler.allPendingJobs.any { it.id == jobId(id) && it.intervalMillis == interval }) return
            scheduler.schedule(
                JobInfo.Builder(jobId(id), ComponentName(context, RandomCardWidgetJob::class.java))
                    .setPeriodic(interval)
                    .setPersisted(true)
                    .setExtras(PersistableBundle().apply { putInt("widgetId", id) })
                    .build(),
            )
        }
    }
}

/** System-managed periodic work; Flutter and the main activity can be stopped. */
class RandomCardWidgetJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        val id = params.extras.getInt("widgetId", -1)
        RandomCardWidgetProvider.executor.execute {
            try { RandomCardWidgetProvider.update(this, id, rotate = true) }
            finally { jobFinished(params, false) }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
