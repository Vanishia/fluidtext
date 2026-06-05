import 'package:flutter/material.dart';

import '../../../../models/book.dart';
import '../../../../models/book_card.dart';
import '../../../../repositories/book_card_repository.dart';

class BarDatum {
  const BarDatum({required this.label, required this.value});

  final String label;
  final int value;
}

class TrendPoint {
  const TrendPoint({required this.date, required this.count});

  final DateTime date;
  final int count;

  String get shortLabel => '${date.month}/${date.day}';
}

class TimedCardEvent {
  const TimedCardEvent({required this.timestamp, required this.card});

  final DateTime timestamp;
  final BookCard card;
}

class DayAnalysis {
  DayAnalysis(this.date);

  final DateTime date;
  final List<TimedCardEvent> readEvents = <TimedCardEvent>[];
  final List<TimedCardEvent> favoriteEvents = <TimedCardEvent>[];
  final Map<int, int> readCountByBook = <int, int>{};
  final Map<int, int> favoriteCountByBook = <int, int>{};
  final List<int> hourlyReads = List<int>.filled(24, 0);

  int get readCount => readEvents.length;
  int get favoriteCount => favoriteEvents.length;

  Iterable<int> get bookIds sync* {
    final ids = <int>{...readCountByBook.keys, ...favoriteCountByBook.keys};
    final ordered = ids.toList(growable: false)..sort();
    yield* ordered;
  }

  String get peakHourLabel {
    var bestHour = 0;
    var bestValue = 0;
    for (var hour = 0; hour < hourlyReads.length; hour += 1) {
      if (hourlyReads[hour] > bestValue) {
        bestValue = hourlyReads[hour];
        bestHour = hour;
      }
    }
    return bestValue == 0 ? '无' : '${bestHour.toString().padLeft(2, '0')}:00';
  }

  static DayAnalysis empty(DateTime date) => DayAnalysis(date);
}

class BookSummary {
  const BookSummary({
    required this.bookId,
    required this.title,
    required this.totalCount,
    required this.readCount,
    required this.favoriteCount,
    this.lastReadAt,
    this.lastFavoritedAt,
  });

  final int bookId;
  final String title;
  final int totalCount;
  final int readCount;
  final int favoriteCount;
  final DateTime? lastReadAt;
  final DateTime? lastFavoritedAt;

  int get unreadCount => totalCount - readCount;
  double get progress => totalCount == 0 ? 0 : readCount / totalCount;
  double get favoriteRate => totalCount == 0 ? 0 : favoriteCount / totalCount;
}

class ReadingAnalytics {
  ReadingAnalytics({
    required this.books,
    required this.bookTitlesById,
    required this.bookSummaries,
    required this.daysByDate,
    required this.recentFavoriteEvents,
    required this.totalCards,
    required this.totalRead,
    required this.totalFavorites,
    required this.readLast7,
    required this.readLast30,
    required this.favoriteLast7,
    required this.favoriteLast30,
    required this.todayRead,
    required this.thisWeekRead,
    required this.thisMonthRead,
    required this.currentStreak,
    required this.bestStreak,
    required this.activeDays365,
    required this.activeDays30,
    required this.activeDays7,
    required this.avgReadsPerActiveDay30,
    required this.weekdayCounts,
    required this.hourCounts,
    required this.trendLast14,
  });

  final List<Book> books;
  final Map<int, String> bookTitlesById;
  final List<BookSummary> bookSummaries;
  final Map<DateTime, DayAnalysis> daysByDate;
  final List<TimedCardEvent> recentFavoriteEvents;
  final int totalCards;
  final int totalRead;
  final int totalFavorites;
  final int readLast7;
  final int readLast30;
  final int favoriteLast7;
  final int favoriteLast30;
  final int todayRead;
  final int thisWeekRead;
  final int thisMonthRead;
  final int currentStreak;
  final int bestStreak;
  final int activeDays365;
  final int activeDays30;
  final int activeDays7;
  final double avgReadsPerActiveDay30;
  final List<int> weekdayCounts;
  final List<int> hourCounts;
  final List<TrendPoint> trendLast14;

  factory ReadingAnalytics.from({
    required List<Book> books,
    required Map<int, String> bookTitlesById,
    required Map<int, BookCardStats> statsByBookId,
    required List<BookCard> readCards,
    required List<BookCard> favoriteCards,
  }) {
    final totalCards = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.totalCount,
    );
    final totalRead = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.readCount,
    );
    final totalFavorites = statsByBookId.values.fold<int>(
      0,
      (sum, item) => sum + item.favoriteCount,
    );

    final lastReadByBook = <int, DateTime>{};
    final lastFavoriteByBook = <int, DateTime>{};
    final daysByDate = <DateTime, DayAnalysis>{};
    final weekdayCounts = List<int>.filled(7, 0);
    final hourCounts = List<int>.filled(24, 0);
    final today = DateUtils.dateOnly(DateTime.now());
    final sevenDayStart = today.subtract(const Duration(days: 6));
    final thirtyDayStart = today.subtract(const Duration(days: 29));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month);

    var readLast7 = 0;
    var readLast30 = 0;
    var favoriteLast7 = 0;
    var favoriteLast30 = 0;
    var todayRead = 0;
    var thisWeekRead = 0;
    var thisMonthRead = 0;

    for (final card in readCards) {
      final readAt = card.readAt?.toLocal();
      if (readAt == null) continue;
      final day = DateUtils.dateOnly(readAt);
      final dayAnalysis = daysByDate.putIfAbsent(day, () => DayAnalysis(day));
      final event = TimedCardEvent(timestamp: readAt, card: card);
      dayAnalysis.readEvents.add(event);
      dayAnalysis.readCountByBook.update(
        card.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      dayAnalysis.hourlyReads[readAt.hour] += 1;
      weekdayCounts[readAt.weekday - 1] += 1;
      hourCounts[readAt.hour] += 1;
      if (!day.isBefore(sevenDayStart)) readLast7 += 1;
      if (!day.isBefore(thirtyDayStart)) readLast30 += 1;
      if (day == today) todayRead += 1;
      if (!day.isBefore(weekStart)) thisWeekRead += 1;
      if (!day.isBefore(monthStart)) thisMonthRead += 1;

      final current = lastReadByBook[card.bookId];
      if (current == null || readAt.isAfter(current)) {
        lastReadByBook[card.bookId] = readAt;
      }
    }

    final favoriteEvents = <TimedCardEvent>[];
    for (final card in favoriteCards) {
      final favoritedAt = card.favoritedAt?.toLocal();
      if (favoritedAt == null) continue;
      final day = DateUtils.dateOnly(favoritedAt);
      final dayAnalysis = daysByDate.putIfAbsent(day, () => DayAnalysis(day));
      final event = TimedCardEvent(timestamp: favoritedAt, card: card);
      dayAnalysis.favoriteEvents.add(event);
      dayAnalysis.favoriteCountByBook.update(
        card.bookId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (!day.isBefore(sevenDayStart)) favoriteLast7 += 1;
      if (!day.isBefore(thirtyDayStart)) favoriteLast30 += 1;
      favoriteEvents.add(event);

      final current = lastFavoriteByBook[card.bookId];
      if (current == null || favoritedAt.isAfter(current)) {
        lastFavoriteByBook[card.bookId] = favoritedAt;
      }
    }

    for (final day in daysByDate.values) {
      day.readEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      day.favoriteEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    favoriteEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final activeReadDays =
        daysByDate.entries
            .where((entry) => entry.value.readCount > 0)
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();

    final activeDays365 = activeReadDays
        .where(
          (day) => !day.isBefore(today.subtract(const Duration(days: 364))),
        )
        .length;
    final activeDays30 = activeReadDays
        .where((day) => !day.isBefore(thirtyDayStart))
        .length;
    final activeDays7 = activeReadDays
        .where((day) => !day.isBefore(sevenDayStart))
        .length;

    var currentStreak = 0;
    for (
      var cursor = today;
      ;
      cursor = cursor.subtract(const Duration(days: 1))
    ) {
      final day = daysByDate[cursor];
      if (day == null || day.readCount == 0) break;
      currentStreak += 1;
    }

    var bestStreak = 0;
    var streak = 0;
    DateTime? previousDay;
    for (final day in activeReadDays) {
      if (previousDay == null || day.difference(previousDay).inDays == 1) {
        streak += 1;
      } else {
        streak = 1;
      }
      if (streak > bestStreak) bestStreak = streak;
      previousDay = day;
    }

    final trendLast14 = List<TrendPoint>.generate(14, (index) {
      final date = today.subtract(Duration(days: 13 - index));
      return TrendPoint(date: date, count: daysByDate[date]?.readCount ?? 0);
    });

    final summaries = books
        .map((book) {
          final stats = statsByBookId[book.id] ?? BookCardStats.empty;
          return BookSummary(
            bookId: book.id,
            title: bookTitlesById[book.id] ?? book.title,
            totalCount: stats.totalCount,
            readCount: stats.readCount,
            favoriteCount: stats.favoriteCount,
            lastReadAt: lastReadByBook[book.id],
            lastFavoritedAt: lastFavoriteByBook[book.id],
          );
        })
        .toList(growable: false);

    return ReadingAnalytics(
      books: books,
      bookTitlesById: bookTitlesById,
      bookSummaries: summaries,
      daysByDate: daysByDate,
      recentFavoriteEvents: favoriteEvents,
      totalCards: totalCards,
      totalRead: totalRead,
      totalFavorites: totalFavorites,
      readLast7: readLast7,
      readLast30: readLast30,
      favoriteLast7: favoriteLast7,
      favoriteLast30: favoriteLast30,
      todayRead: todayRead,
      thisWeekRead: thisWeekRead,
      thisMonthRead: thisMonthRead,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      activeDays365: activeDays365,
      activeDays30: activeDays30,
      activeDays7: activeDays7,
      avgReadsPerActiveDay30: activeDays30 == 0 ? 0 : readLast30 / activeDays30,
      weekdayCounts: weekdayCounts,
      hourCounts: hourCounts,
      trendLast14: trendLast14,
    );
  }

  int get totalBooks => books.length;
  int get totalUnread => totalCards - totalRead;
  double get overallProgress => totalCards == 0 ? 0 : totalRead / totalCards;
  double get favoriteToReadRatio =>
      totalRead == 0 ? 0 : totalFavorites / totalRead;

  List<BookSummary> get booksSortedByRead {
    final copy = List<BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final readCompare = b.readCount.compareTo(a.readCount);
      if (readCompare != 0) return readCompare;
      final progressCompare = b.progress.compareTo(a.progress);
      if (progressCompare != 0) return progressCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  List<BookSummary> get booksSortedByProgress {
    final copy = List<BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final progressCompare = b.progress.compareTo(a.progress);
      if (progressCompare != 0) return progressCompare;
      final readCompare = b.readCount.compareTo(a.readCount);
      if (readCompare != 0) return readCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  List<BookSummary> get booksSortedByFavorite {
    final copy = List<BookSummary>.from(bookSummaries);
    copy.sort((a, b) {
      final favoriteCompare = b.favoriteCount.compareTo(a.favoriteCount);
      if (favoriteCompare != 0) return favoriteCompare;
      final favoriteRateCompare = b.favoriteRate.compareTo(a.favoriteRate);
      if (favoriteRateCompare != 0) return favoriteRateCompare;
      return a.title.compareTo(b.title);
    });
    return copy;
  }

  int get depthBucketNotStarted =>
      bookSummaries.where((item) => item.readCount == 0).length;
  int get depthBucketEarly => bookSummaries
      .where((item) => item.progress > 0 && item.progress < 0.25)
      .length;
  int get depthBucketMid => bookSummaries
      .where((item) => item.progress >= 0.25 && item.progress < 0.75)
      .length;
  int get depthBucketLate => bookSummaries
      .where((item) => item.progress >= 0.75 && item.progress < 1)
      .length;
  int get depthBucketDone =>
      bookSummaries.where((item) => item.progress >= 1).length;

  List<String> get weekdayShortLabels => const [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  String get busiestWeekdayLabel {
    var bestIndex = 0;
    var bestValue = 0;
    for (var index = 0; index < weekdayCounts.length; index += 1) {
      if (weekdayCounts[index] > bestValue) {
        bestValue = weekdayCounts[index];
        bestIndex = index;
      }
    }
    return bestValue == 0
        ? '暂无已读记录'
        : '周${weekdayShortLabels[bestIndex]}，${weekdayCounts[bestIndex]} 张已读';
  }

  String get busiestHourBucketLabel {
    final buckets = hourBuckets;
    var best = const BarDatum(label: '无', value: 0);
    for (final item in buckets) {
      if (item.value > best.value) {
        best = item;
      }
    }
    return best.value == 0 ? '暂无已读记录' : '${best.label}，${best.value} 张已读';
  }

  List<BarDatum> get hourBuckets => <BarDatum>[
    _bucketForHours('00-02', 0, 3),
    _bucketForHours('03-05', 3, 6),
    _bucketForHours('06-08', 6, 9),
    _bucketForHours('09-11', 9, 12),
    _bucketForHours('12-14', 12, 15),
    _bucketForHours('15-17', 15, 18),
    _bucketForHours('18-20', 18, 21),
    _bucketForHours('21-23', 21, 24),
  ];

  BarDatum _bucketForHours(String label, int start, int end) {
    var sum = 0;
    for (var hour = start; hour < end; hour += 1) {
      sum += hourCounts[hour];
    }
    return BarDatum(label: label, value: sum);
  }

  String bookTitle(int bookId) => bookTitlesById[bookId] ?? '未知书籍';
}
