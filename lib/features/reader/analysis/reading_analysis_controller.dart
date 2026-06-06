import '../../../repositories/book_card_repository.dart';
import '../../../services/book_remark_service.dart';
import 'models/reading_analytics.dart';

class ReadingAnalysisController {
  ReadingAnalysisController({
    required this.repository,
    required List<int> bookIds,
  }) : bookIds = List<int>.unmodifiable(bookIds);

  final BookCardRepository repository;
  final List<int> bookIds;

  static final _analysisCache = <String, ReadingAnalytics>{};

  static void clearCache() {
    _analysisCache.clear();
  }

  String get cacheKey {
    if (bookIds.isEmpty) return 'all';
    final sorted = bookIds.toSet().toList(growable: false)..sort();
    return sorted.join(',');
  }

  ReadingAnalytics? getCachedAnalytics({bool forceFullScan = false}) {
    if (forceFullScan) return null;
    return _analysisCache[cacheKey];
  }

  Future<ReadingAnalytics> load({bool forceFullScan = false}) async {
    return _loadFull(cacheKey);
  }

  Future<ReadingAnalytics> _loadFull(String cacheKey) async {
    final books = bookIds.isEmpty
        ? await repository.loadBooks()
        : await repository.loadBooksByIds(bookIds);
    final resolvedBookIds = books
        .map((book) => book.id)
        .toList(growable: false);
    final remarksFuture = BookRemarkService.instance.load();
    final statsFuture = repository.loadBookStats(resolvedBookIds);
    final readEventsFuture = repository.loadReadActivityEvents(resolvedBookIds);
    final favoriteEventsFuture = repository.loadFavoriteActivityEvents(
      resolvedBookIds,
    );

    final remarks = await remarksFuture;
    final stats = await statsFuture;
    final readEvents = await readEventsFuture;
    final favoriteEvents = await favoriteEventsFuture;
    final titlesById = {
      for (final book in books) book.id: remarks[book.id] ?? book.title,
    };

    final analytics = ReadingAnalytics.fromEvents(
      books: books,
      bookTitlesById: titlesById,
      statsByBookId: stats,
      readEvents: readEvents,
      favoriteEvents: favoriteEvents,
    );
    _analysisCache[cacheKey] = analytics;
    return analytics;
  }
}
