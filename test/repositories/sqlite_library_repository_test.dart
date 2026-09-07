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
    }, containsPair('schema_version', '2'));
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

  test('pruneIncompleteBooks removes half-imported books only', () async {
    final driver = await _SqliteRepositoryDriver.create();
    addTearDown(driver.close);

    // Seeded book 1: 3 cards, no recorded count → legacy, judged complete.
    // Seeded book 2: 0 cards → broken, must be pruned.
    // Book 3: recorded 5 cards but only 1 stored → half-imported.
    await driver.database.transaction(() async {
      await driver.database
          .into(driver.database.sqliteBooks)
          .insert(
            SqliteBooksCompanion.insert(
              id: const Value(3),
              title: 'Half imported',
              createdAtMs: DateTime(2026, 3).millisecondsSinceEpoch,
              cardCount: const Value(5),
            ),
          );
      await driver.database
          .into(driver.database.sqliteBookCards)
          .insert(
            SqliteBookCardsCompanion.insert(
              id: const Value(30),
              bookId: 3,
              bookTitle: 'Half imported',
              cardIndex: 0,
              chapterIndex: 0,
              chapterCardIndex: 0,
              content: 'surviving card',
              isRead: false,
              isFavorite: false,
            ),
          );
    });

    final pruned = await driver.repository.pruneIncompleteBooks();

    expect(
      pruned.map((book) => book.id),
      containsAll(<int>[_SqliteRepositoryDriver._secondBookId, 3]),
    );
    expect(
      pruned.map((book) => book.id),
      isNot(contains(_SqliteRepositoryDriver._firstBookId)),
    );
    final remaining = await driver.repository.loadBooks();
    expect(
      remaining.map((book) => book.id),
      [_SqliteRepositoryDriver._firstBookId],
    );
    expect(await driver.database.integrityCheck(), ['ok']);
  });

  group('searchCards', () {
    Future<void> insertCard(
      _SqliteRepositoryDriver driver, {
      required int id,
      required String content,
    }) async {
      await driver.database
          .into(driver.database.sqliteBookCards)
          .insert(
            SqliteBookCardsCompanion.insert(
              id: Value(id),
              bookId: _SqliteRepositoryDriver._firstBookId,
              bookTitle: 'First',
              cardIndex: id,
              chapterIndex: 0,
              chapterCardIndex: id,
              content: content,
              isRead: false,
              isFavorite: false,
            ),
          );
    }

    test('finds Chinese and English cards with marked snippets', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);
      await insertCard(driver, id: 100, content: '春天来了，花儿开了，小鸟在歌唱。');
      await insertCard(driver, id: 101, content: 'Autumn leaves fall slowly.');

      final chinese = await driver.repository.searchCards('花儿开了');
      expect(chinese.map((hit) => hit.card.id), [100]);
      expect(chinese.single.snippet, contains('<mark>'));
      expect(chinese.single.snippet, contains('花儿开'));

      final english = await driver.repository.searchCards('autumn LEAVES');
      expect(english.map((hit) => hit.card.id), [101]);
    });

    test('falls back to LIKE for queries shorter than 3 characters', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);
      await insertCard(driver, id: 100, content: '床前明月光，疑是地上霜。');

      final hits = await driver.repository.searchCards('明月');
      expect(hits.map((hit) => hit.card.id), [100]);
      expect(hits.single.snippet, contains('<mark>明月</mark>'));
    });

    test('paginates results with limit and offset', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);
      for (var i = 0; i < 5; i += 1) {
        await insertCard(driver, id: 100 + i, content: '第 $i 张卡片都包含搜索词。');
      }

      final page1 = await driver.repository.searchCards('搜索词', limit: 2);
      final page2 = await driver.repository.searchCards(
        '搜索词',
        limit: 2,
        offset: 2,
      );
      final page3 = await driver.repository.searchCards(
        '搜索词',
        limit: 2,
        offset: 4,
      );

      expect(page1, hasLength(2));
      expect(page2, hasLength(2));
      expect(page3, hasLength(1));
      final allIds = [
        ...page1.map((hit) => hit.card.id),
        ...page2.map((hit) => hit.card.id),
        ...page3.map((hit) => hit.card.id),
      ];
      expect(allIds.toSet(), hasLength(5));
    });

    test('returns empty for blank queries and non-matches', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);

      expect(await driver.repository.searchCards('   '), isEmpty);
      expect(await driver.repository.searchCards('不存在的词汇'), isEmpty);
    });

    test('reflects content updates and deletes', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);
      await insertCard(driver, id: 100, content: '最初的文字包含旧关键词。');
      expect(await driver.repository.searchCards('旧关键词'), hasLength(1));

      await driver.database.customStatement(
        'UPDATE book_cards SET content = ? WHERE id = 100',
        ['改写后的文字换成新说法。'],
      );
      expect(await driver.repository.searchCards('旧关键词'), isEmpty);
      expect(await driver.repository.searchCards('新说法'), hasLength(1));

      await driver.database.customStatement(
        'DELETE FROM book_cards WHERE id = 100',
      );
      expect(await driver.repository.searchCards('新说法'), isEmpty);
    });

    test('fresh databases report the search index as ready', () async {
      final driver = await _SqliteRepositoryDriver.create();
      addTearDown(driver.close);

      for (var i = 0; i < 50; i += 1) {
        if (await driver.repository.isSearchIndexReady()) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await driver.repository.isSearchIndexReady(), isTrue);
    });
  });

  test('pruneIncompleteBooks keeps complete books with recorded counts', () async {
    final driver = await _SqliteRepositoryDriver.create();
    addTearDown(driver.close);

    // Book 1 has 3 cards; record the matching count and clean up book 2
    // (0 cards) so only the complete book remains.
    await (driver.database.update(
      driver.database.sqliteBooks,
    )..where((table) => table.id.equals(_SqliteRepositoryDriver._firstBookId)))
        .write(const SqliteBooksCompanion(cardCount: Value(3)));
    await driver.database.customStatement('DELETE FROM books WHERE id = ?', [
      _SqliteRepositoryDriver._secondBookId,
    ]);

    final pruned = await driver.repository.pruneIncompleteBooks();

    expect(pruned, isEmpty);
    expect(await driver.repository.loadBooks(), hasLength(1));
  });
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
