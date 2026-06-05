import '../../../../models/book.dart';
import '../../../../models/book_card.dart';
import '../../../../repositories/book_card_repository.dart';
import 'reading_analytics.dart';

class ReadingAnalysisCacheEntry {
  const ReadingAnalysisCacheEntry({
    required this.books,
    required this.bookTitlesById,
    required this.statsByBookId,
    required this.readCards,
    required this.favoriteCards,
    required this.analytics,
    required this.scannedAt,
  });

  final List<Book> books;
  final Map<int, String> bookTitlesById;
  final Map<int, BookCardStats> statsByBookId;
  final List<BookCard> readCards;
  final List<BookCard> favoriteCards;
  final ReadingAnalytics analytics;
  final DateTime scannedAt;
}
