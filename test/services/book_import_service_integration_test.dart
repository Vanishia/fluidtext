import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/book_card_repository.dart';
import 'package:fluidtext/services/book_asset_store.dart';
import 'package:fluidtext/services/book_import_service.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';
import 'package:isar/isar.dart';

import '../support/epub_fixture.dart';
import '../support/isar_test_core.dart';

void main() {
  Directory? databaseDirectory;
  Directory? documentsDirectory;
  Isar? isar;
  late BookAssetStore assetStore;
  late BookImportService importService;
  late BookCardRepository repository;

  setUpAll(initializeIsarTestCore);

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-import-db-',
    );
    documentsDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-import-docs-',
    );
    isar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: databaseDirectory!.path,
      name: 'import_${DateTime.now().microsecondsSinceEpoch}',
      inspector: false,
    );
    assetStore = BookAssetStore(
      documentsDirectory: () async => documentsDirectory!,
    );
    importService = BookImportService(assetStore: assetStore);
    repository = BookCardRepository(isar!, assetStore: assetStore);
  });

  tearDown(() async {
    await isar?.close(deleteFromDisk: true);
    if (await databaseDirectory?.exists() ?? false) {
      await databaseDirectory!.delete(recursive: true);
    }
    if (await documentsDirectory?.exists() ?? false) {
      await documentsDirectory!.delete(recursive: true);
    }
  });

  test('imports a real EPUB and keeps only referenced staged images', () async {
    final result = await importService.importEpubBytes(
      repository: repository,
      bytes: buildTestEpub(),
      sourceFileName: 'integration.epub',
      targetCharsPerCard: 20,
    );

    expect(result.wasDuplicate, isFalse);
    expect(result.insertedCards, greaterThan(0));
    final book = await isar!.books.get(result.bookId);
    final cards = await isar!.bookCards
        .filter()
        .bookIdEqualTo(result.bookId)
        .findAll();
    final assets = await isar!.bookAssets
        .filter()
        .bookIdEqualTo(result.bookId)
        .findAll();
    expect(book?.assetRootKey, isNotNull);
    expect(
      cards.any((card) => card.blocksJson?.contains('assetKey') == true),
      isTrue,
    );
    expect(assets, hasLength(1));
    expect(
      await (await assetStore.resolveRelativeFile(
        assets.single.relativePath,
      )).exists(),
      isTrue,
    );

    final root = Directory(
      '${documentsDirectory!.path}${Platform.pathSeparator}book_assets${Platform.pathSeparator}${book!.assetRootKey}',
    );
    final files = await root
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File)
        .toList();
    expect(files, hasLength(1));
  });

  test('cleans staging files when a duplicate import is detected', () async {
    final epub = buildTestEpub();
    final first = await importService.importEpubBytes(
      repository: repository,
      bytes: epub,
    );
    final second = await importService.importEpubBytes(
      repository: repository,
      bytes: epub,
    );

    expect(second.wasDuplicate, isTrue);
    expect(second.bookId, first.bookId);
    final assetsRoot = Directory(
      '${documentsDirectory!.path}${Platform.pathSeparator}book_assets',
    );
    final roots = await assetsRoot
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .toList();
    expect(roots, hasLength(1));
  });

  test('cleans staged images when chapter parsing fails', () async {
    await expectLater(
      importService.importEpubBytes(
        repository: repository,
        bytes: buildTestEpub(includeChapterFile: false),
      ),
      throwsA(isA<BookImportException>()),
    );

    final assetsRoot = Directory(
      '${documentsDirectory!.path}${Platform.pathSeparator}book_assets',
    );
    final roots = await assetsRoot.exists()
        ? await assetsRoot
              .list(followLinks: false)
              .where((entity) => entity is Directory)
              .toList()
        : const <FileSystemEntity>[];
    expect(roots, isEmpty);
  });

  test('deleting an imported book removes its staged resource root', () async {
    final result = await importService.importEpubBytes(
      repository: repository,
      bytes: buildTestEpub(),
    );
    final book = await isar!.books.get(result.bookId);
    final root = Directory(
      '${documentsDirectory!.path}${Platform.pathSeparator}book_assets${Platform.pathSeparator}${book!.assetRootKey}',
    );
    expect(await root.exists(), isTrue);

    await repository.deleteBook(result.bookId);

    expect(await root.exists(), isFalse);
  });

  test('imports the same real EPUB through the SQLite repository', () async {
    final database = LibraryDatabase.inMemory();
    addTearDown(database.close);
    final sqliteRepository = SqliteLibraryRepository(
      database,
      assetStore: assetStore,
    );

    final result = await importService.importEpubBytes(
      repository: sqliteRepository,
      bytes: buildTestEpub(),
      sourceFileName: 'sqlite.epub',
      targetCharsPerCard: 20,
    );

    expect(result.wasDuplicate, isFalse);
    final books = await sqliteRepository.loadBooksByIds([result.bookId]);
    final cards = await sqliteRepository.loadOrderedCardIds([result.bookId]);
    final snapshot = await sqliteRepository.buildBackupSnapshot();
    final assets = snapshot.bookAssets
        .where((asset) => asset.bookId == result.bookId)
        .toList(growable: false);
    expect(books.single.sourceFileName, 'sqlite.epub');
    expect(cards, hasLength(result.insertedCards));
    expect(assets, hasLength(1));
  });

  test('reports staged progress while importing', () async {
    final progresses = <BookImportProgress>[];
    final result = await importService.importEpubBytes(
      repository: repository,
      bytes: buildTestEpub(),
      targetCharsPerCard: 20,
      onProgress: progresses.add,
    );

    expect(result.insertedCards, greaterThan(0));
    expect(progresses.first.stage, BookImportStage.parsing);
    expect(progresses.last.stage, BookImportStage.writing);

    final reading = progresses
        .where((progress) => progress.stage == BookImportStage.readingChapters)
        .toList();
    expect(reading, isNotEmpty);
    expect(reading.last.totalUnits, greaterThan(0));
    expect(reading.last.fraction, 1.0);

    final building = progresses
        .where((progress) => progress.stage == BookImportStage.buildingCards)
        .toList();
    expect(building, isNotEmpty);
    expect(building.last.producedCards, result.insertedCards);
  });

  test('imports a chapter encoded as GBK', () async {
    const paragraph = '夜半钟声到客船，姑苏城外寒山寺。';
    final result = await importService.importEpubBytes(
      repository: repository,
      bytes: buildTestEpub(paragraph: paragraph, chapterAsGbk: true),
      targetCharsPerCard: 20,
    );

    expect(result.insertedCards, greaterThan(0));
    final cards = await isar!.bookCards
        .filter()
        .bookIdEqualTo(result.bookId)
        .findAll();
    expect(
      cards.any((card) => card.content.contains('夜半钟声到客船')),
      isTrue,
    );
  });

  test('hard-cuts a long paragraph without any sentence boundary', () async {
    final result = await importService.importEpubBytes(
      repository: repository,
      bytes: buildTestEpub(paragraph: '字' * 5000, includeImage: false),
      targetCharsPerCard: 20,
    );

    expect(result.insertedCards, greaterThan(1));
    final cards = await isar!.bookCards
        .filter()
        .bookIdEqualTo(result.bookId)
        .findAll();
    for (final card in cards) {
      expect(card.content.length, lessThanOrEqualTo(60));
    }
  });
}
