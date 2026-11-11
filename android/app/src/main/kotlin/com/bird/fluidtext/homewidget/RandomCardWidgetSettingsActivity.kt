package com.bird.fluidtext.homewidget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.ArrayAdapter
import android.widget.TextView
import com.bird.fluidtext.MainActivity
import com.bird.fluidtext.R

/** Each launcher instance has its own selection and schedule. No Flutter engine needed. */
class RandomCardWidgetSettingsActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var container: LinearLayout
    private var configuration: WidgetConfig? = null
    private var loading = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setResult(RESULT_CANCELED)
        widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (!RandomCardWidgetProvider.ownsWidget(this, widgetId)) {
            finish()
            return
        }
        val scroll = ScrollView(this)
        container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        scroll.addView(container)
        setContentView(scroll)
    }

    override fun onResume() {
        super.onResume()
        if (configuration == null && !loading) loadBooks()
    }

    private fun text(value: String, size: Float = 15f): TextView = TextView(this).apply {
        text = value
        textSize = size
        setPadding(0, 12, 0, 12)
    }

    private fun loadBooks() {
        loading = true
        container.removeAllViews()
        container.addView(text("正在读取书库…"))
        RandomCardWidgetProvider.executor.execute {
            val result = runCatching { WidgetLibrary(this).use { it.books() } }
            runOnUiThread {
                loading = false
                if (isFinishing || isDestroyed) return@runOnUiThread
                result.fold(
                    onSuccess = { showSettings(it) },
                    onFailure = {
                        container.removeAllViews()
                        container.addView(text("先准备好书库", 24f))
                        container.addView(text("请打开 FluidText 完成初始化或书库升级，返回后即可设置小组件。"))
                        container.addView(Button(this).apply {
                            setText(R.string.widget_open_app)
                            setOnClickListener { startActivity(Intent(this@RandomCardWidgetSettingsActivity, MainActivity::class.java)) }
                        })
                        container.addView(Button(this).apply {
                            text = "重新读取"
                            setOnClickListener { loadBooks() }
                        })
                    },
                )
            }
        }
    }

    private fun showSettings(books: List<WidgetBook>) {
        val config = WidgetStore(this).config(widgetId)
        configuration = config
        container.removeAllViews()
        container.addView(text("桌面随机卡片", 25f))
        container.addView(text("展示最多三行正文，点击卡片查看完整内容和上下文。"))
        container.addView(text("选取范围", 18f))
        val all = CheckBox(this).apply { text = "全部书籍"; isChecked = config.allBooks }
        container.addView(all)
        val bookViews = books.map { book ->
            book.id to CheckBox(this).apply {
                text = book.title
                isChecked = book.id in config.bookIds
                isEnabled = !all.isChecked
                container.addView(this)
            }
        }
        all.setOnCheckedChangeListener { _, checked ->
            bookViews.forEach { (_, view) -> view.isEnabled = !checked }
        }
        if (books.isEmpty()) container.addView(text("书库还没有书籍，可以先保存，导入后再换一张。"))
        val favorites = CheckBox(this).apply {
            text = "仅收藏卡片"; isChecked = config.favoritesOnly
        }
        val unread = CheckBox(this).apply {
            text = "仅未读卡片"; isChecked = config.unreadOnly
        }
        container.addView(favorites)
        container.addView(unread)
        container.addView(text("自动换卡", 18f))
        val frequency = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@RandomCardWidgetSettingsActivity,
                android.R.layout.simple_spinner_dropdown_item,
                listOf("仅手动", "约每半小时", "约每小时", "约每六小时", "约每天"),
            )
            setSelection(WidgetConfig.intervals.indexOf(config.intervalMinutes))
        }
        container.addView(frequency)
        container.addView(text("系统省电或休眠时更新可能延后。桌面上的换一张按钮可随时手动更新；展示卡片不会标记已读。"))
        val error = text("").apply { visibility = View.GONE }
        container.addView(error)
        container.addView(Button(this).apply {
            text = "保存"
            setOnClickListener {
                val selected = bookViews.filter { it.second.isChecked }.map { it.first }.toSet()
                if (!all.isChecked && selected.isEmpty()) {
                    error.text = "请至少选择一本书，或启用全部书籍。"
                    error.visibility = View.VISIBLE
                    return@setOnClickListener
                }
                isEnabled = false
                val next = WidgetConfig(
                    all.isChecked, selected, favorites.isChecked, unread.isChecked,
                    WidgetConfig.intervals[frequency.selectedItemPosition],
                )
                RandomCardWidgetProvider.executor.execute {
                    WidgetStore(this@RandomCardWidgetSettingsActivity).saveConfig(widgetId, next)
                    RandomCardWidgetProvider.schedule(this@RandomCardWidgetSettingsActivity, widgetId)
                    RandomCardWidgetProvider.update(this@RandomCardWidgetSettingsActivity, widgetId, rotate = true)
                    runOnUiThread {
                        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                        finish()
                    }
                }
            }
        })
    }
}
