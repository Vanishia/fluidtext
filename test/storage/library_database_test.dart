import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';

/// Runtime configuration and query-plan guarantees for the production
/// (file-based) database. The SQL statements mirror the queries in
/// `SqliteLibraryRepository`; keep them in sync when those queries change.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory directory;
  late LibraryDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fluidtext-db-test-');
    database = LibraryDatabase.file(
      File('${directory.path}${Platform.pathSeparator}library.sqlite'),
    );
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
}
