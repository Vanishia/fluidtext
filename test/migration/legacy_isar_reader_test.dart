import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/legacy_isar_reader.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/storage/storage_layout.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-reader-test-',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<LegacyIsarReader> stagingReaderFromFixture({int batchSize = 1}) async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    final legacyLayout = StorageLayout.legacy(
      documentsDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}documents',
      ),
      supportDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}support',
      ),
    );
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    await staging.copyLegacyDatabases(legacyLayout: legacyLayout);
    return LegacyIsarReader(
      stagingRoot: staging.attemptDirectory,
      mainDatabaseCopy: staging.mainDatabaseCopy,
      remarkDatabaseCopy: staging.remarkDatabaseCopy,
      batchSize: batchSize,
    );
  }

  test('reads all collections in ascending-id batches with batchSize 1', () async {
    final reader = await stagingReaderFromFixture(batchSize: 1);
    addTearDown(reader.close);
    await reader.open();
    expect(reader.isOpen, isTrue);

    final bookBatches = await reader.readBooks().toList();
    final cardBatches = await reader.readBookCards().toList();
    final assetBatches = await reader.readBookAssets().toList();
    final remarkBatches = await reader.readBookRemarks().toList();

    // batchSize 1 forces one batch per record.
    expect(bookBatches, hasLength(2));
    expect(cardBatches, hasLength(3));
    expect(assetBatches, hasLength(1));
    expect(remarkBatches, hasLength(2));
    for (final batch in [
      ...bookBatches,
      ...cardBatches,
      ...assetBatches,
      ...remarkBatches,
    ]) {
      expect(batch, hasLength(1));
    }

    final books = bookBatches.expand((batch) => batch).toList();
    final cards = cardBatches.expand((batch) => batch).toList();
    final assets = assetBatches.expand((batch) => batch).toList();
    final remarks = remarkBatches.expand((batch) => batch).toList();

    expectIdsAscending(books.map((book) => book.id));
    expectIdsAscending(cards.map((card) => card.id));
    expectIdsAscending(assets.map((asset) => asset.id));
    expectIdsAscending(remarks.map((remark) => remark.id));

    expect(books.first.title, 'Legacy Fixture One');
    expect(books.first.assetRootKey, 'asset_fixture_one');
    expect(cards[1].isRead, isTrue);
    expect(cards[1].isFavorite, isTrue);
    expect(
      assets.single.relativePath,
      'book_assets/asset_fixture_one/images/cover.png',
    );
    expect(remarks.first.title, 'Pinned legacy title');
  });

  test('readBookRemarks is empty when no remark copy exists', () async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    await File(
      '${fixtureCopy.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$legacyRemarkDatabaseFileName',
    ).delete();
    final legacyLayout = StorageLayout.legacy(
      documentsDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}documents',
      ),
      supportDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}support',
      ),
    );
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    await staging.copyLegacyDatabases(legacyLayout: legacyLayout);
    final reader = LegacyIsarReader(
      stagingRoot: staging.attemptDirectory,
      mainDatabaseCopy: staging.mainDatabaseCopy,
    );
    addTearDown(reader.close);
    await reader.open();

    expect(await reader.readBookRemarks().toList(), isEmpty);
    expect(await reader.readBooks().expand((batch) => batch).length, 2);
  });

  test('close is idempotent and reading after close throws', () async {
    final reader = await stagingReaderFromFixture();
    await reader.open();
    await reader.close();
    expect(reader.isOpen, isFalse);
    await reader.close();

    await expectLater(reader.readBooks().toList(), throwsStateError);
  });

  test('probe accepts the real fixture copy and rejects garbage', () async {
    final reader = await stagingReaderFromFixture();
    expect(
      await LegacyIsarReader.probeCopy(
        stagingRoot: reader.stagingRoot,
        mainDatabaseCopy: File(
          '${reader.stagingRoot.path}'
          '${Platform.pathSeparator}$legacyMainDatabaseFileName',
        ),
        remarkDatabaseCopy: File(
          '${reader.stagingRoot.path}'
          '${Platform.pathSeparator}$legacyRemarkDatabaseFileName',
        ),
      ),
      isTrue,
    );

    final fakeRoot = Directory(
      '${tempRoot.path}${Platform.pathSeparator}fake',
    )..createSync(recursive: true);
    final fakeMain = File(
      '${fakeRoot.path}${Platform.pathSeparator}$legacyMainDatabaseFileName',
    );
    await fakeMain.writeAsBytes(List<int>.generate(8192, (i) => i % 253));
    expect(
      await LegacyIsarReader.probeCopy(
        stagingRoot: fakeRoot,
        mainDatabaseCopy: fakeMain,
      ),
      isFalse,
    );
  });
}

void expectIdsAscending(Iterable<int> ids) {
  final list = ids.toList();
  for (var index = 1; index < list.length; index++) {
    expect(list[index] > list[index - 1], isTrue, reason: 'ids: $list');
  }
}
