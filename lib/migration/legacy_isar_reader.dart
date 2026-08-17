import 'dart:io';

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_remark.dart';
import '../storage/storage_layout.dart';

/// File name of the legacy main Isar database.
const legacyMainDatabaseFileName = 'default.isar';

/// File name of the legacy book remark Isar database.
const legacyRemarkDatabaseFileName = 'book_remarks.isar';

/// Read-only reader for legacy Isar staging copies.
///
/// The reader only opens copies that live inside an explicit staging root so
/// the original legacy databases are never touched. Records are streamed in
/// ascending-id batches to keep memory bounded and to allow later
/// id-preserving writes.
class LegacyIsarReader {
  LegacyIsarReader({
    required Directory stagingRoot,
    required File mainDatabaseCopy,
    File? remarkDatabaseCopy,
    this.batchSize = defaultBatchSize,
  }) : assert(batchSize > 0, 'batchSize must be positive'),
       assert(
         StoragePathSafety.isLexicallyWithinDirectory(
           directoryPath: stagingRoot.path,
           filePath: mainDatabaseCopy.path,
         ),
         'mainDatabaseCopy must be inside the staging root',
       ),
       assert(
         remarkDatabaseCopy == null ||
             StoragePathSafety.isLexicallyWithinDirectory(
               directoryPath: stagingRoot.path,
               filePath: remarkDatabaseCopy.path,
             ),
         'remarkDatabaseCopy must be inside the staging root',
       ),
       _stagingRoot = stagingRoot,
       _mainDatabaseCopy = mainDatabaseCopy,
       _remarkDatabaseCopy = remarkDatabaseCopy;

  static const defaultBatchSize = 500;

  final Directory _stagingRoot;
  final File _mainDatabaseCopy;
  final File? _remarkDatabaseCopy;

  /// Maximum number of records emitted per batch.
  final int batchSize;

  Isar? _mainIsar;
  Isar? _remarkIsar;

  Directory get stagingRoot => _stagingRoot;

  bool get isOpen => _mainIsar?.isOpen ?? false;

  /// Opens the staging copies. Safe to call more than once.
  Future<void> open() async {
    final existing = _mainIsar;
    if (existing != null && existing.isOpen) return;
    _mainIsar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: _mainDatabaseCopy.parent.path,
      name: _isarInstanceName(_mainDatabaseCopy),
      inspector: false,
    );
    final remarkCopy = _remarkDatabaseCopy;
    if (remarkCopy != null && await remarkCopy.exists()) {
      _remarkIsar = await Isar.open(
        [BookRemarkSchema],
        directory: remarkCopy.parent.path,
        name: _isarInstanceName(remarkCopy),
        inspector: false,
      );
    }
  }

  /// Closes both instances. Idempotent and safe after failures.
  Future<void> close() async {
    final main = _mainIsar;
    _mainIsar = null;
    if (main != null && main.isOpen) {
      await main.close();
    }
    final remark = _remarkIsar;
    _remarkIsar = null;
    if (remark != null && remark.isOpen) {
      await remark.close();
    }
  }

  /// Streams books in ascending-id batches.
  Stream<List<Book>> readBooks() {
    return _readBatched(
      fetch: (lastId, limit) => _requireMain().books
          .where()
          .idGreaterThan(lastId)
          .limit(limit)
          .findAll(),
      idOf: (book) => book.id,
    );
  }

  /// Streams book cards in ascending-id batches.
  Stream<List<BookCard>> readBookCards() {
    return _readBatched(
      fetch: (lastId, limit) => _requireMain().bookCards
          .where()
          .idGreaterThan(lastId)
          .limit(limit)
          .findAll(),
      idOf: (card) => card.id,
    );
  }

  /// Streams book assets in ascending-id batches.
  Stream<List<BookAsset>> readBookAssets() {
    return _readBatched(
      fetch: (lastId, limit) => _requireMain().bookAssets
          .where()
          .idGreaterThan(lastId)
          .limit(limit)
          .findAll(),
      idOf: (asset) => asset.id,
    );
  }

  /// Streams book remarks from the separate remark database copy.
  ///
  /// Emits nothing when the staging copy has no remark database.
  Stream<List<BookRemark>> readBookRemarks() {
    final isar = _remarkIsar;
    if (isar == null || !isar.isOpen) {
      return const Stream<List<BookRemark>>.empty();
    }
    return _readBatched(
      fetch: (lastId, limit) =>
          isar.bookRemarks.where().idGreaterThan(lastId).limit(limit).findAll(),
      idOf: (remark) => remark.id,
    );
  }

  Future<int> countBooks() => _requireMain().books.count();

  Future<int> countBookCards() => _requireMain().bookCards.count();

  Future<int> countBookAssets() => _requireMain().bookAssets.count();

  Future<int> countBookRemarks() async {
    final isar = _remarkIsar;
    if (isar == null || !isar.isOpen) return 0;
    return isar.bookRemarks.count();
  }

  Isar _requireMain() {
    final isar = _mainIsar;
    if (isar == null || !isar.isOpen) {
      throw StateError('LegacyIsarReader must be opened before reading');
    }
    return isar;
  }

  Stream<List<T>> _readBatched<T>({
    required Future<List<T>> Function(int lastId, int limit) fetch,
    required int Function(T record) idOf,
  }) async* {
    var lastId = 0;
    while (true) {
      final batch = await fetch(lastId, batchSize);
      if (batch.isEmpty) return;
      batch.sort((left, right) => idOf(left).compareTo(idOf(right)));
      lastId = idOf(batch.last);
      yield batch;
      if (batch.length < batchSize) return;
    }
  }

  /// Probes a staging copy with the current legacy schema.
  ///
  /// Returns true when the main copy carries the MDBX file header used by
  /// Isar, opens with the legacy schema and the books, bookCards and
  /// bookAssets collections are queryable. When [remarkDatabaseCopy] is
  /// provided, the remark database must also open and be queryable. Never
  /// throws: any failure means the copy is not a readable FluidText legacy
  /// database.
  static Future<bool> probeCopy({
    required Directory stagingRoot,
    required File mainDatabaseCopy,
    File? remarkDatabaseCopy,
  }) async {
    assert(
      StoragePathSafety.isLexicallyWithinDirectory(
        directoryPath: stagingRoot.path,
        filePath: mainDatabaseCopy.path,
      ),
      'mainDatabaseCopy must be inside the staging root',
    );
    Isar? mainIsar;
    Isar? remarkIsar;
    try {
      // Random bytes may still "open" as a fresh empty database, so verify
      // the MDBX magic header before trusting the instance.
      if (!await hasIsarFileHeader(mainDatabaseCopy)) return false;
      mainIsar = await Isar.open(
        [BookSchema, BookAssetSchema, BookCardSchema],
        directory: mainDatabaseCopy.parent.path,
        name: _isarInstanceName(mainDatabaseCopy),
        inspector: false,
      );
      await mainIsar.books.where().limit(1).findAll();
      await mainIsar.bookCards.where().limit(1).findAll();
      await mainIsar.bookAssets.where().limit(1).findAll();
      final remarkCopy = remarkDatabaseCopy;
      if (remarkCopy != null && await remarkCopy.exists()) {
        remarkIsar = await Isar.open(
          [BookRemarkSchema],
          directory: remarkCopy.parent.path,
          name: _isarInstanceName(remarkCopy),
          inspector: false,
        );
        await remarkIsar.bookRemarks.where().limit(1).findAll();
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (mainIsar != null && mainIsar.isOpen) {
        await mainIsar.close();
      }
      if (remarkIsar != null && remarkIsar.isOpen) {
        await remarkIsar.close();
      }
    }
  }

  /// MDBX magic value (`MDBX_MAGIC`) stored in the database meta page.
  static const _mdbxMagic = 0x59659DBDEF4C11;

  /// Offset of `mm_magic_and_version` inside the first meta page.
  static const _mdbxMagicOffset = 20;

  /// Checks whether [file] starts with the MDBX/Isar database header.
  ///
  /// Isar's underlying MDBX engine may open a garbage file as a fresh empty
  /// database instead of failing, so trust decisions must not rely on
  /// [Isar.open] alone.
  static Future<bool> hasIsarFileHeader(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      if (await raf.length() < _mdbxMagicOffset + 8) return false;
      await raf.setPosition(_mdbxMagicOffset);
      final bytes = await raf.read(8);
      if (bytes.length < 8) return false;
      var value = 0;
      for (var index = 7; index >= 0; index--) {
        value = (value << 8) | bytes[index];
      }
      // The low byte carries the MDBX data version, the rest is the magic.
      return (value >> 8) == _mdbxMagic;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  static String _isarInstanceName(File file) {
    final normalized = file.path.replaceAll(r'\', '/');
    final baseName = normalized.substring(normalized.lastIndexOf('/') + 1);
    const extension = '.isar';
    if (baseName.endsWith(extension)) {
      return baseName.substring(0, baseName.length - extension.length);
    }
    return baseName;
  }
}
