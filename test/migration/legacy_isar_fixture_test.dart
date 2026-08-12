import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/models/book_remark.dart';
import 'package:fluidtext/storage/storage_layout.dart';
import 'package:isar/isar.dart';

import '../support/isar_test_core.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  test('1.0.0 legacy fixture opens with expected counts and fields', () async {
    final fixtureRoot = Directory('test/fixtures/legacy_isar_1_0_0');
    expect(await fixtureRoot.exists(), isTrue);

    final tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-fixture-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    await _copyDirectory(fixtureRoot, tempRoot);

    final manifest =
        jsonDecode(
              await File(
                '${tempRoot.path}${Platform.pathSeparator}manifest.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final expected = manifest['expected'] as Map<String, dynamic>;
    final documentsDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}documents',
    );
    final supportDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}support',
    );
    final layout = StorageLayout.legacy(
      documentsDirectory: documentsDirectory,
      supportDirectory: supportDirectory,
    );

    final mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: layout.libraryDatabaseDirectory.path,
      inspector: false,
    );
    final remarkIsar = await Isar.open(
      [BookRemarkSchema],
      directory: layout.bookRemarkDatabaseDirectory.path,
      name: 'book_remarks',
      inspector: false,
    );
    addTearDown(() async {
      await mainIsar.close();
      await remarkIsar.close();
    });

    final books = (await mainIsar.books.where().findAll())
      ..sort((left, right) => left.id.compareTo(right.id));
    final cards = (await mainIsar.bookCards.where().findAll())
      ..sort((left, right) => left.id.compareTo(right.id));
    final assets = (await mainIsar.bookAssets.where().findAll())
      ..sort((left, right) => left.id.compareTo(right.id));
    final remarks = (await remarkIsar.bookRemarks.where().findAll())
      ..sort((left, right) => left.id.compareTo(right.id));

    expect(manifest['format'], 'fluidtext.legacy_fixture');
    expect(manifest['sourceVersion'], '1.0.0');
    expect(books, hasLength(expected['books'] as int));
    expect(cards, hasLength(expected['bookCards'] as int));
    expect(assets, hasLength(expected['bookAssets'] as int));
    expect(remarks, hasLength(expected['bookRemarks'] as int));

    expect(books.first.title, 'Legacy Fixture One');
    expect(books.first.assetRootKey, 'asset_fixture_one');
    expect(cards[1].isRead, isTrue);
    expect(cards[1].isFavorite, isTrue);
    expect(
      assets.single.relativePath,
      'book_assets/asset_fixture_one/images/cover.png',
    );
    expect(remarks.first.title, 'Pinned legacy title');

    final sessionJson =
        jsonDecode(await layout.readerSessionFile.readAsString())
            as Map<String, dynamic>;
    expect(sessionJson['lastOpenedBookIds'], expected['lastOpenedBookIds']);
    expect(await layout.readerBackgroundSettingsFile.exists(), isTrue);
    expect(await layout.appFontSettingsFile.exists(), isTrue);
  });
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(
    recursive: false,
    followLinks: false,
  )) {
    final targetPath =
        '${target.path}${Platform.pathSeparator}${_basename(entity.path)}';
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(targetPath));
    } else if (entity is File) {
      await entity.copy(targetPath);
    }
  }
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
