import 'dart:typed_data';

import '../db/isar_db.dart';
import '../services/book_import_service.dart';
import '../services/data_backup_service.dart';
import '../storage/sqlite/library_database.dart';
import '../storage/sqlite/sqlite_library_repository.dart';
import '../storage/storage_layout.dart';
import 'book_card_repository.dart';
import 'library_repository.dart';

class LibraryDataAccess {
  LibraryDataAccess._({
    required this.repository,
    required BookCardRepository? isarRepository,
    LibraryDatabase? sqliteDatabase,
  }) : _isarRepository = isarRepository,
       _sqliteDatabase = sqliteDatabase;

  static Future<LibraryDataAccess>? _instanceFuture;
  static const _sqliteRepositoryEnabled = bool.fromEnvironment(
    'FLUIDTEXT_USE_SQLITE_LIBRARY',
  );

  static Future<LibraryDataAccess> get instance => _instanceFuture ??= _open();

  final LibraryRepository repository;
  final BookCardRepository? _isarRepository;
  final LibraryDatabase? _sqliteDatabase;

  static Future<LibraryDataAccess> _open() async {
    if (_sqliteRepositoryEnabled) {
      final database = await openLibraryDatabaseForLayout(
        AppStorageResolver.targetRuntimeLayout,
      );
      return LibraryDataAccess._(
        repository: SqliteLibraryRepository(database),
        isarRepository: null,
        sqliteDatabase: database,
      );
    }

    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    return LibraryDataAccess._(
      repository: repository,
      isarRepository: repository,
    );
  }

  Future<BookImportResult> importEpubBytes({
    required Uint8List bytes,
    String? sourceFileName,
    int targetCharsPerCard = 300,
  }) {
    final isarRepository = _isarRepository;
    if (isarRepository == null) {
      throw UnsupportedError(
        'SQLite import is not enabled before the phase 3 import abstraction.',
      );
    }
    return BookImportService().importEpubBytes(
      isar: isarRepository.isar,
      bytes: bytes,
      sourceFileName: sourceFileName,
      targetCharsPerCard: targetCharsPerCard,
    );
  }

  Future<String?> exportBackup() {
    final isarRepository = _isarRepository;
    if (isarRepository == null) {
      throw UnsupportedError(
        'SQLite backup export is not enabled before the phase 3 snapshot abstraction.',
      );
    }
    return const DataBackupService().exportBackup(isarRepository.isar);
  }

  Future<void> close() async {
    await _sqliteDatabase?.close();
  }
}
