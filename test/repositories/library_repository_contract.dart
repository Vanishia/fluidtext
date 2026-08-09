import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/repositories/library_repository.dart';

abstract interface class LibraryRepositoryContractDriver {
  LibraryRepository get repository;

  int get firstBookId;

  int get secondBookId;

  int get firstCardId;

  int get secondCardId;

  String get assetKey;

  Future<void> close();
}

void runLibraryRepositoryContract(
  Future<LibraryRepositoryContractDriver> Function() createDriver,
) {
  LibraryRepositoryContractDriver? driver;

  setUp(() async {
    driver = await createDriver();
  });

  tearDown(() => driver?.close());

  test(
    'loads books, ordered cards, unread cards and aggregate stats',
    () async {
      final current = driver!;
      final books = await current.repository.loadBooks();
      expect(books.map((book) => book.id), [
        current.secondBookId,
        current.firstBookId,
      ]);

      expect(
        await current.repository.loadOrderedCardIds([current.firstBookId]),
        [current.firstCardId, current.secondCardId],
      );
      expect(
        await current.repository.loadUnreadOrderedCardIds([
          current.firstBookId,
        ]),
        [current.firstCardId],
      );

      final stats = await current.repository.loadBookStats([
        current.firstBookId,
      ]);
      expect(stats[current.firstBookId]?.totalCount, 2);
      expect(stats[current.firstBookId]?.readCount, 1);
      expect(stats[current.firstBookId]?.favoriteCount, 1);
    },
  );

  test(
    'loads context and asset metadata through the storage-neutral API',
    () async {
      final current = driver!;
      final contextCards = await current.repository.loadContextCards(
        bookId: current.firstBookId,
        centerCardIndex: 1,
        before: 1,
        after: 1,
      );
      expect(contextCards.map((card) => card.id), [
        current.firstCardId,
        current.secondCardId,
      ]);

      final assets = await current.repository.loadBookAssets(
        bookId: current.firstBookId,
        assetKeys: [current.assetKey],
      );
      expect(assets.single.assetKey, current.assetKey);
    },
  );

  test('persists read and favorite state changes', () async {
    final current = driver!;
    final firstCard = (await current.repository.loadCardsByIds([
      current.firstCardId,
    ])).single;

    await current.repository.toggleRead(firstCard);
    await current.repository.toggleFavorite(firstCard);

    final updated = (await current.repository.loadCardsByIds([
      current.firstCardId,
    ])).single;
    expect(updated.isRead, isTrue);
    expect(updated.readAt, isNotNull);
    expect(updated.isFavorite, isTrue);
    expect(updated.favoritedAt, isNotNull);
  });

  test('deletes a book together with cards and asset metadata', () async {
    final current = driver!;
    await current.repository.deleteBook(current.firstBookId);

    expect(
      await current.repository.loadBooksByIds([current.firstBookId]),
      isEmpty,
    );
    expect(
      await current.repository.loadOrderedCardIds([current.firstBookId]),
      isEmpty,
    );
    expect(
      await current.repository.loadBookAssets(
        bookId: current.firstBookId,
        assetKeys: [current.assetKey],
      ),
      isEmpty,
    );
  });
}
