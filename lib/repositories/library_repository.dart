import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_card_activity_event.dart';
import 'library_snapshot.dart';

class BookCardStats {
  const BookCardStats({
    required this.totalCount,
    required this.readCount,
    required this.favoriteCount,
  });

  static const empty = BookCardStats(
    totalCount: 0,
    readCount: 0,
    favoriteCount: 0,
  );

  final int totalCount;
  final int readCount;
  final int favoriteCount;

  double get readProgress {
    if (totalCount == 0) return 0;
    return readCount / totalCount;
  }

  int get unreadCount => totalCount - readCount;
}

/// A single full-text search hit. [snippet] is the `snippet()` output (or a
/// LIKE-fallback excerpt) with matches wrapped in `<mark>` tags.
class CardSearchResult {
  const CardSearchResult({required this.card, required this.snippet});

  final BookCard card;
  final String snippet;
}

abstract interface class LibraryRepository
    implements
        LibraryReadRepository,
        LibraryWriteRepository,
        LibraryImportRepository,
        LibraryMaintenanceRepository,
        LibrarySearchRepository,
        RemarkRepository,
        BackupSnapshotRepository,
        DatabaseLifecycle {}

abstract interface class LibraryReadRepository {
  Future<List<Book>> loadBooks();

  Future<List<Book>> loadBooksByIds(List<int> ids);

  Future<List<int>> loadOrderedCardIds(List<int> bookIds);

  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds);

  Future<List<BookCard>> loadReadCards(
    List<int> bookIds, {
    int offset = 0,
    int? limit,
  });

  Future<List<BookCard>> loadFavoriteCards(
    List<int> bookIds, {
    int offset = 0,
    int? limit,
  });

  Future<int> countReadCards(List<int> bookIds);

  Future<int> countFavoriteCards(List<int> bookIds);

  Future<List<BookCardActivityEvent>> loadReadActivityEvents(List<int> bookIds);

  Future<List<BookCardActivityEvent>> loadFavoriteActivityEvents(
    List<int> bookIds,
  );

  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds);

  Future<void> logDatabaseSnapshot(String reason);

  Future<List<BookCard>> loadCardsByIds(List<int> ids);

  Future<List<BookCard>> loadUnreadCardsByIds(List<int> ids);

  Future<List<BookAsset>> loadBookAssets({
    required int bookId,
    required List<String> assetKeys,
  });

  Future<List<BookCard>> loadContextCards({
    required int bookId,
    required int centerCardIndex,
    required int before,
    required int after,
  });
}

abstract interface class LibraryWriteRepository {
  Future<void> toggleFavorite(BookCard card);

  Future<void> toggleRead(BookCard card);

  Future<void> deleteBook(int bookId);
}

abstract interface class LibraryImportRepository {
  Future<LibraryImportResult> importBookDraft(ImportBookDraft draft);
}

abstract interface class LibraryMaintenanceRepository {
  /// Deletes books whose stored cards are incomplete — e.g. an import
  /// interrupted by a process kill — together with orphaned staged asset
  /// files, and returns the deleted books so the UI can prompt a re-import.
  Future<List<Book>> pruneIncompleteBooks();
}

abstract interface class LibrarySearchRepository {
  /// Full-text search over card contents. FTS requires at least 3 characters
  /// (trigram tokenizer); shorter queries fall back to a LIKE scan.
  Future<List<CardSearchResult>> searchCards(
    String query, {
    int limit = 50,
    int offset = 0,
  });

  /// False while the FTS index is still being backfilled after an upgrade.
  Future<bool> isSearchIndexReady();
}

abstract interface class RemarkRepository {
  Future<Map<int, String>> loadRemarks();

  Future<void> saveRemark(int bookId, String remark);

  Future<void> removeRemark(int bookId);
}

abstract interface class BackupSnapshotRepository {
  Future<LibraryBackupSnapshot> buildBackupSnapshot();
}

abstract interface class DatabaseLifecycle {
  Future<void> checkpoint();

  Future<void> close();
}
