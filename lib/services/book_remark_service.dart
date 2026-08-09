import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book_remark.dart';
import '../repositories/library_change_tracker.dart';

class BookRemarkService {
  BookRemarkService._();

  static final instance = BookRemarkService._();
  static const _isarName = 'book_remarks';

  Isar? _isar;

  Future<Map<int, String>> load() async {
    final isar = await _db;
    final remarks = await isar.bookRemarks.where().findAll();
    return {
      for (final remark in remarks)
        if (remark.title.trim().isNotEmpty) remark.id: remark.title.trim(),
    };
  }

  Future<List<Map<String, dynamic>>> exportJson() async {
    final isar = await _db;
    return isar.bookRemarks.where().exportJson();
  }

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
    LibraryChangeTracker.instance.markChanged();
  }

  Future<void> removeRemark(int bookId) async {
    final isar = await _db;
    final deleted = await isar.writeTxn(() => isar.bookRemarks.delete(bookId));
    if (deleted) {
      LibraryChangeTracker.instance.markChanged();
    }
  }

  Future<Isar> get _db async {
    final existing = _isar;
    if (existing != null) return existing;

    final dir = await getApplicationDocumentsDirectory();
    final opened = await Isar.open(
      [BookRemarkSchema],
      directory: dir.path,
      name: _isarName,
      inspector: true,
    );
    _isar = opened;
    return opened;
  }
}
