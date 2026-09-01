import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Runtime configuration and query-plan guarantees for the production
/// (file-based) database. The SQL statements mirror the queries in
/// `SqliteLibraryRepository`; keep them in sync when those queries change.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory directory;
  late File databaseFile;
  late LibraryDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fluidtext-db-test-');
    databaseFile = File(
      '${directory.path}${Platform.pathSeparator}library.sqlite',
    );
    database = LibraryDatabase.file(databaseFile);
    // Force the database open before asserting PRAGMAs.
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await database.close();
    for (var attempt = 0; attempt < 5; attempt += 1) {
      if (!await directory.exists()) return;
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  Future<int> intPragma(String name) async {
    final row = await database.customSelect('PRAGMA $name').getSingle();
    return row.data.values.single as int;
  }

  test('applies the conservative PRAGMA configuration', () async {
    final journalMode = await database
        .customSelect('PRAGMA journal_mode')
        .getSingle();
    expect(journalMode.data.values.single, 'wal');
    expect(await intPragma('foreign_keys'), 1);
    expect(await intPragma('busy_timeout'), 5000);
    // Plan §4.3 conservative default: FULL (2), not NORMAL (1).
    expect(await intPragma('synchronous'), 2);
  });

  Future<String> planOf(String sql, [List<Object?> args = const []]) async {
    final rows = await database.explainQueryPlan(sql, args);
    return rows.map((row) => row.data.values.join(' ')).join('\n');
  }

  test('unread card ordering uses the unread index', () async {
    final plan = await planOf(
      'SELECT book_id, id FROM book_cards '
      'WHERE book_id IN (?) AND is_read = 0 '
      'ORDER BY book_id ASC, card_index ASC',
      [1],
    );
    expect(plan, contains('idx_book_cards_unread_order'));
    expect(plan, isNot(contains('SCAN book_cards')));
  });

  test('read activity list uses the read activity index', () async {
    final plan = await planOf(
      'SELECT id, book_id, card_index, read_at_ms AS timestamp_ms '
      'FROM book_cards '
      'WHERE is_read = 1 AND read_at_ms IS NOT NULL '
      'ORDER BY read_at_ms DESC, id DESC',
    );
    expect(plan, contains('idx_book_cards_read_activity'));
    expect(plan, isNot(contains('SCAN book_cards')));
  });

  test('favorite activity list uses the favorite activity index', () async {
    final plan = await planOf(
      'SELECT id, book_id, card_index, favorited_at_ms AS timestamp_ms '
      'FROM book_cards '
      'WHERE is_favorite = 1 AND favorited_at_ms IS NOT NULL '
      'ORDER BY favorited_at_ms DESC, id DESC',
    );
    expect(plan, contains('idx_book_cards_favorite_activity'));
    expect(plan, isNot(contains('SCAN book_cards')));
  });

  test('context card range lookup uses a book order index', () async {
    final plan = await planOf(
      'SELECT * FROM book_cards '
      'WHERE book_id = ? AND card_index >= ? AND card_index <= ? '
      'ORDER BY card_index ASC',
      [1, 10, 20],
    );
    expect(plan, contains('SEARCH book_cards USING'));
    expect(plan, isNot(contains('SCAN book_cards')));
  });

  test('duplicate detection uses the identity indexes', () async {
    final byHash = await planOf(
      'SELECT * FROM books WHERE file_hash = ?',
      ['hash'],
    );
    expect(byHash, contains('idx_books_file_hash'));

    final byFingerprint = await planOf(
      'SELECT * FROM books WHERE content_fingerprint = ?',
      ['fingerprint'],
    );
    expect(byFingerprint, contains('idx_books_content_fingerprint'));
  });

  test('book stats aggregation uses a book_cards index', () async {
    final plan = await planOf(
      'SELECT book_id, COUNT(*) FROM book_cards '
      'WHERE book_id IN (?) GROUP BY book_id',
      [1],
    );
    expect(plan, contains('idx_book_cards'));
    expect(plan, isNot(contains('SCAN book_cards')));
  });

  group('full-text search (schema v2)', () {
    Future<List<int>> ftsMatch(String query) async {
      final rows = await database
          .customSelect(
            'SELECT rowid FROM book_cards_fts WHERE book_cards_fts MATCH ?',
            variables: [Variable(query)],
          )
          .get();
      return rows.map((row) => row.read<int>('rowid')).toList();
    }

    Future<void> insertCard(int id, String content) async {
      await database.customStatement(
        'INSERT INTO books(id, title, created_at_ms) VALUES (?, ?, 0)',
        [id, '书$id'],
      );
      await database.customStatement(
        'INSERT INTO book_cards(id, book_id, book_title, card_index, '
        'chapter_index, chapter_card_index, content, is_read, is_favorite) '
        'VALUES (?, ?, ?, 0, 0, 0, ?, 0, 0)',
        [id, id, '书$id', content],
      );
    }

    test('creates the FTS virtual table and sync triggers on open', () async {
      final rows = await database
          .customSelect(
            "SELECT name, type FROM sqlite_master "
            "WHERE name IN ('book_cards_fts', 'book_cards_fts_ai', "
            "'book_cards_fts_ad', 'book_cards_fts_au')",
          )
          .get();
      final byName = {
        for (final row in rows)
          row.read<String>('name'): row.read<String>('type'),
      };
      expect(byName['book_cards_fts'], 'table');
      expect(byName['book_cards_fts_ai'], 'trigger');
      expect(byName['book_cards_fts_ad'], 'trigger');
      expect(byName['book_cards_fts_au'], 'trigger');
    });

    test('triggers keep the FTS index in sync with book_cards', () async {
      await insertCard(1, '白日依山尽，黄河入海流。');
      await insertCard(2, 'Hello FluidText full text search.');

      expect(await ftsMatch('"黄河入海"'), [1]);
      expect(await ftsMatch('fluidtext'), [2]);

      await database.customStatement(
        'UPDATE book_cards SET content = ? WHERE id = 1',
        ['欲穷千里目，更上一层楼。'],
      );
      expect(await ftsMatch('"黄河入海"'), isEmpty);
      expect(await ftsMatch('"更上一层楼"'), [1]);

      await database.customStatement('DELETE FROM book_cards WHERE id = 1');
      expect(await ftsMatch('"更上一层楼"'), isEmpty);
    });

    test('upgrading from schema v1 creates FTS objects and backfills existing cards', () async {
      await insertCard(1, '旧时王谢堂前燕，飞入寻常百姓家。');
      final filePath = databaseFile.path;
      await database.close();

      // Rewind the file to a schema-v1 state: no FTS objects, version 1, and
      // no fts_index_version marker (v1 never wrote one).
      final raw = sqlite3.open(filePath);
      raw.execute('DROP TRIGGER book_cards_fts_ai');
      raw.execute('DROP TRIGGER book_cards_fts_ad');
      raw.execute('DROP TRIGGER book_cards_fts_au');
      raw.execute('DROP TABLE book_cards_fts');
      raw.execute(
        "DELETE FROM storage_metadata WHERE key = 'fts_index_version'",
      );
      raw.execute('PRAGMA user_version = 1');
      raw.dispose();

      database = LibraryDatabase.file(databaseFile);
      await database.customSelect('SELECT 1').get();

      // 回填是懒触发的：进入搜索功能时才调用 ensureSearchIndexBuilt。
      await database.ensureSearchIndexBuilt();
      expect(await database.isSearchIndexReady(), isTrue);
      expect(database.searchIndexProgress.value, isNull);
      expect(await ftsMatch('"飞入寻常百姓家"'), [1]);
    });
  });
}
