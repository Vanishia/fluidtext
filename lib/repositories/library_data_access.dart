import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../db/isar_db.dart';
import '../models/book_remark.dart';
import '../services/backup/backup_export_service.dart';
import '../services/book_asset_store.dart';
import '../services/book_import_service.dart';
import '../storage/sqlite/library_database.dart';
import '../storage/sqlite/sqlite_library_repository.dart';
import '../storage/storage_layout.dart';
import 'book_card_repository.dart';
import 'library_repository.dart';

class LibraryDataAccess {
  LibraryDataAccess._({required this.repository});

  /// Wraps an arbitrary repository without touching the singleton. Only for
  /// widget tests that inject a fake repository into UI code.
  @visibleForTesting
  factory LibraryDataAccess.forTesting(LibraryRepository repository) {
    return LibraryDataAccess._(repository: repository);
  }

  static Future<LibraryDataAccess>? _instanceFuture;

  /// Rollback switch: force the legacy Isar repository (and legacy runtime
  /// layout) regardless of migration state.
  static const forceIsarLibrary = bool.fromEnvironment(
    'FLUIDTEXT_FORCE_ISAR_LIBRARY',
  );

  /// Legacy opt-in switch from the pre-migration development phase; still
  /// honoured as "force SQLite".
  static const _sqliteRepositoryEnabled = bool.fromEnvironment(
    'FLUIDTEXT_USE_SQLITE_LIBRARY',
  );

  static Future<LibraryDataAccess> get instance => _instanceFuture ??= _open();

  /// Whether the singleton has been opened. Only for tests.
  @visibleForTesting
  static bool get isInitialized => _instanceFuture != null;

  final LibraryRepository repository;
  var _closed = false;

  static Future<LibraryDataAccess> _open() async {
    if (!forceIsarLibrary || _sqliteRepositoryEnabled) {
      final layoutProvider = AppStorageResolver.activeRuntimeLayout;
      final database = await openLibraryDatabaseForLayout(layoutProvider);
      final assetStore = BookAssetStore(storageLayout: layoutProvider);
      return LibraryDataAccess._(
        repository: SqliteLibraryRepository(database, assetStore: assetStore),
      );
    }

    final isar = await IsarDb.instance.isar;
    final remarkIsar = await _openLegacyRemarkIsar();
    final repository = BookCardRepository(isar, remarkIsar: remarkIsar);
    return LibraryDataAccess._(repository: repository);
  }

  static Future<Isar> _openLegacyRemarkIsar() async {
    final layout = await AppStorageResolver.legacyRuntimeLayout();
    return Isar.open(
      [BookRemarkSchema],
      directory: layout.bookRemarkDatabaseDirectory.path,
      name: 'book_remarks',
      inspector: true,
    );
  }

  Future<BookImportResult> importEpubBytes({
    required Uint8List bytes,
    String? sourceFileName,
    int targetCharsPerCard = 300,
  }) {
    return BookImportService().importEpubBytes(
      repository: repository,
      bytes: bytes,
      sourceFileName: sourceFileName,
      targetCharsPerCard: targetCharsPerCard,
    );
  }

  /// Exports a full v3 backup archive. Works for both the SQLite repository
  /// and the forced-Isar rollback path because the snapshot DTO is
  /// backend-neutral; the picker flow lives here, not in the export service.
  Future<String?> exportBackup() async {
    final backup = await const BackupExportService().exportV3(
      repository: repository,
      layout: await AppStorageResolver.activeRuntimeLayout(),
    );
    return FilePicker.platform.saveFile(
      dialogTitle: '导出 FluidText 备份',
      fileName: backup.fileName,
      type: FileType.custom,
      allowedExtensions: [backup.extension],
      bytes: backup.bytes,
    );
  }

  Future<Map<int, String>> loadRemarks() {
    return repository.loadRemarks();
  }

  Future<void> saveRemark(int bookId, String remark) {
    return repository.saveRemark(bookId, remark);
  }

  Future<void> removeRemark(int bookId) {
    return repository.removeRemark(bookId);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(await _instanceFuture, this)) {
      _instanceFuture = null;
    }
    await repository.close();
  }
}
