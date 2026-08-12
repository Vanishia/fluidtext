import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/book_card_repository.dart';
import 'package:fluidtext/services/book_asset_store.dart';
import 'package:fluidtext/services/book_import_service.dart';
import 'package:fluidtext/services/data_backup_service.dart';
import 'package:isar/isar.dart';

import '../support/epub_fixture.dart';
import '../support/isar_test_core.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  test(
    'backup archive contains database payload and referenced image',
    () async {
      final databaseDirectory = await Directory.systemTemp.createTemp(
        'fluidtext-backup-db-',
      );
      final documentsDirectory = await Directory.systemTemp.createTemp(
        'fluidtext-backup-docs-',
      );
      final isar = await Isar.open(
        [BookSchema, BookAssetSchema, BookCardSchema],
        directory: databaseDirectory.path,
        name: 'backup_${DateTime.now().microsecondsSinceEpoch}',
        inspector: false,
      );
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        if (await databaseDirectory.exists()) {
          await databaseDirectory.delete(recursive: true);
        }
        if (await documentsDirectory.exists()) {
          await documentsDirectory.delete(recursive: true);
        }
      });

      final assetStore = BookAssetStore(
        documentsDirectory: () async => documentsDirectory,
      );
      final repository = BookCardRepository(isar, assetStore: assetStore);
      final imported = await BookImportService(
        assetStore: assetStore,
      ).importEpubBytes(repository: repository, bytes: buildTestEpub());
      final backup =
          await DataBackupService(
            assetStore: assetStore,
            remarksExporter: () async => const [],
            readerSessionExporter: () async => null,
          ).buildBackup(
            repository,
            exportedAt: DateTime.utc(2026, 8, 9, 10, 11, 12),
          );

      expect(backup.extension, 'zip');
      final archive = ZipDecoder().decodeBytes(backup.bytes);
      final jsonEntry = archive.findFile('backup.json');
      expect(jsonEntry, isNotNull);
      final payload =
          jsonDecode(utf8.decode(jsonEntry!.content as List<int>))
              as Map<String, dynamic>;
      expect(payload['format'], 'fluidtext.backup');
      expect(payload['version'], DataBackupService.backupFormatVersion);
      expect((payload['books'] as List), hasLength(1));
      expect((payload['bookCards'] as List), isNotEmpty);

      final assets = payload['bookAssets'] as List<dynamic>;
      expect(assets, hasLength(1));
      final asset = assets.single as Map<String, dynamic>;
      final relativePath = asset['relativePath'] as String;
      final imageEntry = archive.findFile(relativePath.replaceAll(r'\', '/'));
      expect(imageEntry, isNotNull);
      expect((imageEntry!.content as List<int>), isNotEmpty);
      expect((payload['books'] as List).single['id'], imported.bookId);
    },
  );
}
