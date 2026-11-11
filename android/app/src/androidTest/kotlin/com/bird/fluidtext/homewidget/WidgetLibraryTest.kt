package com.bird.fluidtext.homewidget

import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/** Run against the device's SQLite implementation, independently of Flutter. */
class WidgetLibraryTest {
    private lateinit var file: File
    private var previousPath: String? = null
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before fun setUp() {
        previousPath = WidgetStore(context).databasePath
        file = File(context.cacheDir, "widget-library-test.sqlite")
        SQLiteDatabase.deleteDatabase(file)
        SQLiteDatabase.openOrCreateDatabase(file, null).use { database ->
            database.version = 2
            database.execSQL("CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT, created_at_ms INTEGER)")
            database.execSQL("CREATE TABLE book_remarks (book_id INTEGER PRIMARY KEY, title TEXT)")
            database.execSQL("""CREATE TABLE book_cards (
                id INTEGER PRIMARY KEY, book_id INTEGER, content TEXT,
                is_favorite INTEGER, is_read INTEGER)""")
            database.execSQL("INSERT INTO books VALUES (1, 'First book', 1), (2, 'Second book', 2)")
            database.execSQL("INSERT INTO book_remarks VALUES (2, 'Book remark')")
            database.execSQL("""INSERT INTO book_cards VALUES
                (11, 1, 'Unread first', 0, 0), (12, 1, 'Read favorite', 1, 1),
                (21, 2, 'Unread favorite', 1, 0), (22, 2, 'Other unread', 0, 0),
                (23, 2, '   ', 1, 0), (24, 2, char(10) || char(9) || char(12288), 1, 0)""")
        }
        WidgetStore(context).databasePath = file.path
    }

    @After fun tearDown() {
        WidgetStore(context).databasePath = previousPath
        SQLiteDatabase.deleteDatabase(file)
    }

    @Test fun filtersIntersectAndSkipBlankCards() {
        WidgetLibrary(context).use { library ->
            val config = WidgetConfig(
                allBooks = false, bookIds = setOf(2), favoritesOnly = true, unreadOnly = true,
            )
            val card = library.choose(config, null, true)!!
            assertEquals(21L, card.id)
            assertEquals("Book remark", card.title)
            assertEquals(64, card.contentHash.length)
        }
    }

    @Test fun manualRefreshAvoidsImmediateRepeatAndPassiveRefreshKeepsCard() {
        WidgetLibrary(context).use { library ->
            val config = WidgetConfig(allBooks = false, bookIds = setOf(1))
            assertEquals(11L, library.choose(config, 11, false)!!.id)
            assertEquals(12L, library.choose(config, 11, true)!!.id)
            assertEquals(11L, library.choose(config, 12, true)!!.id)
        }
    }

    @Test fun oneEligibleCardStaysVisibleAndEmptySelectionNeverMeansAllBooks() {
        WidgetLibrary(context).use { library ->
            val config = WidgetConfig(allBooks = false, bookIds = setOf(1), unreadOnly = true)
            assertEquals(11L, library.choose(config, 11, true)!!.id)
            assertNull(library.choose(WidgetConfig(allBooks = false), null, true))
            assertNull(library.choose(config.copy(bookIds = setOf(999)), null, true))
        }
    }

    @Test fun deletedCardIsReplacedAndWidgetReadsNeverMarkAsRead() {
        SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE).use {
            it.execSQL("DELETE FROM book_cards WHERE id = 11")
        }
        WidgetLibrary(context).use { library ->
            val config = WidgetConfig(allBooks = false, bookIds = setOf(1))
            assertEquals(12L, library.choose(config, 11, false)!!.id)
            val unread = WidgetConfig(unreadOnly = true)
            repeat(5) { library.choose(unread, null, true) }
        }
        SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use {
            it.rawQuery("SELECT count(*) FROM book_cards WHERE is_read = 1", null).use { cursor ->
                cursor.moveToFirst()
                assertEquals(1, cursor.getInt(0))
            }
        }
    }

    @Test fun differentInstancesKeepIndependentSettings() {
        val store = WidgetStore(context)
        val firstId = 1000001
        val secondId = 1000002
        try {
            val first = WidgetConfig(allBooks = false, bookIds = setOf(1), intervalMinutes = 0)
            val second = WidgetConfig(favoritesOnly = true, intervalMinutes = 360)
            store.saveConfig(firstId, first)
            store.saveConfig(secondId, second)
            assertEquals(first, store.config(firstId))
            assertEquals(second, store.config(secondId))
            store.delete(firstId)
            assertEquals(second, store.config(secondId))
        } finally {
            store.delete(firstId)
            store.delete(secondId)
        }
    }

    @Test fun restorePreservesSettingsWhenOldAndNewIdsOverlap() {
        val store = WidgetStore(context)
        val firstId = 1000001
        val secondId = 1000002
        val thirdId = 1000003
        try {
            val first = WidgetConfig(allBooks = false, bookIds = setOf(1), intervalMinutes = 0)
            val second = WidgetConfig(favoritesOnly = true, intervalMinutes = 360)
            store.saveConfig(firstId, first)
            store.saveConfig(secondId, second)
            val provider = RandomCardWidgetProvider()
            provider.onRestored(context, intArrayOf(firstId, secondId), intArrayOf(secondId, thirdId))
            assertEquals(first, store.config(secondId))
            assertEquals(second, store.config(thirdId))
            provider.onRestored(context, intArrayOf(secondId), intArrayOf(secondId))
            assertEquals(first, store.config(secondId))
        } finally {
            for (id in listOf(firstId, secondId, thirdId)) store.delete(id)
        }
    }
}
