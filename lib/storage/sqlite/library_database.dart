import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../services/app_logger.dart';
import '../storage_layout.dart';

part 'library_database.g.dart';

@DriftDatabase(
  tables: [
    SqliteBooks,
    SqliteBookCards,
    SqliteBookAssets,
    SqliteBookRemarks,
    StorageMetadata,
  ],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(super.executor);

  factory LibraryDatabase.file(File file) {
    return LibraryDatabase(openLibraryDatabase(file));
  }

  factory LibraryDatabase.inMemory() {
    return LibraryDatabase(NativeDatabase.memory(setup: configureSqlite));
  }

  /// The current schema version, mirrored in migration completion markers.
  static const int currentSchemaVersion = 2;

  /// Bump when the FTS index definition changes (tokenizer/columns) so
  /// existing installs rebuild the index on next launch.
  static const String ftsIndexVersion = '1';
  static const String _ftsIndexVersionKey = 'fts_index_version';

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement('PRAGMA busy_timeout = 5000');
        await _ensureStorageMetadata();
      },
      onCreate: (migrator) async {
        await migrator.createAll();
        await _createSchemaV1Indexes();
        await _createFtsObjects();
        // Fresh databases index through the sync triggers from the very first
        // insert, so they start out "ready" — only v1 upgrades backfill.
        await _writeFtsIndexMarker();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await _createFtsObjects();
        }
      },
    );
  }

  Future<void> _ensureStorageMetadata() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await customStatement(
      '''
      INSERT INTO storage_metadata(key, value, updated_at_ms)
      VALUES ('schema_version', ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      [schemaVersion.toString(), now],
    );
    await customStatement(
      '''
      INSERT INTO storage_metadata(key, value, updated_at_ms)
      VALUES ('storage_format_version', 'sqlite-v1', ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      [now],
    );
  }

  Future<void> _createSchemaV1Indexes() async {
    for (final statement in sqliteSchemaV1Indexes) {
      await customStatement(statement);
    }
  }

  Future<void> _createFtsObjects() async {
    for (final statement in sqliteSchemaV2FtsStatements) {
      await customStatement(statement);
    }
  }

  /// Whether the FTS index has been rebuilt for [ftsIndexVersion]. Until this
  /// returns true (freshly upgraded installs), search may miss existing cards.
  Future<bool> isSearchIndexReady() async {
    final row = await customSelect(
      'SELECT value FROM storage_metadata WHERE key = ?',
      variables: [Variable(_ftsIndexVersionKey)],
    ).getSingleOrNull();
    return row?.read<String>('value') == ftsIndexVersion;
  }

  /// 0..1 while [rebuildSearchIndex] is running, null otherwise. Backed by an
  /// in-memory notifier because the rebuild lives on the background isolate
  /// connection — callers in the UI isolate only observe this value.
  final ValueNotifier<double?> searchIndexProgress = ValueNotifier<double?>(
    null,
  );

  Future<void> _rebuildSearchIndexIfNeeded() async {
    try {
      if (await isSearchIndexReady()) return;
      AppLogger.instance.info('fts', 'rebuilding book_cards_fts index');
      final stopwatch = Stopwatch()..start();
      await rebuildSearchIndex();
      AppLogger.instance.info(
        'fts',
        'book_cards_fts rebuild finished in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (error, stackTrace) {
      // Marker stays unset so the rebuild is retried on the next request.
      AppLogger.instance.error(
        'fts',
        'book_cards_fts rebuild failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void>? _ongoingSearchIndexRebuild;

  /// Starts the FTS backfill unless the index is already built. Idempotent:
  /// concurrent callers share the in-flight rebuild. Deliberately NOT called
  /// at database open — the backfill only runs when the search feature is
  /// actually used (only v1→v2 upgrades have unindexed cards; fresh installs,
  /// migrations and restores index through the sync triggers).
  Future<void> ensureSearchIndexBuilt() {
    return _ongoingSearchIndexRebuild ??= _rebuildSearchIndexIfNeeded()
        .whenComplete(() => _ongoingSearchIndexRebuild = null);
  }

  Future<void> _writeFtsIndexMarker() {
    return customStatement(
      '''
      INSERT INTO storage_metadata(key, value, updated_at_ms)
      VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at_ms = excluded.updated_at_ms
      ''',
      [
        _ftsIndexVersionKey,
        ftsIndexVersion,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  /// Rebuilds the FTS index in chunks (inside one transaction so imports
  /// cannot interleave and double-index rows) and reports progress through
  /// [searchIndexProgress]. Chunked instead of the single `rebuild` command
  /// precisely so the progress bar has something real to show.
  Future<void> rebuildSearchIndex() async {
    const chunkSize = 500;
    final total = await customSelect(
      'SELECT COUNT(*) AS count FROM book_cards',
    ).getSingle().then((row) => row.read<int>('count'));
    searchIndexProgress.value = 1.0;
    if (total > 0) searchIndexProgress.value = 0.0;
    try {
      await transaction(() async {
        await customStatement(
          "INSERT INTO book_cards_fts(book_cards_fts) VALUES('delete-all')",
        );
        var lastId = 0;
        var done = 0;
        while (true) {
          final rows = await customSelect(
            'SELECT id, content FROM book_cards '
            'WHERE id > ? ORDER BY id ASC LIMIT $chunkSize',
            variables: [Variable<int>(lastId)],
          ).get();
          if (rows.isEmpty) break;
          final placeholders = rows.map((_) => '(?, ?)').join(', ');
          await customStatement(
            'INSERT INTO book_cards_fts(rowid, content) VALUES $placeholders',
            [
              for (final row in rows) ...[
                row.read<int>('id'),
                row.read<String>('content'),
              ],
            ],
          );
          done += rows.length;
          lastId = rows.last.read<int>('id');
          searchIndexProgress.value = done / total;
        }
        await _writeFtsIndexMarker();
      });
    } finally {
      searchIndexProgress.value = null;
    }
  }

  Future<List<String>> integrityCheck() async {
    final rows = await customSelect('PRAGMA integrity_check').get();
    return rows.map((row) => row.data.values.single.toString()).toList();
  }

  Future<List<QueryRow>> foreignKeyCheck() {
    return customSelect('PRAGMA foreign_key_check').get();
  }

  Future<void> checkpoint({bool truncate = true}) async {
    await customStatement(
      truncate ? 'PRAGMA wal_checkpoint(TRUNCATE)' : 'PRAGMA wal_checkpoint',
    );
  }

  Future<List<QueryRow>> explainQueryPlan(String sql, [List<Object?>? args]) {
    return customSelect(
      'EXPLAIN QUERY PLAN $sql',
      variables: [for (final arg in args ?? const <Object?>[]) Variable(arg)],
    ).get();
  }
}

QueryExecutor openLibraryDatabase(File file) {
  return NativeDatabase.createInBackground(file, setup: configureSqlite);
}

void configureSqlite(Database database) {
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA busy_timeout = 5000');
  // Migration plan §4.3: without conclusive kill-recovery benchmarks on both
  // platforms the conservative default is FULL; only downgrade to NORMAL when
  // real-user performance is unacceptable AND recovery tests still pass.
  database.execute('PRAGMA synchronous = FULL');
}

Future<LibraryDatabase> openLibraryDatabaseForLayout(
  StorageLayoutProvider storageLayout,
) async {
  final layout = await storageLayout();
  await layout.rootDirectory.create(recursive: true);
  return LibraryDatabase.file(layout.sqliteDatabaseFile);
}

const sqliteSchemaV1Indexes = <String>[
  'CREATE INDEX IF NOT EXISTS idx_books_file_hash ON books(file_hash)',
  '''
  CREATE INDEX IF NOT EXISTS idx_books_content_fingerprint
    ON books(content_fingerprint)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_books_created_at_desc
    ON books(created_at_ms DESC)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_cards_book_order
    ON book_cards(book_id, card_index)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_cards_unread_order
    ON book_cards(book_id, is_read, card_index)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_cards_read_activity
    ON book_cards(is_read, read_at_ms DESC, id DESC)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_cards_favorite_activity
    ON book_cards(is_favorite, favorited_at_ms DESC, id DESC)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_assets_book_asset_key
    ON book_assets(book_id, asset_key)
  ''',
  '''
  CREATE INDEX IF NOT EXISTS idx_book_assets_normalized_href
    ON book_assets(normalized_href)
  ''',
];

/// Schema v2: FTS5 external-content index over book_cards.content with
/// triggers keeping it in sync. The trigram tokenizer makes substring
/// matching work for both Chinese and English (unicode61 cannot tokenize
/// Chinese); queries shorter than 3 characters bypass FTS and use LIKE.
const sqliteSchemaV2FtsStatements = <String>[
  '''
  CREATE VIRTUAL TABLE IF NOT EXISTS book_cards_fts USING fts5(
    content,
    content='book_cards',
    content_rowid='id',
    tokenize='trigram'
  )
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS book_cards_fts_ai AFTER INSERT ON book_cards BEGIN
    INSERT INTO book_cards_fts(rowid, content) VALUES (new.id, new.content);
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS book_cards_fts_ad AFTER DELETE ON book_cards BEGIN
    INSERT INTO book_cards_fts(book_cards_fts, rowid, content)
    VALUES ('delete', old.id, old.content);
  END
  ''',
  '''
  CREATE TRIGGER IF NOT EXISTS book_cards_fts_au AFTER UPDATE OF content ON book_cards BEGIN
    INSERT INTO book_cards_fts(book_cards_fts, rowid, content)
    VALUES ('delete', old.id, old.content);
    INSERT INTO book_cards_fts(rowid, content) VALUES (new.id, new.content);
  END
  ''',
];

class SqliteBooks extends Table {
  @override
  String get tableName => 'books';

  IntColumn get id => integer()();
  TextColumn get title => text()();
  IntColumn get createdAtMs => integer().named('created_at_ms')();
  TextColumn get fileHash => text().named('file_hash').nullable()();
  TextColumn get contentFingerprint =>
      text().named('content_fingerprint').nullable()();
  TextColumn get sourceFileName =>
      text().named('source_file_name').nullable()();
  IntColumn get importedAtMs => integer().named('imported_at_ms').nullable()();
  IntColumn get cardCount => integer().named('card_count').nullable()();
  IntColumn get textCharCount =>
      integer().named('text_char_count').nullable()();
  TextColumn get assetRootKey => text().named('asset_root_key').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK(id > 0)',
    'CHECK(card_count IS NULL OR card_count >= 0)',
    'CHECK(text_char_count IS NULL OR text_char_count >= 0)',
  ];
}

class SqliteBookCards extends Table {
  @override
  String get tableName => 'book_cards';

  IntColumn get id => integer()();
  IntColumn get bookId => integer()
      .named('book_id')
      .customConstraint(
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
      )();
  TextColumn get bookTitle => text().named('book_title')();
  IntColumn get cardIndex => integer().named('card_index')();
  IntColumn get chapterIndex => integer().named('chapter_index')();
  IntColumn get chapterCardIndex => integer().named('chapter_card_index')();
  TextColumn get chapterTitle => text().named('chapter_title').nullable()();
  TextColumn get content => text()();
  TextColumn get blocksJson => text().named('blocks_json').nullable()();
  BoolColumn get isRead => boolean().named('is_read')();
  IntColumn get readAtMs => integer().named('read_at_ms').nullable()();
  BoolColumn get isFavorite => boolean().named('is_favorite')();
  IntColumn get favoritedAtMs =>
      integer().named('favorited_at_ms').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {bookId, cardIndex},
  ];

  @override
  List<String> get customConstraints => const [
    'CHECK(id > 0)',
    'CHECK(is_read IN (0, 1))',
    'CHECK(is_favorite IN (0, 1))',
    'CHECK(card_index >= 0)',
    'CHECK(chapter_index >= 0)',
    'CHECK(chapter_card_index >= 0)',
    'CHECK(is_read = 1 OR read_at_ms IS NULL)',
    'CHECK(is_favorite = 1 OR favorited_at_ms IS NULL)',
  ];
}

class SqliteBookAssets extends Table {
  @override
  String get tableName => 'book_assets';

  IntColumn get id => integer()();
  IntColumn get bookId => integer()
      .named('book_id')
      .customConstraint(
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
      )();
  TextColumn get assetKey => text().named('asset_key')();
  TextColumn get originalHref => text().named('original_href').nullable()();
  TextColumn get normalizedHref => text().named('normalized_href').nullable()();
  TextColumn get mimeType => text().named('mime_type').nullable()();
  TextColumn get relativePath => text().named('relative_path')();
  IntColumn get byteLength => integer().named('byte_length').nullable()();
  IntColumn get createdAtMs => integer().named('created_at_ms')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK(id > 0)',
    'CHECK(byte_length IS NULL OR byte_length >= 0)',
  ];
}

class SqliteBookRemarks extends Table {
  @override
  String get tableName => 'book_remarks';

  IntColumn get bookId => integer()
      .named('book_id')
      .customConstraint(
        'NOT NULL REFERENCES books(id) ON DELETE CASCADE CHECK(book_id > 0)',
      )();
  TextColumn get title => text()();
  IntColumn get updatedAtMs => integer().named('updated_at_ms')();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

class StorageMetadata extends Table {
  @override
  String get tableName => 'storage_metadata';

  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtMs => integer().named('updated_at_ms')();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
