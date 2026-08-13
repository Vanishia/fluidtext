import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';
import 'package:fluidtext/storage/storage_layout.dart';
import 'package:sqlite3/sqlite3.dart';

import 'dart:io';

import 'library_repository_contract.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  runLibraryRepositoryContract(_SqliteRepositoryDriver.create);

  test('SQLite rolls back a failed write transaction', () async {
    final driver = await _SqliteRepositoryDriver.create();
    addTearDown(driver.close);

    await expectLater(
      driver.database.transaction(() async {
        await driver.database
            .into(driver.database.sqliteBooks)
            .insert(
              SqliteBooksCompanion.insert(
                id: const Value(99),
                title: 'Rolled back',
                createdAtMs: DateTime(2026, 3).millisecondsSinceEpoch,
              ),
            );
        throw StateError('force rollback');
      }),
      throwsA(isA<StateError>()),
    );

    expect(
      await (driver.database.select(
        driver.database.sqliteBooks,
      )..where((table) => table.id.equals(99))).getSingleOrNull(),
      isNull,
    );
  });

  test(
    'SQLite enforces foreign keys, cascade delete and integrity checks',
    () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);

      await expectLater(
        driver.database
            .into(driver.database.sqliteBookCards)
            .insert(
              SqliteBookCardsCompanion.insert(
                id: const Value(99),
                bookId: 404,
                bookTitle: 'Missing',
                cardIndex: 0,
                chapterIndex: 0,
                chapterCardIndex: 0,
                content: 'orphan',
                isRead: false,
                isFavorite: false,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      await driver.repository.deleteBook(driver.firstBookId);
      expect(
        await (driver.database.select(
          driver.database.sqliteBookCards,
        )..where((table) => table.bookId.equals(driver.firstBookId))).get(),
        isEmpty,
      );

      expect(await driver.database.integrityCheck(), ['ok']);
      expect(await driver.database.foreignKeyCheck(), isEmpty);
    },
  );

  test('SQLite stores schema metadata and uses expected stats index', () async {
    final driver = await _SqliteRepositoryDriver.create();
    addTearDown(driver.close);

    final metadata = await driver.database
        .customSelect(
          'SELECT key, value FROM storage_metadata ORDER BY key',
          readsFrom: {driver.database.storageMetadata},
        )
        .get();
    expect({
      for (final row in metadata)
        row.read<String>('key'): row.read<String>('value'),
    }, containsPair('schema_version', '1'));
    expect({
      for (final row in metadata)
        row.read<String>('key'): row.read<String>('value'),
    }, containsPair('storage_format_version', 'sqlite-v1'));

    final plan = await driver.database.explainQueryPlan(
      '''
      SELECT book_id, COUNT(*)
      FROM book_cards
      WHERE book_id IN (?)
      GROUP BY book_id
      ''',
      [driver.firstBookId],
    );
    expect(
      plan.map((row) => row.data.values.join(' ')).join('\n'),
      contains('idx_book_cards'),
    );
  });

  test(
    'SQLite import leaves no partial book when the batch write fails',
    () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);
      final repository = driver.repository;

      // Duplicate (book_id, card_index) inside one draft violates the UNIQUE
      // constraint halfway through the batch insert; the whole import
      // transaction must roll back so no half-imported book survives.
      const cards = [
        BookCardDraft(
          bookTitle: 'Broken import',
          cardIndex: 0,
          chapterIndex: 0,
          chapterCardIndex: 0,
          chapterTitle: null,
          content: 'First card',
          blocksJson: null,
        ),
        BookCardDraft(
          bookTitle: 'Broken import',
          cardIndex: 0,
          chapterIndex: 0,
          chapterCardIndex: 1,
          chapterTitle: null,
          content: 'Conflicting card',
          blocksJson: null,
        ),
      ];
      final draft = ImportBookDraft(
        title: 'Broken import',
        createdAt: DateTime(2026, 8, 13),
        fileHash: 'broken-import-file-hash',
        contentFingerprint: 'broken-import-fingerprint',
        sourceFileName: 'broken.epub',
        importedAt: DateTime(2026, 8, 13),
        cardCount: cards.length,
        textCharCount: 24,
        assetRootKey: 'asset_broken_import',
        cards: cards,
        assets: const [
          BookAssetDraft(
            assetKey: 'broken-asset',
            originalHref: null,
            normalizedHref: null,
            mimeType: 'image/png',
            relativePath:
                'book_assets/asset_broken_import/images/broken.png',
            byteLength: 12,
          ),
        ],
      );

      await expectLater(
        repository.importBookDraft(draft),
        throwsA(isA<SqliteException>()),
      );

      final books = await repository.loadBooks();
      expect(
        books.where((book) => book.title == 'Broken import'),
        isEmpty,
      );
      expect(
        await driver.database.customSelect(
          'SELECT COUNT(*) AS count FROM book_cards WHERE book_title = ?',
          variables: [Variable<String>('Broken import')],
          readsFrom: {driver.database.sqliteBookCards},
        ).getSingle().then((row) => row.read<int>('count')),
        0,
      );
      expect(
        await driver.database.customSelect(
          'SELECT COUNT(*) AS count FROM book_assets WHERE asset_key = ?',
          variables: [Variable<String>('broken-asset')],
          readsFrom: {driver.database.sqliteBookAssets},
        ).getSingle().then((row) => row.read<int>('count')),
        0,
      );
      expect(await driver.database.integrityCheck(), ['ok']);
    },
  );

  test(
    'SQLite file database opens through StorageLayout and reopens cleanly',
    () async {      final directory = await Directory.systemTemp.createTemp(
        'fluidtext-sqlite-layout-',
      );
      LibraryDatabase? reopened;
      addTearDown(() async {
        await reopened?.close();
        await _deleteDirectoryWithRetry(directory);
      });

      final layout = StorageLayout.modern(rootDirectory: directory);
      final database = await openLibraryDatabaseForLayout(() async => layout);
      await database
          .into(database.sqliteBooks)
          .insert(
            SqliteBooksCompanion.insert(
              id: const Value(1),
              title: 'Persistent',
              createdAtMs: DateTime(2026, 8, 12).millisecondsSinceEpoch,
            ),
          );
      await database.checkpoint();
      await database.close();

      reopened = await openLibraryDatabaseForLayout(() async => layout);

      expect(await layout.sqliteDatabaseFile.exists(), isTrue);
      expect(
        (await SqliteLibraryRepository(reopened).loadBooks()).single.title,
        'Persistent',
      );
      expect(await reopened.integrityCheck(), ['ok']);
    },
  );
}

class _SqliteRepositoryDriver implements LibraryRepositoryContractDriver {
  _SqliteRepositoryDriver._({required this.database, required this.repository});

  static const _firstBookId = 1;
  static const _secondBookId = 2;
  static const _firstCardId = 10;
  static const _secondCardId = 11;
  static const _thirdCardId = 12;
  static const _assetKey = 'asset-key';

  final LibraryDatabase database;

  @override
  final SqliteLibraryRepository repository;

  @override
  int get firstBookId => _firstBookId;

  @override
  int get secondBookId => _secondBookId;

  @override
  int get firstCardId => _firstCardId;

  @override
  int get secondCardId => _secondCardId;

  @override
  int get thirdCardId => _thirdCardId;

  @override
  String get assetKey => _assetKey;

  static Future<_SqliteRepositoryDriver> create() async {
    final database = LibraryDatabase.inMemory();
    final repository = SqliteLibraryRepository(database);
    final driver = _SqliteRepositoryDriver._(
      database: database,
      repository: repository,
    );
    await driver._seed();
    return driver;
  }

  Future<void> _seed() async {
    final firstCreatedAt = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final secondCreatedAt = DateTime(2026, 2, 1).millisecondsSinceEpoch;
    final readAt = DateTime(2026, 1, 2).millisecondsSinceEpoch;
    final favoritedAt = DateTime(2026, 1, 3).millisecondsSinceEpoch;

    await database.transaction(() async {
      await database.batch((batch) {
        batch.insertAll(database.sqliteBooks, [
          SqliteBooksCompanion.insert(
            id: const Value(_firstBookId),
            title: 'First',
            createdAtMs: firstCreatedAt,
          ),
          SqliteBooksCompanion.insert(
            id: const Value(_secondBookId),
            title: 'Second',
            createdAtMs: secondCreatedAt,
          ),
        ]);
        batch.insertAll(database.sqliteBookCards, [
          SqliteBookCardsCompanion.insert(
            id: const Value(_firstCardId),
            bookId: _firstBookId,
            bookTitle: 'First',
            cardIndex: 0,
            chapterIndex: 0,
            chapterCardIndex: 0,
            content: 'First card',
            isRead: false,
            isFavorite: false,
          ),
          SqliteBookCardsCompanion.insert(
            id: const Value(_secondCardId),
            bookId: _firstBookId,
            bookTitle: 'First',
            cardIndex: 1,
            chapterIndex: 0,
            chapterCardIndex: 1,
            content: 'Second card',
            isRead: true,
            readAtMs: Value(readAt),
            isFavorite: true,
            favoritedAtMs: Value(favoritedAt),
          ),
          SqliteBookCardsCompanion.insert(
            id: const Value(_thirdCardId),
            bookId: _firstBookId,
            bookTitle: 'First',
            cardIndex: 2,
            chapterIndex: 0,
            chapterCardIndex: 2,
            content: 'Third card',
            isRead: true,
            readAtMs: Value(readAt),
            isFavorite: true,
            favoritedAtMs: Value(favoritedAt),
          ),
        ]);
        batch.insert(
          database.sqliteBookAssets,
          SqliteBookAssetsCompanion.insert(
            id: const Value(20),
            bookId: _firstBookId,
            assetKey: _assetKey,
            relativePath: 'book_assets/root/images/asset-key.png',
            createdAtMs: firstCreatedAt,
          ),
        );
      });
    });
  }

  @override
  Future<void> close() => database.close();
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
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
}
