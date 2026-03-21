import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_card.dart';

class BookCardRepository {
  const BookCardRepository(this.isar);

  final Isar isar;

  Future<List<Book>> loadBooks() {
    return isar.books.where().sortByCreatedAtDesc().findAll();
  }

  Future<List<int>> loadOrderedCardIds(int bookId) {
    return isar.bookCards
        .filter()
        .bookIdEqualTo(bookId)
        .sortByCardIndex()
        .idProperty()
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
