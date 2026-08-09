import 'dart:typed_data';

import '../db/isar_db.dart';
import '../services/book_import_service.dart';
import '../services/data_backup_service.dart';
import 'book_card_repository.dart';
import 'library_repository.dart';

class LibraryDataAccess {
  LibraryDataAccess._(this.repository, this._isarRepository);

  static Future<LibraryDataAccess>? _instanceFuture;

  static Future<LibraryDataAccess> get instance => _instanceFuture ??= _open();

  final LibraryRepository repository;
  final BookCardRepository _isarRepository;

  static Future<LibraryDataAccess> _open() async {
    final isar = await IsarDb.instance.isar;
    final repository = BookCardRepository(isar);
    return LibraryDataAccess._(repository, repository);
  }

  Future<BookImportResult> importEpubBytes({
    required Uint8List bytes,
    String? sourceFileName,
    int targetCharsPerCard = 300,
  }) {
    return BookImportService().importEpubBytes(
      isar: _isarRepository.isar,
      bytes: bytes,
      sourceFileName: sourceFileName,
      targetCharsPerCard: targetCharsPerCard,
    );
  }

  Future<String?> exportBackup() {
    return const DataBackupService().exportBackup(_isarRepository.isar);
  }
}
