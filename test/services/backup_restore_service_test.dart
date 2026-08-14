import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/migration_progress.dart' show MigrationPhase;
import 'package:fluidtext/migration/migration_promotion.dart';
import 'package:fluidtext/migration/migration_state.dart';
import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/services/backup/backup_export_service.dart';
import 'package:fluidtext/services/backup/backup_format.dart';
import 'package:fluidtext/services/backup/backup_restore_service.dart';
import 'package:fluidtext/services/data_backup_service.dart' show BackupFile;
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';
import 'package:fluidtext/storage/storage_layout.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluidtext-restore-test-');
  });

  tearDown(() async {
    // The SQLite background isolate may still hold or concurrently remove
    // sidecar files right after close; retry briefly before giving up.
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  StorageLayout layoutFor(String name) {
    return StorageLayout.modern(
      rootDirectory: Directory('${tempDir.path}/$name'),
    );
  }

  final bookCreatedAt = DateTime.utc(2026, 1, 1);
  final bookImportedAt = DateTime.utc(2026, 1, 2);
  final cardReadAt = DateTime.utc(2026, 2, 1);
  final cardFavoritedAt = DateTime.utc(2026, 2, 2);
  final remarkUpdatedAt = DateTime.utc(2026, 3, 1);

  const assetRelativePath = 'book_assets/asset_root_1/images/img1.png';
  final assetBytes = List<int>.generate(64, (index) => index * 3 % 256);

  Future<void> seedDatabase(File databaseFile) async {
    final database = LibraryDatabase.file(databaseFile);
    try {
      await database.batch((batch) {
        batch.insertAll(database.sqliteBooks, [
          SqliteBooksCompanion.insert(
            id: const Value(1),
            title: '第一本书',
            createdAtMs: bookCreatedAt.millisecondsSinceEpoch,
            fileHash: const Value('hash1'),
            contentFingerprint: const Value('fp1'),
            sourceFileName: const Value('a.epub'),
            importedAtMs: Value(bookImportedAt.millisecondsSinceEpoch),
            cardCount: const Value(2),
            textCharCount: const Value(20),
            assetRootKey: const Value('asset_root_1'),
          ),
        ]);
        batch.insertAll(database.sqliteBookCards, [
          SqliteBookCardsCompanion.insert(
            id: const Value(10),
            bookId: 1,
            bookTitle: '第一本书',
            cardIndex: 0,
            chapterIndex: 0,
            chapterCardIndex: 0,
            content: '第一章内容',
            isRead: true,
            readAtMs: Value(cardReadAt.millisecondsSinceEpoch),
            isFavorite: false,
          ),
          SqliteBookCardsCompanion.insert(
            id: const Value(11),
            bookId: 1,
            bookTitle: '第一本书',
            cardIndex: 1,
            chapterIndex: 0,
            chapterCardIndex: 1,
            chapterTitle: const Value('第一章'),
            content: '第二章内容',
            blocksJson: const Value('[{"type":"text"}]'),
            isRead: false,
            isFavorite: true,
            favoritedAtMs: Value(cardFavoritedAt.millisecondsSinceEpoch),
          ),
        ]);
        batch.insertAll(database.sqliteBookAssets, [
          SqliteBookAssetsCompanion.insert(
            id: const Value(20),
            bookId: 1,
            assetKey: 'img1',
            originalHref: const Value('images/img1.png'),
            normalizedHref: const Value('images/img1.png'),
            mimeType: const Value('image/png'),
            relativePath: assetRelativePath,
            byteLength: Value(assetBytes.length),
            createdAtMs: bookCreatedAt.millisecondsSinceEpoch,
          ),
        ]);
        batch.insertAll(database.sqliteBookRemarks, [
          SqliteBookRemarksCompanion.insert(
            bookId: const Value(1),
            title: '这本书的备注',
            updatedAtMs: remarkUpdatedAt.millisecondsSinceEpoch,
          ),
        ]);
      });
    } finally {
      await database.close();
    }
  }

  Future<LibraryBackupSnapshot> snapshotOf(File databaseFile) async {
    final database = LibraryDatabase.file(databaseFile);
    try {
      return await SqliteLibraryRepository(database).buildBackupSnapshot();
    } finally {
      await database.close();
    }
  }

  /// Builds the v2 payload JSON (header + library records) from a snapshot.
  Map<String, dynamic> v2Payload(
    LibraryBackupSnapshot snapshot, {
    Map<String, dynamic>? readerSession,
    List<Map<String, dynamic>>? extraRemarks,
    List<Map<String, dynamic>>? extraAssets,
  }) {
    final data = BackupLibraryData.fromSnapshot(
      snapshot,
      readerSession: readerSession,
    ).toLibraryJson();
    if (extraRemarks != null) {
      data['bookRemarks'] = <dynamic>[
        ...data['bookRemarks'] as List<dynamic>,
        ...extraRemarks,
      ];
    }
    if (extraAssets != null) {
      data['bookAssets'] = <dynamic>[
        ...data['bookAssets'] as List<dynamic>,
        ...extraAssets,
      ];
    }
    return <String, dynamic>{
      'format': 'fluidtext.backup',
      'version': 2,
      'exportedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
      ...data,
    };
  }

  Future<File> writeJson(String name, Map<String, dynamic> payload) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  Future<File> writeZip(String name, Map<String, List<int>> files) async {
    final archive = Archive();
    files.forEach((entryName, bytes) {
      archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
    });
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return file;
  }

  var closeCalls = 0;
  Future<void> defaultClose() async {
    closeCalls++;
  }

  setUp(() => closeCalls = 0);

  test('v2 JSON restores into a fresh SQLite database', () async {
    final sourceLayout = layoutFor('source');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson('backup.json', v2Payload(snapshot));

    final targetLayout = layoutFor('target');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(closeCalls, 1);
    expect(result.formatVersion, 2);
    expect(result.bookCount, 1);
    expect(result.cardCount, 2);
    expect(result.assetCount, 1);
    expect(result.remarkCount, 1);
    expect(result.settingsIncluded, isFalse);
    expect(result.warnings, contains(contains('旧版备份')));

    // The sealed database has no WAL sidecars and the attempt was cleaned up
    // (checked before reopening the database, which would recreate them).
    expect(
      await File('${targetLayout.sqliteDatabaseFile.path}-wal').exists(),
      isFalse,
    );
    final attempts = Directory(
      '${targetLayout.recoveryDirectory.path}/attempts',
    );
    if (await attempts.exists()) {
      expect(await attempts.list().toList(), isEmpty);
    }

    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.books.single.id, 1);
    expect(restored.books.single.title, '第一本书');
    expect(restored.books.single.fileHash, 'hash1');
    expect(restored.books.single.assetRootKey, 'asset_root_1');
    expect(
      restored.books.single.createdAt.millisecondsSinceEpoch,
      bookCreatedAt.millisecondsSinceEpoch,
    );
    expect(restored.bookCards.map((card) => card.id), [10, 11]);
    expect(restored.bookCards.map((card) => card.cardIndex), [0, 1]);
    expect(restored.bookCards.first.isRead, isTrue);
    expect(
      restored.bookCards.first.readAt?.millisecondsSinceEpoch,
      cardReadAt.millisecondsSinceEpoch,
    );
    expect(restored.bookCards.last.isFavorite, isTrue);
    expect(restored.bookCards.last.blocksJson, '[{"type":"text"}]');
    expect(restored.bookAssets.single.relativePath, assetRelativePath);
    expect(restored.bookRemarks.single.title, '这本书的备注');
  });

  test('v2 ZIP restores asset files byte-identically', () async {
    final sourceLayout = layoutFor('source2');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeZip('backup2.zip', <String, List<int>>{
      'backup.json': utf8.encode(jsonEncode(v2Payload(snapshot))),
      assetRelativePath: assetBytes,
    });

    final targetLayout = layoutFor('target2');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(result.assetCount, 1);
    final restoredAsset = File(
      '${targetLayout.rootDirectory.path}/$assetRelativePath',
    );
    expect(await restoredAsset.readAsBytes(), assetBytes);
    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.bookAssets.single.assetKey, 'img1');
  });

  test('v3 round-trip restores data, settings and managed files', () async {
    final sourceLayout = layoutFor('source3');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);

    // Managed files in the source layout.
    final sourceAsset = File(
      '${sourceLayout.rootDirectory.path}/$assetRelativePath',
    );
    await sourceAsset.parent.create(recursive: true);
    await sourceAsset.writeAsBytes(assetBytes, flush: true);
    await sourceLayout.settingsDirectory.create(recursive: true);
    await sourceLayout.readerSessionFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'lastOpenedBookIds': [1, 999],
        'savedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
      }),
    );
    await sourceLayout.readerBackgroundSettingsFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'source': 'image',
        'imagePath': 'reader_backgrounds/bg.png',
      }),
    );
    await sourceLayout.appFontSettingsFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'source': 'custom',
        'fontFamily': 'FluidTextUserFont_x',
        'fontPath': 'app_fonts/font.ttf',
      }),
    );
    await sourceLayout.appBehaviorSettingsFile.writeAsString(
      jsonEncode(<String, dynamic>{'themeMode': 'dark'}),
    );
    await sourceLayout.readerBackgroundsDirectory.create(recursive: true);
    await File(
      '${sourceLayout.readerBackgroundsDirectory.path}/bg.png',
    ).writeAsBytes(<int>[1, 2, 3], flush: true);
    await sourceLayout.appFontsDirectory.create(recursive: true);
    await File(
      '${sourceLayout.appFontsDirectory.path}/font.ttf',
    ).writeAsBytes(<int>[4, 5, 6], flush: true);

    final sourceDatabase = LibraryDatabase.file(
      sourceLayout.sqliteDatabaseFile,
    );
    final BackupFile backup;
    try {
      backup = await const BackupExportService().exportV3(
        repository: SqliteLibraryRepository(sourceDatabase),
        layout: sourceLayout,
        appVersion: '1.1.0+2',
        exportedAt: DateTime.utc(2026, 8, 2, 10, 30, 0),
      );
    } finally {
      await sourceDatabase.close();
    }
    expect(backup.extension, 'zip');
    expect(
      backup.fileName,
      matches(RegExp(r'^fluidtext-backup-\d{8}-\d{6}\.zip$')),
    );
    final backupFile = File('${tempDir.path}/v3.zip');
    await backupFile.writeAsBytes(backup.bytes, flush: true);

    final targetLayout = layoutFor('target3');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(result.formatVersion, 3);
    expect(result.settingsIncluded, isTrue);
    expect(result.bookCount, 1);
    expect(result.cardCount, 2);
    expect(result.assetCount, 1);
    expect(result.remarkCount, 1);

    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.books.single.title, '第一本书');
    expect(restored.bookCards, hasLength(2));
    expect(restored.bookAssets.single.assetKey, 'img1');
    expect(restored.bookRemarks.single.title, '这本书的备注');

    // Settings restored; session references filtered to existing books.
    final session =
        jsonDecode(await targetLayout.readerSessionFile.readAsString())
            as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], [1]);
    final background =
        jsonDecode(
              await targetLayout.readerBackgroundSettingsFile.readAsString(),
            )
            as Map<String, dynamic>;
    expect(background['imagePath'], 'reader_backgrounds/bg.png');
    expect(
      await File(
        '${targetLayout.readerBackgroundsDirectory.path}/bg.png',
      ).readAsBytes(),
      <int>[1, 2, 3],
    );
    expect(
      await File(
        '${targetLayout.appFontsDirectory.path}/font.ttf',
      ).readAsBytes(),
      <int>[4, 5, 6],
    );
    expect(
      await File(
        '${targetLayout.rootDirectory.path}/$assetRelativePath',
      ).readAsBytes(),
      assetBytes,
    );
    expect(
      jsonDecode(
        await targetLayout.appBehaviorSettingsFile.readAsString(),
      )['themeMode'],
      'dark',
    );
  });

  test('restore replaces an existing library completely', () async {
    final sourceLayout = layoutFor('source4');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson('backup4.json', v2Payload(snapshot));

    // Pre-populate the target with a different library and a stray file.
    final targetLayout = layoutFor('target4');
    await targetLayout.rootDirectory.create(recursive: true);
    final existingDatabase = LibraryDatabase.file(
      targetLayout.sqliteDatabaseFile,
    );
    await existingDatabase
        .into(existingDatabase.sqliteBooks)
        .insert(
          SqliteBooksCompanion.insert(
            id: const Value(500),
            title: '旧书',
            createdAtMs: DateTime.utc(2025).millisecondsSinceEpoch,
          ),
        );
    await existingDatabase.close();
    final stray = File(
      '${targetLayout.bookAssetsDirectory.path}/old/stray.txt',
    );
    await stray.parent.create(recursive: true);
    await stray.writeAsString('old', flush: true);
    await MigrationCompletion.write(
      targetLayout,
      MigrationCompletionMarker(
        source: MigrationCompletionMarker.sourceMigration,
        sourceFingerprint: 'fp',
        sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
        bookCount: 1,
        cardCount: 0,
        assetCount: 0,
        remarkCount: 0,
        verifiedResourceCount: 0,
        completedAt: DateTime.utc(2026, 7, 1),
      ),
    );

    await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.books.map((book) => book.id), [1]);
    expect(await stray.exists(), isFalse);

    // The completion marker counts are refreshed, source preserved.
    final marker = await MigrationCompletion.load(targetLayout);
    expect(marker, isNotNull);
    expect(marker!.bookCount, 1);
    expect(marker.cardCount, 2);
    expect(marker.assetCount, 1);
    expect(marker.remarkCount, 1);
    expect(marker.source, MigrationCompletionMarker.sourceMigration);
    expect(marker.sourceFingerprint, 'fp');
  });

  test(
    'a failing closeLiveDatabase leaves the original library intact',
    () async {
      final sourceLayout = layoutFor('source5');
      await sourceLayout.rootDirectory.create(recursive: true);
      await seedDatabase(sourceLayout.sqliteDatabaseFile);
      final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
      final backupFile = await writeJson('backup5.json', v2Payload(snapshot));

      final targetLayout = layoutFor('target5');
      await targetLayout.rootDirectory.create(recursive: true);
      final existingDatabase = LibraryDatabase.file(
        targetLayout.sqliteDatabaseFile,
      );
      await existingDatabase
          .into(existingDatabase.sqliteBooks)
          .insert(
            SqliteBooksCompanion.insert(
              id: const Value(500),
              title: '旧书',
              createdAtMs: DateTime.utc(2025).millisecondsSinceEpoch,
            ),
          );
      await existingDatabase.close();

      await expectLater(
        const BackupRestoreService().restore(
          backupFile: backupFile,
          targetLayout: targetLayout,
          closeLiveDatabase: () => throw StateError('模拟关闭失败'),
        ),
        throwsStateError,
      );

      final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
      expect(restored.books.map((book) => book.id), [500]);
    },
  );

  test(
    'a tampered v3 checksum is rejected before touching the library',
    () async {
      final sourceLayout = layoutFor('source6');
      await sourceLayout.rootDirectory.create(recursive: true);
      await seedDatabase(sourceLayout.sqliteDatabaseFile);
      final sourceDatabase = LibraryDatabase.file(
        sourceLayout.sqliteDatabaseFile,
      );
      final BackupFile backup;
      try {
        backup = await const BackupExportService().exportV3(
          repository: SqliteLibraryRepository(sourceDatabase),
          layout: sourceLayout,
        );
      } finally {
        await sourceDatabase.close();
      }

      // Re-encode the archive with a modified library.json.
      final decoded = ZipDecoder().decodeBytes(backup.bytes);
      final repacked = Archive();
      for (final file in decoded.files) {
        var content = file.content as List<int>;
        if (file.name == 'data/library.json') {
          content = utf8.encode(
            utf8.decode(content).replaceAll('第一本书', '被篡改的书'),
          );
        }
        repacked.addFile(ArchiveFile(file.name, content.length, content));
      }
      final tamperedFile = File('${tempDir.path}/tampered.zip');
      await tamperedFile.writeAsBytes(
        ZipEncoder().encode(repacked),
        flush: true,
      );

      final targetLayout = layoutFor('target6');
      await targetLayout.rootDirectory.create(recursive: true);
      await expectLater(
        const BackupRestoreService().restore(
          backupFile: tamperedFile,
          targetLayout: targetLayout,
          closeLiveDatabase: defaultClose,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('校验和不匹配'),
          ),
        ),
      );
      expect(closeCalls, 0);
      expect(await targetLayout.sqliteDatabaseFile.exists(), isFalse);
    },
  );

  test('reader session references to missing books are cleared', () async {
    final sourceLayout = layoutFor('source7');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson(
      'backup7.json',
      v2Payload(
        snapshot,
        readerSession: <String, dynamic>{
          'lastOpenedBookIds': [999],
          'savedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
        },
      ),
    );

    final targetLayout = layoutFor('target7');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(result.warnings, contains(contains('无效引用')));
    final session =
        jsonDecode(await targetLayout.readerSessionFile.readAsString())
            as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], isEmpty);
  });

  test('orphan remarks and assets are skipped with warnings', () async {
    final sourceLayout = layoutFor('source8');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson(
      'backup8.json',
      v2Payload(
        snapshot,
        extraRemarks: [
          <String, dynamic>{
            'id': 999,
            'title': '孤儿备注',
            'updatedAt': DateTime.utc(2026, 3, 2).toIso8601String(),
          },
        ],
        extraAssets: [
          <String, dynamic>{
            'id': 888,
            'bookId': 999,
            'assetKey': 'orphan',
            'originalHref': null,
            'normalizedHref': null,
            'mimeType': null,
            'relativePath': 'book_assets/asset_root_9/images/orphan.png',
            'byteLength': 1,
            'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          },
        ],
      ),
    );

    final targetLayout = layoutFor('target8');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(result.remarkCount, 1);
    expect(result.assetCount, 1);
    expect(result.warnings, contains(contains('备注（书籍 ID 999）')));
    expect(result.warnings, contains(contains('资源记录（ID 888）')));

    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.bookRemarks.map((remark) => remark.bookId), [1]);
    expect(restored.bookAssets.map((asset) => asset.id), [20]);
  });

  test('cards referencing missing books are rejected', () async {
    final sourceLayout = layoutFor('source9');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final payload = v2Payload(snapshot);
    (payload['bookCards'] as List)
            .cast<Map<String, dynamic>>()
            .first['bookId'] =
        777;
    final backupFile = await writeJson('backup9.json', payload);

    final targetLayout = layoutFor('target9');
    await targetLayout.rootDirectory.create(recursive: true);
    await expectLater(
      const BackupRestoreService().restore(
        backupFile: backupFile,
        targetLayout: targetLayout,
        closeLiveDatabase: defaultClose,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('不存在的书籍'),
        ),
      ),
    );
    expect(await targetLayout.sqliteDatabaseFile.exists(), isFalse);
  });

  test('legacy sentinel chapter fields are normalized to chapter 0', () async {
    final sourceLayout = layoutFor('source10');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final payload = v2Payload(snapshot);
    // Cards exported by app versions before chapter metadata existed carry
    // Isar's int64-min "unset" sentinel (observed on a real v2 backup).
    for (final card
        in (payload['bookCards'] as List).cast<Map<String, dynamic>>()) {
      card['chapterIndex'] = -9223372036854775808;
      card['chapterCardIndex'] = -9223372036854775808;
    }
    final backupFile = await writeJson('backup10.json', payload);

    final targetLayout = layoutFor('target10');
    await targetLayout.rootDirectory.create(recursive: true);
    final result = await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    expect(result.cardCount, 2);
    expect(result.warnings, contains(contains('第 0 章')));

    final restored = await snapshotOf(targetLayout.sqliteDatabaseFile);
    expect(restored.bookCards.map((card) => card.chapterIndex), [0, 0]);
    expect(restored.bookCards.map((card) => card.chapterCardIndex), [0, 0]);
  });

  test(
    'database write failures are sanitized and leak no card content',
    () async {
      final sourceLayout = layoutFor('source11');
      await sourceLayout.rootDirectory.create(recursive: true);
      await seedDatabase(sourceLayout.sqliteDatabaseFile);
      final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
      final payload = v2Payload(snapshot);
      // Passes app-level validation but violates CHECK(card_count >= 0).
      (payload['books'] as List)
              .cast<Map<String, dynamic>>()
              .first['cardCount'] =
          -5;
      final backupFile = await writeJson('backup11.json', payload);

      final targetLayout = layoutFor('target11');
      await targetLayout.rootDirectory.create(recursive: true);
      Object? failure;
      try {
        await const BackupRestoreService().restore(
          backupFile: backupFile,
          targetLayout: targetLayout,
          closeLiveDatabase: defaultClose,
        );
      } catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      final message = failure.toString();
      expect(message, contains('恢复数据写入数据库失败'));
      // The raw SqliteException tails (SQL statement + bound parameters,
      // including card content) must not reach user-facing messages.
      expect(message, isNot(contains('Causing statement')));
      expect(message, isNot(contains('第一章内容')));
      // Failed before closing/swapping the live database.
      expect(closeCalls, 0);
      expect(await targetLayout.sqliteDatabaseFile.exists(), isFalse);
    },
  );

  test('reports monotonic progress through the restore stages', () async {
    final sourceLayout = layoutFor('source12');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeZip('backup12.zip', <String, List<int>>{
      'backup.json': utf8.encode(jsonEncode(v2Payload(snapshot))),
      assetRelativePath: assetBytes,
    });

    final targetLayout = layoutFor('target12');
    await targetLayout.rootDirectory.create(recursive: true);
    final events = <BackupRestoreProgress>[];
    await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
      onProgress: events.add,
    );

    expect(events, isNotEmpty);
    expect(events.last.fraction, 1.0);
    for (var index = 1; index < events.length; index++) {
      expect(
        events[index].fraction,
        greaterThanOrEqualTo(events[index - 1].fraction),
        reason: 'progress must be monotonic: $events',
      );
    }
    final stages = events.map((event) => event.stage).toList();
    for (final expected in const [
      '正在校验压缩包',
      '正在解压备份',
      '正在解析备份数据',
      '正在校验备份数据',
      '正在写入书库',
      '正在恢复资源与设置',
      '正在密封数据库',
      '正在切换书库',
      '恢复完成',
    ]) {
      expect(
        stages.any((stage) => stage.startsWith(expected)),
        isTrue,
        reason: 'missing stage $expected in $stages',
      );
    }
  });

  test('restore without a prior marker writes an initial completion marker '
      'and settles the migration state', () async {
    final sourceLayout = layoutFor('source13');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson('backup13.json', v2Payload(snapshot));

    // Migration-page scenario: the target has neither a live database nor a
    // completion marker yet, and the last migration attempt failed.
    final targetLayout = layoutFor('target13');
    final stateStore = MigrationStateStore(targetLayout: targetLayout);
    await stateStore.markFailed(
      'attempt-1',
      MigrationPhase.migratingCards,
      '旧书库中存在重复的卡片序号，已停止迁移',
    );

    await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    // Without an initial marker the next launch would see a live database
    // with no marker and loop back into recovery.
    final marker = await MigrationCompletion.load(targetLayout);
    expect(marker, isNotNull);
    expect(marker!.source, MigrationCompletionMarker.sourceRestore);
    expect(marker.bookCount, 1);
    expect(marker.cardCount, 2);
    // A lingering failed state must not keep the app in recovery either.
    expect((await stateStore.load()).status, MigrationLifecycleStatus.idle);
  });

  test('restore with an existing marker keeps its source fingerprint',
      () async {
    final sourceLayout = layoutFor('source14');
    await sourceLayout.rootDirectory.create(recursive: true);
    await seedDatabase(sourceLayout.sqliteDatabaseFile);
    final snapshot = await snapshotOf(sourceLayout.sqliteDatabaseFile);
    final backupFile = await writeJson('backup14.json', v2Payload(snapshot));

    final targetLayout = layoutFor('target14');
    await targetLayout.rootDirectory.create(recursive: true);
    await MigrationCompletion.write(
      targetLayout,
      MigrationCompletionMarker(
        source: MigrationCompletionMarker.sourceMigration,
        sourceFingerprint: 'legacy-fingerprint',
        sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
        bookCount: 9,
        cardCount: 9,
        assetCount: 9,
        remarkCount: 9,
        verifiedResourceCount: 3,
        completedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    await const BackupRestoreService().restore(
      backupFile: backupFile,
      targetLayout: targetLayout,
      closeLiveDatabase: defaultClose,
    );

    final marker = await MigrationCompletion.load(targetLayout);
    expect(marker!.source, MigrationCompletionMarker.sourceMigration);
    expect(marker.sourceFingerprint, 'legacy-fingerprint');
    expect(marker.bookCount, 1, reason: 'counts must track the restore');
  });
}
