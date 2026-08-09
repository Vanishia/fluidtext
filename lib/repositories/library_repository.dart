import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_card_activity_event.dart';

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

abstract interface class LibraryRepository {
  Future<List<Book>> loadBooks();

  Future<List<Book>> loadBooksByIds(List<int> ids);

  Future<List<int>> loadOrderedCardIds(List<int> bookIds);

  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds);

  Future<List<BookCard>> loadReadCards(List<int> bookIds);

  Future<List<BookCard>> loadFavoriteCards(List<int> bookIds);

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

  Future<void> toggleFavorite(BookCard card);

  Future<void> toggleRead(BookCard card);

  Future<void> deleteBook(int bookId);
}
