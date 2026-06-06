import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/analysis/models/reading_analytics.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_card_activity_event.dart';
import 'package:fluidtext/repositories/book_card_repository.dart';

void main() {
  group('ReadingAnalytics.fromEvents', () {
    test(
      'recomputes from the provided event snapshot without stale events',
      () {
        final book = Book()
          ..id = 1
          ..title = 'Book A'
          ..createdAt = DateTime(2026);
        final titlesById = {1: 'Book A'};
        final firstStats = {
          1: const BookCardStats(totalCount: 3, readCount: 2, favoriteCount: 0),
        };
        final secondStats = {
          1: const BookCardStats(totalCount: 3, readCount: 1, favoriteCount: 0),
        };
        final day = DateTime(2026, 6, 6, 9);

        final first = ReadingAnalytics.fromEvents(
          books: [book],
          bookTitlesById: titlesById,
          statsByBookId: firstStats,
          readEvents: [
            BookCardActivityEvent(
              cardId: 10,
              bookId: 1,
              cardIndex: 1,
              timestamp: day,
            ),
            BookCardActivityEvent(
              cardId: 11,
              bookId: 1,
              cardIndex: 2,
              timestamp: day.add(const Duration(hours: 1)),
            ),
          ],
          favoriteEvents: const [],
        );
        final second = ReadingAnalytics.fromEvents(
          books: [book],
          bookTitlesById: titlesById,
          statsByBookId: secondStats,
          readEvents: [
            BookCardActivityEvent(
              cardId: 11,
              bookId: 1,
              cardIndex: 2,
              timestamp: day.add(const Duration(hours: 1)),
            ),
          ],
          favoriteEvents: const [],
        );

        final date = DateTime(2026, 6, 6);
        expect(first.daysByDate[date]?.readCount, 2);
        expect(second.daysByDate[date]?.readCount, 1);
        expect(second.daysByDate[date]?.readEvents.single.cardId, 11);
        expect(second.totalRead, 1);
      },
    );

    test('handles empty snapshots without divide-by-zero output', () {
      final analytics = ReadingAnalytics.fromEvents(
        books: const [],
        bookTitlesById: const {},
        statsByBookId: const {},
        readEvents: const [],
        favoriteEvents: const [],
      );

      expect(analytics.totalBooks, 0);
      expect(analytics.overallProgress, 0);
      expect(analytics.favoriteToReadRatio, 0);
      expect(analytics.avgReadsPerActiveDay30, 0);
      expect(analytics.daysByDate, isEmpty);
    });
  });
}
