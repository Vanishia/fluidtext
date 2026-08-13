import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/legacy_source.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/models/book_remark.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/storage_layout.dart';
import 'package:isar/isar.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;
  late Directory fixtureCopy;
  late StorageLayout legacyLayout;
  late StorageLayout targetLayout;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-migrator-test-',
    );
    fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    legacyLayout = StorageLayout.legacy(
      documentsDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}documents',
      ),
      supportDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}support',
      ),
    );
    targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
    // The checked-in fixture stores absolute paths into the original fixture
    // location; point them at this temp copy so tests are hermetic.
    await _rewriteJsonPath(
      legacyLayout.readerBackgroundSettingsFile,
      'imagePath',
      '${legacyLayout.readerBackgroundsDirectory.path}'
      '${Platform.pathSeparator}legacy_background.png',
    );
    await _rewriteJsonPath(
      legacyLayout.appFontSettingsFile,
      'fontPath',
      '${legacyLayout.appFontsDirectory.path}'
      '${Platform.pathSeparator}legacy.ttf',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  const detection = LegacySourceDetection(
    status: LegacySourceStatus.trusted,
    companionSignals: ['book_remarks.isar'],
    sourceFingerprint: 'test-fingerprint',
  );

  Future<(MigrationResult, List<MigrationProgressEvent>)> runMigration({
    int batchSize = 500,
  }) async {
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    final events = <MigrationProgressEvent>[];
    final result = await LibraryMigrator(
      batchSize: batchSize,
      onProgress: events.add,
    ).migrate(
      detection: detection,
      legacyLayout: legacyLayout,
      staging: staging,
    );
    return (result, events);
  }

  test('end to end migration preserves ids, flags, times and resources', () async {
    final (result, events) = await runMigration(batchSize: 1);

    expect(result.bookCount, 2);
    expect(result.cardCount, 3);
    expect(result.assetCount, 1);
    expect(result.remarkCount, 2);
    expect(result.warnings, isEmpty);
    expect(result.sourceFingerprint, 'test-fingerprint');

    final database = LibraryDatabase.file(result.staging.payloadDatabaseFile);
    addTearDown(database.close);
    expect(await database.integrityCheck(), ['ok']);
    expect(await database.foreignKeyCheck(), isEmpty);

    // Compare every row against the legacy source.
    final mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: legacyLayout.libraryDatabaseDirectory.path,
      inspector: false,
    );
    final remarkIsar = await Isar.open(
      [BookRemarkSchema],
      directory: legacyLayout.bookRemarkDatabaseDirectory.path,
      name: 'book_remarks',
      inspector: false,
    );
    addTearDown(() async {
      await mainIsar.close();
      await remarkIsar.close();
    });

    final sourceBooks = await mainIsar.books.where().findAll();
    final bookRows = await database
        .customSelect('SELECT * FROM books ORDER BY id')
        .get();
    expect(bookRows, hasLength(sourceBooks.length));
    for (var index = 0; index < sourceBooks.length; index++) {
      final book = sourceBooks[index];
      final row = bookRows[index];
      expect(row.read<int>('id'), book.id);
      expect(row.read<String>('title'), book.title);
      expect(
        row.read<int>('created_at_ms'),
        book.createdAt.millisecondsSinceEpoch,
      );
      expect(row.read<String?>('asset_root_key'), book.assetRootKey);
      expect(row.read<String?>('file_hash'), book.fileHash);
    }

    final sourceCards = (await mainIsar.bookCards.where().findAll())
      ..sort((a, b) {
        final byBook = a.bookId.compareTo(b.bookId);
        return byBook != 0 ? byBook : a.cardIndex.compareTo(b.cardIndex);
      });
    final cardRows = await database
        .customSelect(
          'SELECT * FROM book_cards ORDER BY book_id, card_index',
        )
        .get();
    expect(cardRows, hasLength(sourceCards.length));
    for (var index = 0; index < sourceCards.length; index++) {
      final card = sourceCards[index];
      final row = cardRows[index];
      expect(row.read<int>('id'), card.id);
      expect(row.read<int>('book_id'), card.bookId);
      expect(row.read<int>('card_index'), card.cardIndex);
      expect(row.read<String>('content'), card.content);
      expect(row.read<int>('is_read'), card.isRead ? 1 : 0);
      expect(row.read<int>('is_favorite'), card.isFavorite ? 1 : 0);
      expect(
        row.read<int?>('read_at_ms'),
        card.isRead ? card.readAt?.millisecondsSinceEpoch : null,
      );
      expect(
        row.read<int?>('favorited_at_ms'),
        card.isFavorite ? card.favoritedAt?.millisecondsSinceEpoch : null,
      );
    }

    final remarkRows = await database
        .customSelect('SELECT * FROM book_remarks ORDER BY book_id')
        .get();
    final sourceRemarks = (await remarkIsar.bookRemarks.where().findAll())
      ..sort((a, b) => a.id.compareTo(b.id));
    expect(remarkRows, hasLength(sourceRemarks.length));
    for (var index = 0; index < sourceRemarks.length; index++) {
      expect(remarkRows[index].read<int>('book_id'), sourceRemarks[index].id);
      expect(remarkRows[index].read<String>('title'), sourceRemarks[index].title);
      expect(
        remarkRows[index].read<int>('updated_at_ms'),
        sourceRemarks[index].updatedAt.millisecondsSinceEpoch,
      );
    }

    // Resource copy with matching SHA-256.
    const coverKey = 'book_assets/asset_fixture_one/images/cover.png';
    final sourceCover = File(
      '${legacyLayout.bookAssetsDirectory.path}'
      '${Platform.pathSeparator}asset_fixture_one'
      '${Platform.pathSeparator}images${Platform.pathSeparator}cover.png',
    );
    final expectedHash = sha256.convert(await sourceCover.readAsBytes());
    expect(result.copiedResourceHashes[coverKey], expectedHash.toString());
    final copiedCover = File(
      '${result.staging.payloadDirectory.path}'
      '${Platform.pathSeparator}book_assets'
      '${Platform.pathSeparator}asset_fixture_one'
      '${Platform.pathSeparator}images${Platform.pathSeparator}cover.png',
    );
    expect(await copiedCover.exists(), isTrue);

    // Settings migrated into payload/settings/.
    final settingsDir = result.staging.payloadSettingsDirectory;
    for (final name in [
      StorageLayout.appBehaviorSettingsFileName,
      StorageLayout.readerSessionFileName,
      StorageLayout.readerBackgroundSettingsFileName,
      StorageLayout.appFontSettingsFileName,
    ]) {
      expect(
        await File(
          '${settingsDir.path}${Platform.pathSeparator}$name',
        ).exists(),
        isTrue,
        reason: name,
      );
    }
    final background =
        jsonDecode(
              await File(
                '${settingsDir.path}${Platform.pathSeparator}'
                '${StorageLayout.readerBackgroundSettingsFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(background['source'], 'image');
    expect(background['imagePath'], 'reader_backgrounds/legacy_background.png');
    final font =
        jsonDecode(
              await File(
                '${settingsDir.path}${Platform.pathSeparator}'
                '${StorageLayout.appFontSettingsFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(font['source'], 'custom');
    expect(font['fontPath'], 'app_fonts/legacy.ttf');
    final session =
        jsonDecode(
              await File(
                '${settingsDir.path}${Platform.pathSeparator}'
                '${StorageLayout.readerSessionFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], [1, 2]);

    // Progress: phases never move backwards, card counts are monotonic and
    // reach the total.
    final phases = events.map((event) => event.phase.index).toList();
    for (var index = 1; index < phases.length; index++) {
      expect(phases[index] >= phases[index - 1], isTrue, reason: '$events');
    }
    expect(phases.first, MigrationPhase.copyingDatabase.index);
    expect(phases.last, MigrationPhase.migratingSettings.index);
    final cardEvents = events
        .where((event) => event.phase == MigrationPhase.migratingCards)
        .toList();
    expect(cardEvents, isNotEmpty);
    for (var index = 1; index < cardEvents.length; index++) {
      expect(cardEvents[index].completed >= cardEvents[index - 1].completed,
          isTrue);
    }
    expect(cardEvents.last.completed, 3);
    expect(cardEvents.last.total, 3);
    final copyEvents = events
        .where((event) => event.phase == MigrationPhase.copyingDatabase)
        .toList();
    expect(copyEvents.last.fraction, 1.0);
  });

  test('reader session filters book ids that were not migrated', () async {
    await legacyLayout.readerSessionFile.writeAsString(
      jsonEncode({'lastOpenedBookIds': [1, 2, 999]}),
    );

    final (result, _) = await runMigration();

    final session =
        jsonDecode(
              await File(
                '${result.staging.payloadSettingsDirectory.path}'
                '${Platform.pathSeparator}'
                '${StorageLayout.readerSessionFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], [1, 2]);
  });

  test('background image pointing at a missing file falls back to color', () async {
    await _rewriteJsonPath(
      legacyLayout.readerBackgroundSettingsFile,
      'imagePath',
      '${legacyLayout.readerBackgroundsDirectory.path}'
      '${Platform.pathSeparator}missing.png',
    );

    final (result, _) = await runMigration();

    final background =
        jsonDecode(
              await File(
                '${result.staging.payloadSettingsDirectory.path}'
                '${Platform.pathSeparator}'
                '${StorageLayout.readerBackgroundSettingsFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(background['source'], 'color');
    expect(background['imagePath'], isNull);
    expect(
      result.warnings.any((warning) => warning.contains('阅读背景图片')),
      isTrue,
    );
  });

  test('font pointing at a missing file falls back to system', () async {
    await _rewriteJsonPath(
      legacyLayout.appFontSettingsFile,
      'fontPath',
      '${legacyLayout.appFontsDirectory.path}'
      '${Platform.pathSeparator}missing.ttf',
    );

    final (result, _) = await runMigration();

    final font =
        jsonDecode(
              await File(
                '${result.staging.payloadSettingsDirectory.path}'
                '${Platform.pathSeparator}'
                '${StorageLayout.appFontSettingsFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(font['source'], 'system');
    expect(font['fontPath'], isNull);
    expect(
      result.warnings.any((warning) => warning.contains('字体')),
      isTrue,
    );
  });

  test('corrupted settings JSON falls back to default without touching source',
      () async {
    final sessionFile = legacyLayout.readerSessionFile;
    const corrupted = '{"lastOpenedBookIds": [1, 2';
    await sessionFile.writeAsString(corrupted);

    final (result, _) = await runMigration();

    final session =
        jsonDecode(
              await File(
                '${result.staging.payloadSettingsDirectory.path}'
                '${Platform.pathSeparator}'
                '${StorageLayout.readerSessionFileName}',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], isEmpty);
    expect(
      result.warnings.any((warning) => warning.contains('阅读记录')),
      isTrue,
    );
    // The legacy file must not be modified.
    expect(await sessionFile.readAsString(), corrupted);
  });

  test('orphan remarks are skipped with a warning', () async {
    final remarkIsar = await Isar.open(
      [BookRemarkSchema],
      directory: legacyLayout.bookRemarkDatabaseDirectory.path,
      name: 'book_remarks',
      inspector: false,
    );
    await remarkIsar.writeTxn(() async {
      await remarkIsar.bookRemarks.put(
        BookRemark()
          ..id = 9999
          ..title = 'orphan remark'
          ..updatedAt = DateTime.now(),
      );
    });
    await remarkIsar.close();

    final (result, _) = await runMigration();

    expect(result.remarkCount, 2);
    expect(result.warnings.any((warning) => warning.contains('备注')), isTrue);
  });

  test('orphan assets are skipped with a warning', () async {
    final mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: legacyLayout.libraryDatabaseDirectory.path,
      inspector: false,
    );
    await mainIsar.writeTxn(() async {
      await mainIsar.bookAssets.put(
        BookAsset()
          ..bookId = 9999
          ..assetKey = 'orphan'
          ..relativePath = 'book_assets/orphan/images/x.png'
          ..createdAt = DateTime.now(),
      );
    });
    await mainIsar.close();

    final (result, _) = await runMigration();

    expect(result.assetCount, 1);
    expect(result.warnings.any((warning) => warning.contains('资源')), isTrue);
  });

  test('duplicate (bookId, cardIndex) fails and rolls back the transaction',
      () async {
    final mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: legacyLayout.libraryDatabaseDirectory.path,
      inspector: false,
    );
    final firstBook = (await mainIsar.books.where().findAll()).first;
    await mainIsar.writeTxn(() async {
      await mainIsar.bookCards.put(
        BookCard()
          ..bookId = firstBook.id
          ..bookTitle = firstBook.title
          ..cardIndex = 0
          ..chapterIndex = 0
          ..chapterCardIndex = 0
          ..content = 'duplicate card',
      );
    });
    await mainIsar.close();

    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    await expectLater(
      LibraryMigrator().migrate(
        detection: detection,
        legacyLayout: legacyLayout,
        staging: staging,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.migratingCards,
        ),
      ),
    );

    // The transaction rolled back: no partial book in the staging database.
    final database = LibraryDatabase.file(staging.payloadDatabaseFile);
    addTearDown(database.close);
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM books')
        .getSingle();
    expect(row.read<int>('c'), 0);
    final cardRow = await database
        .customSelect('SELECT COUNT(*) AS c FROM book_cards')
        .getSingle();
    expect(cardRow.read<int>('c'), 0);
  });

  test('card pointing at a missing book is a hard failure', () async {
    final mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: legacyLayout.libraryDatabaseDirectory.path,
      inspector: false,
    );
    await mainIsar.writeTxn(() async {
      await mainIsar.bookCards.put(
        BookCard()
          ..bookId = 9999
          ..bookTitle = 'ghost'
          ..cardIndex = 0
          ..chapterIndex = 0
          ..chapterCardIndex = 0
          ..content = 'orphan card',
      );
    });
    await mainIsar.close();

    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    await expectLater(
      LibraryMigrator().migrate(
        detection: detection,
        legacyLayout: legacyLayout,
        staging: staging,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.migratingCards,
        ),
      ),
    );
  });

  test('symlinked resource files are skipped with a warning', () async {
    final outside = File(
      '${tempRoot.path}${Platform.pathSeparator}outside.txt',
    );
    await outside.writeAsString('secret');
    final link = Link(
      '${legacyLayout.bookAssetsDirectory.path}'
      '${Platform.pathSeparator}linked.txt',
    );
    try {
      await link.create(outside.path);
    } on FileSystemException {
      // Creating symlinks on Windows requires elevated privileges or
      // developer mode; skip the assertions when unavailable.
      return;
    }

    final (result, _) = await runMigration();

    expect(
      result.warnings.any((warning) => warning.contains('符号链接')),
      isTrue,
    );
    expect(
      await File(
        '${result.staging.payloadDirectory.path}'
        '${Platform.pathSeparator}book_assets'
        '${Platform.pathSeparator}linked.txt',
      ).exists(),
      isFalse,
    );
  });
}

Future<void> _rewriteJsonPath(File file, String key, String value) async {
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  json[key] = value;
  await file.writeAsString(jsonEncode(json));
}
