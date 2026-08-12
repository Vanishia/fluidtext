import 'package:isar/isar.dart';

import '../models/book_remark.dart';
import '../repositories/library_change_tracker.dart';
import '../repositories/library_repository.dart';
import '../repositories/library_snapshot.dart';
import '../storage/storage_layout.dart';

class BookRemarkService implements RemarkRepository, BackupSnapshotRepository {
  BookRemarkService({
    StorageLayoutProvider? storageLayout,
    LibraryChangeTracker? changeTracker,
  }) : _storageLayout = storageLayout ?? AppStorageResolver.legacyRuntimeLayout,
       _changeTracker = changeTracker ?? LibraryChangeTracker.instance;

  static final instance = BookRemarkService();
  static const _isarName = 'book_remarks';

  final StorageLayoutProvider _storageLayout;
  final LibraryChangeTracker _changeTracker;
  Isar? _isar;

  Future<Map<int, String>> load() => loadRemarks();

  @override
  Future<Map<int, String>> loadRemarks() async {
    final isar = await _db;
    final remarks = await isar.bookRemarks.where().findAll();
    return {
      for (final remark in remarks)
        if (remark.title.trim().isNotEmpty) remark.id: remark.title.trim(),
    };
  }

  Future<List<Map<String, dynamic>>> exportJson() async {
    final snapshot = await buildBackupSnapshot();
    return snapshot.bookRemarks
        .map(
          (remark) => {
            'id': remark.bookId,
            'title': remark.title,
            'updatedAt': remark.updatedAt.toIso8601String(),
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveRemark(int bookId, String remark) async {
    final isar = await _db;
    final trimmed = remark.trim();
    await isar.writeTxn(() async {
      if (trimmed.isEmpty) {
        await isar.bookRemarks.delete(bookId);
        return;
      }

      await isar.bookRemarks.put(
        BookRemark()
          ..id = bookId
          ..title = trimmed
          ..updatedAt = DateTime.now(),
      );
    });
    _changeTracker.markChanged();
  }

  @override
  Future<void> removeRemark(int bookId) async {
    final isar = await _db;
    final deleted = await isar.writeTxn(() => isar.bookRemarks.delete(bookId));
    if (deleted) {
      _changeTracker.markChanged();
    }
  }

  @override
  Future<LibraryBackupSnapshot> buildBackupSnapshot() async {
    final isar = await _db;
    final remarks = await isar.bookRemarks.where().findAll();
    return LibraryBackupSnapshot(
      books: const [],
      bookCards: const [],
      bookAssets: const [],
      bookRemarks: remarks
          .map(
            (remark) => BookRemarkSnapshot(
              bookId: remark.id,
              title: remark.title,
              updatedAt: remark.updatedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }

  Future<Isar> get _db async {
    final existing = _isar;
    if (existing != null && existing.isOpen) return existing;

    final layout = await _storageLayout();
    final opened = await Isar.open(
      [BookRemarkSchema],
      directory: layout.bookRemarkDatabaseDirectory.path,
      name: _isarName,
      inspector: true,
    );
    _isar = opened;
    return opened;
  }
}
