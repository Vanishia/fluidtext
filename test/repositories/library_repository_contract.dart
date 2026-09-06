import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/repositories/library_repository.dart';
import 'package:fluidtext/repositories/library_snapshot.dart';

abstract interface class LibraryRepositoryContractDriver {
  LibraryRepository get repository;

  int get firstBookId;

  int get secondBookId;

  int get firstCardId;

  int get secondCardId;

  int get thirdCardId;

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
        [current.firstCardId, current.secondCardId, current.thirdCardId],
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
      expect(stats[current.firstBookId]?.totalCount, 3);
      expect(stats[current.firstBookId]?.readCount, 2);
      expect(stats[current.firstBookId]?.favoriteCount, 2);
    },
  );

  test(
    'loads cards by caller order and keeps activity tie breakers stable',
    () async {
      final current = driver!;
      final cards = await current.repository.loadCardsByIds([
        current.thirdCardId,
        current.firstCardId,
        current.secondCardId,
      ]);
      expect(cards.map((card) => card.id), [
        current.thirdCardId,
        current.firstCardId,
        current.secondCardId,
      ]);

      final readEvents = await current.repository.loadReadActivityEvents([
        current.firstBookId,
      ]);
      expect(readEvents.map((event) => event.cardId), [
        current.thirdCardId,
        current.secondCardId,
      ]);

      final favoriteEvents = await current.repository
          .loadFavoriteActivityEvents([current.firstBookId]);
      expect(favoriteEvents.map((event) => event.cardId), [
        current.thirdCardId,
        current.secondCardId,
      ]);
    },
  );

  test('paginates read and favorite cards and reports totals', () async {
    final current = driver!;
    final repository = current.repository;

    expect(await repository.countReadCards([current.firstBookId]), 2);
    expect(await repository.countFavoriteCards([current.firstBookId]), 2);

    final readFirstPage = await repository.loadReadCards([
      current.firstBookId,
    ], limit: 1);
    expect(readFirstPage.map((card) => card.id), [current.thirdCardId]);

    final readSecondPage = await repository.loadReadCards(
      [current.firstBookId],
      offset: 1,
      limit: 1,
    );
    expect(readSecondPage.map((card) => card.id), [current.secondCardId]);

    final readTail = await repository.loadReadCards(
      [current.firstBookId],
      offset: 2,
      limit: 1,
    );
    expect(readTail, isEmpty);

    final favoriteSecondPage = await repository.loadFavoriteCards(
      [current.firstBookId],
      offset: 1,
      limit: 1,
    );
    expect(favoriteSecondPage.map((card) => card.id), [current.secondCardId]);
  });

  test('filters read and favorite cards by activity range and sort', () async {
    final current = driver!;
    final repository = current.repository;
    final bookIds = [current.firstBookId];

    // 种子数据：已读于 2026-01-02、收藏于 2026-01-03；范围含 from、不含 to。
    expect(
      await repository.countReadCards(
        bookIds,
        from: DateTime(2026, 1, 2),
        to: DateTime(2026, 1, 3),
      ),
      2,
    );
    expect(
      await repository.countReadCards(bookIds, to: DateTime(2026, 1, 2)),
      0,
    );
    expect(
      await repository.countFavoriteCards(bookIds, from: DateTime(2026, 1, 4)),
      0,
    );

    // 从旧到新：时间相同按 id 升序兜底。
    final ascending = await repository.loadReadCards(
      bookIds,
      sort: CardListSort.activityAsc,
    );
    expect(ascending.map((card) => card.id), [
      current.secondCardId,
      current.thirdCardId,
    ]);

    // 卡片顺序：按书籍、卡片序号升序。
    final cardOrder = await repository.loadFavoriteCards(
      bookIds,
      sort: CardListSort.cardOrder,
    );
    expect(cardOrder.map((card) => card.id), [
      current.secondCardId,
      current.thirdCardId,
    ]);

    // 过滤 + 排序组合：时间倒序时 id 倒序兜底。
    final ranged = await repository.loadReadCards(
      bookIds,
      from: DateTime(2026, 1, 2),
      to: DateTime(2026, 1, 3),
      sort: CardListSort.activityDesc,
    );
    expect(ranged.map((card) => card.id), [
      current.thirdCardId,
      current.secondCardId,
    ]);
  });

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
        current.thirdCardId,
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

  test('persists remarks through the storage-neutral API', () async {
    final current = driver!;

    await current.repository.saveRemark(current.firstBookId, '  Alias  ');
    expect(await current.repository.loadRemarks(), {
      current.firstBookId: 'Alias',
    });

    await current.repository.removeRemark(current.firstBookId);
    expect(
      await current.repository.loadRemarks(),
      isNot(contains(current.firstBookId)),
    );
  });

  test('exports a storage-neutral backup snapshot', () async {
    final current = driver!;
    await current.repository.saveRemark(current.firstBookId, 'Snapshot title');

    final snapshot = await current.repository.buildBackupSnapshot();

    expect(
      snapshot.books.map((book) => book.id),
      contains(current.firstBookId),
    );
    expect(
      snapshot.bookCards.map((card) => card.id),
      containsAll([current.firstCardId, current.secondCardId]),
    );
    expect(
      snapshot.bookAssets.map((asset) => asset.assetKey),
      contains(current.assetKey),
    );
    expect(snapshot.bookRemarks.single.bookId, current.firstBookId);
    expect(snapshot.bookRemarks.single.title, 'Snapshot title');
  });

  test('imports a neutral draft transaction and detects duplicates', () async {
    final current = driver!;
    const cards = [
      BookCardDraft(
        bookTitle: 'Draft book',
        cardIndex: 0,
        chapterIndex: 0,
        chapterCardIndex: 0,
        chapterTitle: 'Start',
        content: 'Draft first card.',
        blocksJson: null,
      ),
      BookCardDraft(
        bookTitle: 'Draft book',
        cardIndex: 1,
        chapterIndex: 0,
        chapterCardIndex: 1,
        chapterTitle: 'Start',
        content: 'Draft second card.',
        blocksJson: null,
      ),
    ];
    final draft = ImportBookDraft(
      title: 'Draft book',
      createdAt: DateTime(2026, 4, 1),
      fileHash: 'contract-draft-file-hash',
      contentFingerprint:
          LibraryContentIdentity.contentFingerprintForCardDrafts(cards),
      sourceFileName: 'draft.epub',
      importedAt: DateTime(2026, 4, 1, 1),
      cardCount: cards.length,
      textCharCount: cards.fold<int>(
        0,
        (sum, card) =>
            sum +
            LibraryContentIdentity.normalizeForFingerprint(card.content).length,
      ),
      assetRootKey: null,
      cards: cards,
      assets: const [],
    );

    final inserted = await current.repository.importBookDraft(draft);
    expect(inserted.wasDuplicate, isFalse);
    expect(inserted.insertedCards, cards.length);
    expect(
      await current.repository.loadOrderedCardIds([inserted.book.id]),
      hasLength(cards.length),
    );

    final duplicate = await current.repository.importBookDraft(draft);
    expect(duplicate.wasDuplicate, isTrue);
    expect(duplicate.book.id, inserted.book.id);
    expect(duplicate.insertedCards, 0);
    expect(duplicate.matchedBy, 'fileHash');
  });
}
