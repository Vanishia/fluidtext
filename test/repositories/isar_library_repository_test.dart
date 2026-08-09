import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/book_card_repository.dart';
import 'package:fluidtext/repositories/library_repository.dart';
import 'package:isar/isar.dart';

import 'library_repository_contract.dart';
import '../support/isar_test_core.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  runLibraryRepositoryContract(_IsarRepositoryDriver.create);

  test('Isar rolls back a failed write transaction', () async {
    final driver = await _IsarRepositoryDriver.create();
    addTearDown(driver.close);

    await expectLater(
      driver.isar.writeTxn(() async {
        await driver.isar.books.put(
          Book()
            ..id = 99
            ..title = 'Rolled back'
            ..createdAt = DateTime(2026, 3),
        );
        throw StateError('force rollback');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await driver.isar.books.get(99), isNull);
  });
}

class _IsarRepositoryDriver implements LibraryRepositoryContractDriver {
  _IsarRepositoryDriver._({
    required this.isar,
    required this.directory,
    required this.repository,
  });

  static const _firstBookId = 1;
  static const _secondBookId = 2;
  static const _firstCardId = 10;
  static const _secondCardId = 11;
  static const _assetKey = 'asset-key';

  final Isar isar;
  final Directory directory;

  @override
  final LibraryRepository repository;

  @override
  int get firstBookId => _firstBookId;

  @override
  int get secondBookId => _secondBookId;

  @override
  int get firstCardId => _firstCardId;

  @override
  int get secondCardId => _secondCardId;

  @override
  String get assetKey => _assetKey;

  static Future<_IsarRepositoryDriver> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'fluidtext-isar-contract-',
    );
    final isar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: directory.path,
      name: 'contract_${DateTime.now().microsecondsSinceEpoch}',
      inspector: false,
    );
    final repository = BookCardRepository(isar);
    final driver = _IsarRepositoryDriver._(
      isar: isar,
      directory: directory,
      repository: repository,
    );
    await driver._seed();
    return driver;
  }

  Future<void> _seed() async {
    final firstBook = Book()
      ..id = _firstBookId
      ..title = 'First'
      ..createdAt = DateTime(2026, 1, 1);
    final secondBook = Book()
      ..id = _secondBookId
      ..title = 'Second'
      ..createdAt = DateTime(2026, 2, 1);
    final firstCard = BookCard()
      ..id = _firstCardId
      ..bookId = _firstBookId
      ..bookTitle = firstBook.title
      ..cardIndex = 0
      ..chapterIndex = 0
      ..chapterCardIndex = 0
      ..content = 'First card';
    final secondCard = BookCard()
      ..id = _secondCardId
      ..bookId = _firstBookId
      ..bookTitle = firstBook.title
      ..cardIndex = 1
      ..chapterIndex = 0
      ..chapterCardIndex = 1
      ..content = 'Second card'
      ..isRead = true
      ..readAt = DateTime(2026, 1, 2)
      ..isFavorite = true
      ..favoritedAt = DateTime(2026, 1, 3);
    final asset = BookAsset()
      ..id = 20
      ..bookId = _firstBookId
      ..assetKey = _assetKey
      ..relativePath = 'book_assets/root/images/asset-key.png'
      ..createdAt = DateTime(2026, 1, 1);

    await isar.writeTxn(() async {
      await isar.books.putAll([firstBook, secondBook]);
      await isar.bookCards.putAll([firstCard, secondCard]);
      await isar.bookAssets.put(asset);
    });
  }

  @override
  Future<void> close() async {
    await isar.close(deleteFromDisk: true);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
