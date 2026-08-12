import '../../../repositories/library_repository.dart';
import '../../../repositories/library_change_tracker.dart';
import 'models/reading_analytics.dart';

class ReadingAnalysisController {
  ReadingAnalysisController({
    required this.repository,
    required List<int> bookIds,
    Future<Map<int, String>> Function()? loadRemarks,
  }) : bookIds = List<int>.unmodifiable(bookIds),
       _loadRemarks = loadRemarks ?? repository.loadRemarks;

  final LibraryRepository repository;
  final List<int> bookIds;
  final Future<Map<int, String>> Function() _loadRemarks;

  static final _analysisCache = <String, _ReadingAnalyticsCacheEntry>{};

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
    final entry = _analysisCache[cacheKey];
    if (entry == null) return null;
    if (entry.revision != LibraryChangeTracker.instance.revision) {
      _analysisCache.remove(cacheKey);
      return null;
    }
    return entry.analytics;
  }

  Future<ReadingAnalytics> load({bool forceFullScan = false}) async {
    return _loadFull(cacheKey);
  }

  Future<ReadingAnalytics> _loadFull(String cacheKey) async {
    final sourceRevision = LibraryChangeTracker.instance.revision;
    final books = bookIds.isEmpty
        ? await repository.loadBooks()
        : await repository.loadBooksByIds(bookIds);
    final resolvedBookIds = books
        .map((book) => book.id)
        .toList(growable: false);
    final remarksFuture = _loadRemarks();
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
    if (LibraryChangeTracker.instance.revision == sourceRevision) {
      _analysisCache[cacheKey] = _ReadingAnalyticsCacheEntry(
        revision: sourceRevision,
        analytics: analytics,
      );
    }
    return analytics;
  }
}

class _ReadingAnalyticsCacheEntry {
  const _ReadingAnalyticsCacheEntry({
    required this.revision,
    required this.analytics,
  });

  final int revision;
  final ReadingAnalytics analytics;
}
