import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_card.dart';

class BookCardRepository {
  const BookCardRepository(this.isar);

  final Isar isar;

  Future<List<Book>> loadBooks() {
    return isar.books.where().sortByCreatedAtDesc().findAll();
  }

  Future<List<Book>> loadBooksByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Book>[];

    final fetched = await isar.books
        .filter()
        .anyOf(ids, (query, id) => query.idEqualTo(id))
        .findAll();
    final booksById = {for (final book in fetched) book.id: book};
    return ids.map((id) => booksById[id]).whereType<Book>().toList();
  }

  Future<List<int>> loadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final orderedIds = <int>[];
    for (final bookId in bookIds) {
      final ids = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .sortByCardIndex()
          .idProperty()
          .findAll();
      orderedIds.addAll(ids);
    }
    return orderedIds;
  }

  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final orderedIds = <int>[];
    for (final bookId in bookIds) {
      final ids = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .and()
          .isReadEqualTo(false)
          .sortByCardIndex()
          .idProperty()
          .findAll();
      orderedIds.addAll(ids);
    }
    return orderedIds;
  }

  Future<List<BookCard>> loadReadCards(List<int> bookIds) {
    if (bookIds.isEmpty) return Future.value(const <BookCard>[]);

    return isar.bookCards
        .filter()
        .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
        .and()
        .isReadEqualTo(true)
        .sortByReadAtDesc()
        .findAll();
  }

  Future<List<BookCard>> loadFavoriteCards(List<int> bookIds) {
    if (bookIds.isEmpty) return Future.value(const <BookCard>[]);

    return isar.bookCards
        .filter()
        .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
        .and()
        .isFavoriteEqualTo(true)
        .sortByFavoritedAtDesc()
        .findAll();
  }

  Future<List<BookCard>> loadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final fetched = await isar.bookCards
        .filter()
        .anyOf(ids, (query, id) => query.idEqualTo(id))
        .findAll();
    final mapById = {for (final card in fetched) card.id: card};
    return ids.map((id) => mapById[id]).whereType<BookCard>().toList();
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
