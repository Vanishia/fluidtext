import 'dart:developer' as developer;

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_card.dart';

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

class BookCardRepository {
  const BookCardRepository(this.isar);

  final Isar isar;

  Future<List<Book>> loadBooks() {
    return isar.books.where().sortByCreatedAtDesc().findAll();
  }

  Future<List<Book>> loadBooksByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Book>[];

    final books = await Future.wait(ids.map(isar.books.get));
    return books.whereType<Book>().toList(growable: false);
  }

  Future<List<int>> loadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final idsByBook = await Future.wait(
      bookIds.map(_loadOrderedCardIdsForBook),
    );
    return idsByBook.expand((ids) => ids).toList(growable: false);
  }

  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final idsByBook = await Future.wait(
      bookIds.map(_loadUnreadOrderedCardIdsForBook),
    );
    return idsByBook.expand((ids) => ids).toList(growable: false);
  }

  Future<List<int>> _loadOrderedCardIdsForBook(int bookId) {
    return isar.bookCards
        .filter()
        .bookIdEqualTo(bookId)
        .sortByCardIndex()
        .idProperty()
        .findAll();
  }

  Future<List<int>> _loadUnreadOrderedCardIdsForBook(int bookId) {
    return isar.bookCards
        .filter()
        .bookIdEqualTo(bookId)
        .sortByCardIndex()
        .findAll()
        .then(
          (cards) => cards
              .where((card) => !card.isRead)
              .map((card) => card.id)
              .toList(growable: false),
        );
  }

  Future<List<BookCard>> loadReadCards(List<int> bookIds) {
    if (bookIds.isEmpty) {
      return isar.bookCards
          .filter()
          .isReadEqualTo(true)
          .sortByReadAtDesc()
          .findAll();
    }

    return isar.bookCards
        .filter()
        .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
        .and()
        .isReadEqualTo(true)
        .sortByReadAtDesc()
        .findAll();
  }

  Future<List<BookCard>> loadFavoriteCards(List<int> bookIds) {
    if (bookIds.isEmpty) {
      return isar.bookCards
          .filter()
          .isFavoriteEqualTo(true)
          .sortByFavoritedAtDesc()
          .findAll();
    }

    return isar.bookCards
        .filter()
        .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
        .and()
        .isFavoriteEqualTo(true)
        .sortByFavoritedAtDesc()
        .findAll();
  }

  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int, BookCardStats>{};

    final entries = await Future.wait(
      bookIds.map((bookId) async {
        final total = await isar.bookCards
            .filter()
            .bookIdEqualTo(bookId)
            .count();
        final read = await isar.bookCards
            .filter()
            .bookIdEqualTo(bookId)
            .and()
            .isReadEqualTo(true)
            .count();
        final favorite = await isar.bookCards
            .filter()
            .bookIdEqualTo(bookId)
            .and()
            .isFavoriteEqualTo(true)
            .count();
        return MapEntry(
          bookId,
          BookCardStats(
            totalCount: total,
            readCount: read,
            favoriteCount: favorite,
          ),
        );
      }),
    );

    return Map<int, BookCardStats>.fromEntries(entries);
  }

  Future<void> logDatabaseSnapshot(String reason) async {
    final books = await loadBooks();
    final stats = await loadBookStats(books.map((book) => book.id).toList());
    final totalCards = stats.values.fold<int>(
      0,
      (sum, item) => sum + item.totalCount,
    );
    final totalRead = stats.values.fold<int>(
      0,
      (sum, item) => sum + item.readCount,
    );
    final totalFavorites = stats.values.fold<int>(
      0,
      (sum, item) => sum + item.favoriteCount,
    );
    final unknownFavoriteTime = await isar.bookCards
        .filter()
        .isFavoriteEqualTo(true)
        .and()
        .favoritedAtIsNull()
        .count();

    developer.log(
      'DB snapshot [$reason]: books=${books.length}, cards=$totalCards, read=$totalRead, favorites=$totalFavorites, favoritesWithoutTime=$unknownFavoriteTime',
      name: 'BookCardRepository',
    );

    for (final book in books) {
      final item = stats[book.id] ?? BookCardStats.empty;
      developer.log(
        'Book id=${book.id}, title="${book.title}", cards=${item.totalCount}, read=${item.readCount}, favorites=${item.favoriteCount}, fileHash=${book.fileHash != null ? 'yes' : 'no'}, contentFingerprint=${book.contentFingerprint != null ? 'yes' : 'no'}, createdAt=${book.createdAt.toIso8601String()}',
        name: 'BookCardRepository',
      );
    }
  }

  Future<List<BookCard>> loadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final cards = await Future.wait(ids.map(isar.bookCards.get));
    return cards.whereType<BookCard>().toList(growable: false);
  }

  Future<List<BookCard>> loadUnreadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final cards = await Future.wait(ids.map(isar.bookCards.get));
    return cards
        .whereType<BookCard>()
        .where((card) => !card.isRead)
        .toList(growable: false);
  }

  Future<List<BookCard>> loadContextCards({
    required int bookId,
    required int centerCardIndex,
    required int before,
    required int after,
  }) {
    return isar.bookCards
        .filter()
        .bookIdEqualTo(bookId)
        .cardIndexGreaterThan(centerCardIndex - before - 1)
        .and()
        .cardIndexLessThan(centerCardIndex + after + 1)
        .sortByCardIndex()
        .findAll();
  }

  Future<void> toggleFavorite(BookCard card) {
    return isar.writeTxn(() async {
      card.isFavorite = !card.isFavorite;
      card.favoritedAt = card.isFavorite ? DateTime.now() : null;
      await isar.bookCards.put(card);
    });
  }

  Future<void> toggleRead(BookCard card) {
    return isar.writeTxn(() async {
      card.isRead = !card.isRead;
      card.readAt = card.isRead ? DateTime.now() : null;
      await isar.bookCards.put(card);
    });
  }

  Future<void> deleteBook(int bookId) async {
    await isar.writeTxn(() async {
      final cardIds = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .idProperty()
          .findAll();
      if (cardIds.isNotEmpty) {
        await isar.bookCards.deleteAll(cardIds);
      }
      await isar.books.delete(bookId);
    });
  }
}
