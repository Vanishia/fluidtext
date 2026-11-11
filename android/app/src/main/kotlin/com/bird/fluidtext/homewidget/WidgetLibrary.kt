package com.bird.fluidtext.homewidget

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import java.io.Closeable
import java.io.File
import java.security.MessageDigest
import kotlin.random.Random

internal data class WidgetConfig(
    val allBooks: Boolean = true,
    val bookIds: Set<Long> = emptySet(),
    val favoritesOnly: Boolean = false,
    val unreadOnly: Boolean = false,
    val intervalMinutes: Int = 60,
) {
    companion object {
        val intervals = listOf(0, 30, 60, 360, 1440)
    }
}

internal data class WidgetBook(val id: Long, val title: String)

internal data class WidgetCard(
    val id: Long,
    val bookId: Long,
    val title: String,
    val content: String,
) {
    val contentHash: String
        get() = MessageDigest.getInstance("SHA-256")
            .digest(content.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}

/** Only reads normal tables; never runs Drift migrations or touches FTS. */
internal class WidgetLibrary(context: Context) : Closeable {
    private val database: SQLiteDatabase

    init {
        val path = WidgetStore(context).databasePath
        check(path != null && File(path).isFile) { "请先打开 FluidText 并导入书籍" }
        database = SQLiteDatabase.openDatabase(
            path, null,
            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS,
        )
        // The native reader deliberately supports only known library schemas.
        if (database.version !in 1..2) {
            database.close()
            error("请先打开 FluidText 完成书库升级")
        }
    }

    fun books(): List<WidgetBook> = database.rawQuery(
        """SELECT b.id, COALESCE(NULLIF(r.title, ''), b.title)
           FROM books b LEFT JOIN book_remarks r ON r.book_id = b.id
           ORDER BY b.created_at_ms DESC, b.id DESC""", null,
    ).use { cursor ->
        buildList { while (cursor.moveToNext()) add(WidgetBook(cursor.getLong(0), cursor.getString(1))) }
    }

    fun choose(config: WidgetConfig, previousId: Long?, rotate: Boolean): WidgetCard? {
        val clauses = mutableListOf(
            "length(trim(c.content, ' ' || char(9) || char(10) || char(13) || char(160) || char(12288))) > 0",
        )
        val args = mutableListOf<String>()
        if (!config.allBooks) {
            if (config.bookIds.isEmpty()) return null
            clauses.add("c.book_id IN (${config.bookIds.joinToString(",") { "?" }})")
            args.addAll(config.bookIds.map { it.toString() })
        }
        if (config.favoritesOnly) clauses.add("c.is_favorite = 1")
        if (config.unreadOnly) clauses.add("c.is_read = 0")
        val where = clauses.joinToString(" AND ")
        val current = previousId?.let { id ->
            queryCard("$where AND c.id = ?", args + id.toString())
        }
        if (!rotate && current != null) return current

        // Choose an offset among IDs, so large card bodies aren't shuffled in memory.
        val exclude = current != null
        val randomWhere = where + if (exclude) " AND c.id != ?" else ""
        val randomArgs = args + if (exclude) listOf(current!!.id.toString()) else emptyList()
        val count = database.rawQuery(
            "SELECT count(*) FROM book_cards c WHERE $randomWhere", randomArgs.toTypedArray(),
        ).use { it.moveToFirst(); it.getLong(0) }
        if (count == 0L) return current
        return queryCard(randomWhere, randomArgs, Random.nextLong(count))
            // A foreground delete may occur between the count and the selection.
            ?: queryCard(where, args)
    }

    private fun queryCard(where: String, args: List<String>, offset: Long = 0): WidgetCard? =
        database.rawQuery(
            """SELECT c.id, c.book_id, COALESCE(NULLIF(r.title, ''), b.title), c.content
               FROM book_cards c JOIN books b ON b.id = c.book_id
               LEFT JOIN book_remarks r ON r.book_id = b.id
               WHERE $where ORDER BY c.id LIMIT 1 OFFSET ?""",
            (args + offset.toString()).toTypedArray(),
        ).use { if (it.moveToFirst()) it.card() else null }

    private fun Cursor.card() = WidgetCard(getLong(0), getLong(1), getString(2), getString(3))

    override fun close() = database.close()
}

internal class WidgetStore(context: Context) {
    private val preferences = context.getSharedPreferences("random_card_widgets", Context.MODE_PRIVATE)

    var databasePath: String?
        get() = preferences.getString("database_path", null)
        set(value) { preferences.edit().putString("database_path", value).apply() }

    fun config(id: Int): WidgetConfig = WidgetConfig(
        allBooks = preferences.getBoolean("${id}_all_books", true),
        bookIds = preferences.getStringSet("${id}_book_ids", emptySet())!!
            .mapNotNull { it.toLongOrNull() }.toSet(),
        favoritesOnly = preferences.getBoolean("${id}_favorites", false),
        unreadOnly = preferences.getBoolean("${id}_unread", false),
        intervalMinutes = preferences.getInt("${id}_interval", 60)
            .takeIf { it in WidgetConfig.intervals } ?: 60,
    )

    fun saveConfig(id: Int, config: WidgetConfig) {
        preferences.edit()
            .putBoolean("${id}_all_books", config.allBooks)
            .putStringSet("${id}_book_ids", config.bookIds.map { it.toString() }.toSet())
            .putBoolean("${id}_favorites", config.favoritesOnly)
            .putBoolean("${id}_unread", config.unreadOnly)
            .putInt("${id}_interval", config.intervalMinutes)
            .apply()
    }

    fun currentId(id: Int): Long? = preferences.getLong("${id}_card_id", 0).takeIf { it > 0 }
    fun lastUpdate(id: Int): Long = preferences.getLong("${id}_updated_at", 0)

    fun remember(id: Int, card: WidgetCard?, rotated: Boolean) {
        val edit = preferences.edit().putLong("${id}_card_id", card?.id ?: 0)
        if (rotated) edit.putLong("${id}_updated_at", System.currentTimeMillis())
        edit.apply()
    }

    fun delete(id: Int) {
        val edit = preferences.edit()
        for (key in preferences.all.keys) if (key.startsWith("${id}_")) edit.remove(key)
        edit.apply()
    }
}
