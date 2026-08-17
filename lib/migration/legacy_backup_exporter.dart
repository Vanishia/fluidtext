import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_remark.dart';
import '../repositories/book_card_repository.dart';
import '../services/book_asset_store.dart';
import '../services/data_backup_service.dart';
import '../storage/storage_layout.dart';
import 'legacy_isar_reader.dart';

/// Failure to build a legacy backup from staging copies.
class LegacyBackupException implements Exception {
  const LegacyBackupException(this.message);

  /// User-facing message (Chinese).
  final String message;

  @override
  String toString() => message;
}

/// Exports a v2 ZIP backup from copies of the legacy Isar databases
/// (plan 7.1): the original files in the legacy directory are never opened,
/// so no lock files are created there and the data is never modified.
class LegacyBackupExporter {
  const LegacyBackupExporter({
    required this.legacyLayout,
    this.backupService = const DataBackupService(),
  });

  final StorageLayout legacyLayout;

  /// Only used to encode the backup; asset resolution is overridden with a
  /// store bound to [legacyLayout].
  final DataBackupService backupService;

  /// Builds the backup file in memory from staging copies.
  Future<BackupFile> buildOnly() async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-backup-',
    );
    Isar? mainIsar;
    Isar? remarkIsar;
    try {
      final mainCopy = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        '$legacyMainDatabaseFileName',
      );
      final remarkCopy = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        '$legacyRemarkDatabaseFileName',
      );
      try {
        await File(
          StorageLayout.joinPath([
            legacyLayout.libraryDatabaseDirectory.path,
            legacyMainDatabaseFileName,
          ], separator: legacyLayout.pathSeparator),
        ).copy(mainCopy.path);
        final remarkSource = File(
          StorageLayout.joinPath([
            legacyLayout.bookRemarkDatabaseDirectory.path,
            legacyRemarkDatabaseFileName,
          ], separator: legacyLayout.pathSeparator),
        );
        final hasRemarks = await remarkSource.exists();
        if (hasRemarks) {
          await remarkSource.copy(remarkCopy.path);
        }

        mainIsar = await Isar.open(
          [BookSchema, BookAssetSchema, BookCardSchema],
          directory: tempDirectory.path,
          inspector: false,
        );
        if (hasRemarks) {
          remarkIsar = await Isar.open(
            [BookRemarkSchema],
            directory: tempDirectory.path,
            name: 'book_remarks',
            inspector: false,
          );
        }
      } catch (_) {
        throw const LegacyBackupException('无法读取旧数据库副本，旧数据未被修改。');
      }

      Future<StorageLayout> legacyProvider() async => legacyLayout;
      final repository = BookCardRepository(
        mainIsar,
        remarkIsar: remarkIsar,
        assetStore: BookAssetStore(storageLayout: legacyProvider),
      );
      final service = DataBackupService(
        assetStore: BookAssetStore(storageLayout: legacyProvider),
        readerSessionExporter: _readLegacySession,
      );
      return await service.buildBackup(repository);
    } finally {
      await mainIsar?.close();
      await remarkIsar?.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  /// Builds the backup and asks the user where to save it. Returns the saved
  /// path, or null when the user cancels.
  Future<String?> exportToPickedFile() async {
    final backup = await buildOnly();
    return FilePicker.platform.saveFile(
      dialogTitle: '导出 FluidText 备份',
      fileName: backup.fileName,
      type: FileType.custom,
      allowedExtensions: [backup.extension],
      bytes: backup.bytes,
    );
  }

  Future<Map<String, dynamic>?> _readLegacySession() async {
    try {
      final file = legacyLayout.readerSessionFile;
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
