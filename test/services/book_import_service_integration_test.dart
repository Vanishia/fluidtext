import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/book_card_repository.dart';
import 'package:fluidtext/services/book_asset_store.dart';
import 'package:fluidtext/services/book_import_service.dart';
import 'package:isar/isar.dart';

import '../support/epub_fixture.dart';
import '../support/isar_test_core.dart';

void main() {
  Directory? databaseDirectory;
  Directory? documentsDirectory;
  Isar? isar;
  late BookAssetStore assetStore;
  late BookImportService importService;

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
      isar: isar!,
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
    final first = await importService.importEpubBytes(isar: isar!, bytes: epub);
    final second = await importService.importEpubBytes(
      isar: isar!,
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
        isar: isar!,
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
      isar: isar!,
      bytes: buildTestEpub(),
    );
    final book = await isar!.books.get(result.bookId);
    final root = Directory(
      '${documentsDirectory!.path}${Platform.pathSeparator}book_assets${Platform.pathSeparator}${book!.assetRootKey}',
    );
    expect(await root.exists(), isTrue);

    final repository = BookCardRepository(isar!, assetStore: assetStore);
    await repository.deleteBook(result.bookId);

    expect(await root.exists(), isFalse);
  });
}
