import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/analysis/reading_analysis_controller.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_card_activity_event.dart';
import 'package:fluidtext/repositories/library_change_tracker.dart';
import 'package:fluidtext/repositories/library_repository.dart';

void main() {
  test('cached analytics are rejected after library data changes', () async {
    ReadingAnalysisController.clearCache();
    final repository = _AnalysisRepository();
    final controller = ReadingAnalysisController(
      repository: repository,
      bookIds: const [],
      loadRemarks: () async => const {},
    );

    final loaded = await controller.load();

    expect(controller.getCachedAnalytics(), same(loaded));
    LibraryChangeTracker.instance.markChanged();
    expect(controller.getCachedAnalytics(), isNull);
  });
}

class _AnalysisRepository implements LibraryRepository {
  final _book = Book()
    ..id = 1
    ..title = 'Book'
    ..createdAt = DateTime(2026);

  @override
  Future<List<Book>> loadBooks() async => [_book];

  @override
  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds) async => {
    1: const BookCardStats(totalCount: 1, readCount: 0, favoriteCount: 0),
  };

  @override
  Future<List<BookCardActivityEvent>> loadReadActivityEvents(
    List<int> bookIds,
  ) async => const [];

  @override
  Future<List<BookCardActivityEvent>> loadFavoriteActivityEvents(
    List<int> bookIds,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
