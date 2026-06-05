import '../../../models/book.dart';
import '../../../models/book_card.dart';
import '../../../repositories/book_card_repository.dart';
import '../../../services/book_remark_service.dart';
import 'models/analysis_cache_entry.dart';
import 'models/reading_analytics.dart';

class ReadingAnalysisController {
  ReadingAnalysisController({
    required this.repository,
    required List<int> bookIds,
  }) : bookIds = List<int>.unmodifiable(bookIds);

  final BookCardRepository repository;
  final List<int> bookIds;

  static final _analysisCache = <String, ReadingAnalysisCacheEntry>{};

  String get cacheKey {
    if (bookIds.isEmpty) return 'all';
    return bookIds.join(',');
  }

  ReadingAnalysisCacheEntry? getCachedEntry({bool forceFullScan = false}) {
    if (forceFullScan) return null;
    return _analysisCache[cacheKey];
  }

  Future<ReadingAnalytics> load({bool forceFullScan = false}) async {
    final cached = getCachedEntry(forceFullScan: forceFullScan);
    if (cached != null) {
      return _loadIncremental(cacheKey, cached);
    }
    return _loadFull(cacheKey);
  }

  Future<ReadingAnalytics> _loadFull(String cacheKey) async {
    final scanStartedAt = DateTime.now();
    final books = bookIds.isEmpty
        ? await repository.loadBooks()
        : await repository.loadBooksByIds(bookIds);
    final resolvedBookIds = books.map((book) => book.id).toList(growable: false);
    final remarksFuture = BookRemarkService.instance.load();
    final statsFuture = repository.loadBookStats(resolvedBookIds);
    final readCardsFuture = repository.loadReadCards(resolvedBookIds);
    final favoriteCardsFuture = repository.loadFavoriteCards(resolvedBookIds);

    final remarks = await remarksFuture;
    final stats = await statsFuture;
    final readCards = await readCardsFuture;
    final favoriteCards = await favoriteCardsFuture;
    final titlesById = {
      for (final book in books) book.id: remarks[book.id] ?? book.title,
    };

    final analytics = ReadingAnalytics.from(
      books: books,
      bookTitlesById: titlesById,
      statsByBookId: stats,
      readCards: readCards,
      favoriteCards: favoriteCards,
    );
    _analysisCache[cacheKey] = ReadingAnalysisCacheEntry(
      books: books,
      bookTitlesById: titlesById,
      statsByBookId: stats,
      readCards: readCards,
      favoriteCards: favoriteCards,
      analytics: analytics,
      scannedAt: scanStartedAt,
    );
    return analytics;
  }

  Future<ReadingAnalytics> _loadIncremental(
    String cacheKey,
    ReadingAnalysisCacheEntry cached,
  ) async {
    final books = bookIds.isEmpty
        ? await repository.loadBooks()
        : await repository.loadBooksByIds(bookIds);
    if (!_sameBookIds(books, cached.books)) {
      return _loadFull(cacheKey);
    }

    final scanStartedAt = DateTime.now();
    final resolvedBookIds = books.map((book) => book.id).toList(growable: false);
    final remarksFuture = BookRemarkService.instance.load();
    final newReadCardsFuture = repository.loadReadCardsSince(
      resolvedBookIds,
      cached.scannedAt,
    );
    final newFavoriteCardsFuture = repository.loadFavoriteCardsSince(
      resolvedBookIds,
      cached.scannedAt,
    );
    final remarks = await remarksFuture;
    final newReadCards = await newReadCardsFuture;
    final newFavoriteCards = await newFavoriteCardsFuture;
    final titlesById = {
      for (final book in books) book.id: remarks[book.id] ?? book.title,
    };

    final readCards = _mergeCards(cached.readCards, newReadCards);
    final favoriteCards = _mergeCards(cached.favoriteCards, newFavoriteCards);
    final stats = _statsFromCachedTotals(
      cached.statsByBookId,
      readCards,
      favoriteCards,
    );
    final analytics = ReadingAnalytics.from(
      books: books,
      bookTitlesById: titlesById,
      statsByBookId: stats,
      readCards: readCards,
      favoriteCards: favoriteCards,
    );

    _analysisCache[cacheKey] = ReadingAnalysisCacheEntry(
      books: books,
      bookTitlesById: titlesById,
      statsByBookId: stats,
      readCards: readCards,
      favoriteCards: favoriteCards,
      analytics: analytics,
      scannedAt: scanStartedAt,
    );

    return analytics;
  }

  bool _sameBookIds(List<Book> a, List<Book> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((book) => book.id).toSet();
    final bIds = b.map((book) => book.id).toSet();
    return aIds.length == bIds.length && aIds.containsAll(bIds);
  }

  List<BookCard> _mergeCards(List<BookCard> current, List<BookCard> incoming) {
    if (incoming.isEmpty) return current;
    final byId = <int, BookCard>{for (final card in current) card.id: card};
    for (final card in incoming) {
      byId[card.id] = card;
    }
    return byId.values.toList(growable: false);
  }

  Map<int, BookCardStats> _statsFromCachedTotals(
    Map<int, BookCardStats> totals,
    List<BookCard> readCards,
    List<BookCard> favoriteCards,
  ) {
    final readByBook = <int, int>{};
    final favoriteByBook = <int, int>{};
    for (final card in readCards) {
      readByBook.update(card.bookId, (value) => value + 1, ifAbsent: () => 1);
    }
    for (final card in favoriteCards) {
      favoriteByBook.update(
        card.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      for (final entry in totals.entries)
        entry.key: BookCardStats(
          totalCount: entry.value.totalCount,
          readCount: readByBook[entry.key] ?? 0,
          favoriteCount: favoriteByBook[entry.key] ?? 0,
        ),
    };
  }
}
