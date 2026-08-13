import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

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
  static const int currentSchemaVersion = 1;

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
  database.execute('PRAGMA synchronous = NORMAL');
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
