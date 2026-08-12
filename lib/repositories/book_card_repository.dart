import 'dart:developer' as developer;

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_card_activity_event.dart';
import '../models/book_remark.dart';
import '../services/book_asset_store.dart';
import 'library_change_tracker.dart';
import 'library_repository.dart';
import 'library_snapshot.dart';

class BookCardRepository implements LibraryRepository {
  BookCardRepository(this.isar, {Isar? remarkIsar, BookAssetStore? assetStore})
    : _remarkIsar = remarkIsar,
      _assetStore = assetStore ?? BookAssetStore.instance;

  final Isar isar;
  final Isar? _remarkIsar;
  final BookAssetStore _assetStore;

  @override
  Future<List<Book>> loadBooks() {
    return isar.books.where().sortByCreatedAtDesc().findAll();
  }

  @override
  Future<List<Book>> loadBooksByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Book>[];

    final books = await Future.wait(ids.map(isar.books.get));
    return books.whereType<Book>().toList(growable: false);
  }

  @override
  Future<List<int>> loadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final idsByBook = await Future.wait(
      bookIds.map(_loadOrderedCardIdsForBook),
    );
    return idsByBook.expand((ids) => ids).toList(growable: false);
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<List<BookCardActivityEvent>> loadReadActivityEvents(
    List<int> bookIds,
  ) async {
    try {
      final events = await isar.txn(
        () => _loadReadActivityEventsByProjection(bookIds),
      );
      if (events != null) return events;
    } catch (error, stackTrace) {
      developer.log(
        'Read activity projection failed; falling back to full card load.',
        name: 'BookCardRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final cards = await loadReadCards(bookIds);
    return _readCardsToActivityEvents(cards);
  }

  @override
  Future<List<BookCardActivityEvent>> loadFavoriteActivityEvents(
    List<int> bookIds,
  ) async {
    try {
      final events = await isar.txn(
        () => _loadFavoriteActivityEventsByProjection(bookIds),
      );
      if (events != null) return events;
    } catch (error, stackTrace) {
      developer.log(
        'Favorite activity projection failed; falling back to full card load.',
        name: 'BookCardRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final cards = await loadFavoriteCards(bookIds);
    return _favoriteCardsToActivityEvents(cards);
  }

  Future<List<BookCardActivityEvent>?> _loadReadActivityEventsByProjection(
    List<int> bookIds,
  ) async {
    final ids = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .idProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .idProperty()
              .findAll();
    final projectedBookIds = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .bookIdProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .bookIdProperty()
              .findAll();
    final cardIndexes = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .cardIndexProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .cardIndexProperty()
              .findAll();
    final timestamps = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .readAtProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isReadEqualTo(true)
              .and()
              .readAtIsNotNull()
              .sortByReadAtDesc()
              .thenByIdDesc()
              .readAtProperty()
              .findAll();

    return _zipActivityEvents(
      ids: ids,
      bookIds: projectedBookIds,
      cardIndexes: cardIndexes,
      timestamps: timestamps,
      fallbackReason: 'read projection mismatch',
    );
  }

  Future<List<BookCardActivityEvent>?> _loadFavoriteActivityEventsByProjection(
    List<int> bookIds,
  ) async {
    final ids = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .idProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .idProperty()
              .findAll();
    final projectedBookIds = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .bookIdProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .bookIdProperty()
              .findAll();
    final cardIndexes = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .cardIndexProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .cardIndexProperty()
              .findAll();
    final timestamps = bookIds.isEmpty
        ? await isar.bookCards
              .filter()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .favoritedAtProperty()
              .findAll()
        : await isar.bookCards
              .filter()
              .anyOf(bookIds, (query, bookId) => query.bookIdEqualTo(bookId))
              .and()
              .isFavoriteEqualTo(true)
              .and()
              .favoritedAtIsNotNull()
              .sortByFavoritedAtDesc()
              .thenByIdDesc()
              .favoritedAtProperty()
              .findAll();

    return _zipActivityEvents(
      ids: ids,
      bookIds: projectedBookIds,
      cardIndexes: cardIndexes,
      timestamps: timestamps,
      fallbackReason: 'favorite projection mismatch',
    );
  }

  List<BookCardActivityEvent>? _zipActivityEvents({
    required List<int> ids,
    required List<int> bookIds,
    required List<int> cardIndexes,
    required List<DateTime?> timestamps,
    required String fallbackReason,
  }) {
    final length = ids.length;
    if (bookIds.length != length ||
        cardIndexes.length != length ||
        timestamps.length != length ||
        timestamps.any((timestamp) => timestamp == null)) {
      developer.log(
        '$fallbackReason: ids=${ids.length}, bookIds=${bookIds.length}, cardIndexes=${cardIndexes.length}, timestamps=${timestamps.length}',
        name: 'BookCardRepository',
      );
      return null;
    }

    return List<BookCardActivityEvent>.generate(
      length,
      (index) => BookCardActivityEvent(
        cardId: ids[index],
        bookId: bookIds[index],
        cardIndex: cardIndexes[index],
        timestamp: timestamps[index]!,
      ),
      growable: false,
    );
  }

  List<BookCardActivityEvent> _readCardsToActivityEvents(List<BookCard> cards) {
    final events = <BookCardActivityEvent>[];
    for (final card in cards) {
      final timestamp = card.readAt;
      if (timestamp == null) continue;
      events.add(
        BookCardActivityEvent(
          cardId: card.id,
          bookId: card.bookId,
          cardIndex: card.cardIndex,
          timestamp: timestamp,
        ),
      );
    }
    events.sort(_compareActivityEventsDesc);
    return List<BookCardActivityEvent>.unmodifiable(events);
  }

  List<BookCardActivityEvent> _favoriteCardsToActivityEvents(
    List<BookCard> cards,
  ) {
    final events = <BookCardActivityEvent>[];
    for (final card in cards) {
      final timestamp = card.favoritedAt;
      if (timestamp == null) continue;
      events.add(
        BookCardActivityEvent(
          cardId: card.id,
          bookId: card.bookId,
          cardIndex: card.cardIndex,
          timestamp: timestamp,
        ),
      );
    }
    events.sort(_compareActivityEventsDesc);
    return List<BookCardActivityEvent>.unmodifiable(events);
  }

  int _compareActivityEventsDesc(
    BookCardActivityEvent a,
    BookCardActivityEvent b,
  ) {
    final timestampCompare = b.timestamp.compareTo(a.timestamp);
    if (timestampCompare != 0) return timestampCompare;
    return b.cardId.compareTo(a.cardId);
  }

  @override
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

  @override
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

  @override
  Future<List<BookCard>> loadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final cards = await Future.wait(ids.map(isar.bookCards.get));
    return cards.whereType<BookCard>().toList(growable: false);
  }

  @override
  Future<List<BookCard>> loadUnreadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final cards = await Future.wait(ids.map(isar.bookCards.get));
    return cards
        .whereType<BookCard>()
        .where((card) => !card.isRead)
        .toList(growable: false);
  }

  @override
  Future<List<BookAsset>> loadBookAssets({
    required int bookId,
    required List<String> assetKeys,
  }) {
    if (assetKeys.isEmpty) return Future.value(const <BookAsset>[]);

    return isar.bookAssets
        .filter()
        .bookIdEqualTo(bookId)
        .anyOf(assetKeys, (query, key) => query.assetKeyEqualTo(key))
        .findAll();
  }

  @override
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

  @override
  Future<void> toggleFavorite(BookCard card) async {
    await isar.writeTxn(() async {
      card.isFavorite = !card.isFavorite;
      card.favoritedAt = card.isFavorite ? DateTime.now() : null;
      await isar.bookCards.put(card);
    });
    LibraryChangeTracker.instance.markChanged();
  }

  @override
  Future<void> toggleRead(BookCard card) async {
    await isar.writeTxn(() async {
      card.isRead = !card.isRead;
      card.readAt = card.isRead ? DateTime.now() : null;
      await isar.bookCards.put(card);
    });
    LibraryChangeTracker.instance.markChanged();
  }

  @override
  Future<void> deleteBook(int bookId) async {
    final book = await isar.books.get(bookId);
    final assetRootKey = book?.assetRootKey;

    await isar.writeTxn(() async {
      final cardIds = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .idProperty()
          .findAll();
      if (cardIds.isNotEmpty) {
        await isar.bookCards.deleteAll(cardIds);
      }
      final assetIds = await isar.bookAssets
          .filter()
          .bookIdEqualTo(bookId)
          .idProperty()
          .findAll();
      if (assetIds.isNotEmpty) {
        await isar.bookAssets.deleteAll(assetIds);
      }
      await isar.books.delete(bookId);
    });
    LibraryChangeTracker.instance.markChanged();

    try {
      await _assetStore.deleteAssetRoot(assetRootKey);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to delete book asset root: bookId=$bookId',
        name: 'BookCardRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<LibraryImportResult> importBookDraft(ImportBookDraft draft) async {
    final existingByFileHash = await _findBestCompleteBookByFileHash(
      fileHash: draft.fileHash,
      contentFingerprint: draft.contentFingerprint,
      cardCount: draft.cards.length,
    );
    if (existingByFileHash != null) {
      developer.log(
        'Duplicate import matched by fileHash: bookId=${existingByFileHash.id}',
        name: 'BookCardRepository',
      );
      return LibraryImportResult(
        book: existingByFileHash,
        insertedCards: 0,
        wasDuplicate: true,
        matchedBy: 'fileHash',
      );
    }

    final existingByFingerprint =
        await _findBookByContentFingerprintWithLegacyBackfill(
          contentFingerprint: draft.contentFingerprint,
          fileHash: draft.fileHash,
          sourceFileName: draft.sourceFileName,
          cardCount: draft.cards.length,
          textCharCount: draft.textCharCount,
        );
    if (existingByFingerprint != null) {
      developer.log(
        'Duplicate import matched by contentFingerprint: bookId=${existingByFingerprint.id}',
        name: 'BookCardRepository',
      );
      return LibraryImportResult(
        book: existingByFingerprint,
        insertedCards: 0,
        wasDuplicate: true,
        matchedBy: 'contentFingerprint',
      );
    }

    final book = Book()
      ..title = draft.title
      ..createdAt = draft.createdAt
      ..fileHash = draft.fileHash
      ..contentFingerprint = draft.contentFingerprint
      ..sourceFileName = draft.sourceFileName
      ..importedAt = draft.importedAt
      ..cardCount = draft.cardCount
      ..textCharCount = draft.textCharCount
      ..assetRootKey = draft.assetRootKey;

    final bookId = await isar.writeTxn(() async {
      final newBookId = await isar.books.put(book);
      final cards = draft.cards
          .map((card) {
            return BookCard()
              ..bookId = newBookId
              ..bookTitle = card.bookTitle
              ..cardIndex = card.cardIndex
              ..chapterIndex = card.chapterIndex
              ..chapterCardIndex = card.chapterCardIndex
              ..chapterTitle = card.chapterTitle
              ..content = card.content
              ..blocksJson = card.blocksJson;
          })
          .toList(growable: false);
      final assets = draft.assets
          .map((asset) {
            return BookAsset()
              ..bookId = newBookId
              ..assetKey = asset.assetKey
              ..originalHref = asset.originalHref
              ..normalizedHref = asset.normalizedHref
              ..mimeType = asset.mimeType
              ..relativePath = asset.relativePath
              ..byteLength = asset.byteLength
              ..createdAt = draft.importedAt;
          })
          .toList(growable: false);
      if (assets.isNotEmpty) {
        await isar.bookAssets.putAll(assets);
      }
      await isar.bookCards.putAll(cards);
      return newBookId;
    });

    LibraryChangeTracker.instance.markChanged();
    return LibraryImportResult(
      book: book..id = bookId,
      insertedCards: draft.cards.length,
      wasDuplicate: false,
      matchedBy: null,
    );
  }

  Future<Book?> _findBestCompleteBookByFileHash({
    required String fileHash,
    required String contentFingerprint,
    required int cardCount,
  }) async {
    final matches = await isar.books
        .filter()
        .fileHashEqualTo(fileHash)
        .findAll();
    if (matches.isEmpty) return null;

    final completeMatches = <Book>[];
    for (final book in matches) {
      final actualCardCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .count();
      if (actualCardCount != cardCount) {
        developer.log(
          'Skipping incomplete fileHash duplicate: bookId=${book.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'BookCardRepository',
        );
        continue;
      }

      if (book.contentFingerprint == contentFingerprint) {
        completeMatches.add(book);
        continue;
      }

      if (book.contentFingerprint == null) {
        final cards = await isar.bookCards
            .filter()
            .bookIdEqualTo(book.id)
            .sortByCardIndex()
            .findAll();
        if (LibraryContentIdentity.contentFingerprintForCards(cards) ==
            contentFingerprint) {
          completeMatches.add(book);
        }
      }
    }

    if (completeMatches.isEmpty) return null;
    return _bestDuplicateMatch(completeMatches);
  }

  Future<Book?> _findBookByContentFingerprintWithLegacyBackfill({
    required String contentFingerprint,
    required String fileHash,
    required String? sourceFileName,
    required int cardCount,
    required int textCharCount,
  }) async {
    final matches = await isar.books
        .filter()
        .contentFingerprintEqualTo(contentFingerprint)
        .findAll();
    final completeMatches = <Book>[];
    for (final book in matches) {
      final actualCardCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .count();
      if (actualCardCount == cardCount) {
        completeMatches.add(book);
      } else {
        developer.log(
          'Skipping incomplete contentFingerprint duplicate: bookId=${book.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'BookCardRepository',
        );
      }
    }

    final legacyBooks = await isar.books
        .filter()
        .contentFingerprintIsNull()
        .findAll();
    for (final legacyBook in legacyBooks) {
      final legacyCards = await isar.bookCards
          .filter()
          .bookIdEqualTo(legacyBook.id)
          .sortByCardIndex()
          .findAll();
      if (legacyCards.isEmpty) continue;

      final legacyFingerprint =
          LibraryContentIdentity.contentFingerprintForCards(legacyCards);
      final legacyTextCharCount = LibraryContentIdentity.textCharCountForCards(
        legacyCards,
      );
      final isMatch = legacyFingerprint == contentFingerprint;
      await _fillMissingIdentity(
        book: legacyBook,
        contentFingerprint: legacyFingerprint,
        fileHash: null,
        sourceFileName: null,
        cardCount: legacyCards.length,
        textCharCount: legacyTextCharCount,
      );

      if (isMatch && legacyCards.length == cardCount) {
        completeMatches.add(legacyBook);
      } else if (isMatch) {
        developer.log(
          'Skipping incomplete legacy duplicate: bookId=${legacyBook.id}, actualCards=${legacyCards.length}, expectedCards=$cardCount',
          name: 'BookCardRepository',
        );
      }
    }

    if (completeMatches.isEmpty) return null;
    final best = await _bestDuplicateMatch(completeMatches);
    await _fillMissingIdentity(
      book: best,
      contentFingerprint: contentFingerprint,
      fileHash: fileHash,
      sourceFileName: sourceFileName,
      cardCount: cardCount,
      textCharCount: textCharCount,
    );
    return best;
  }

  Future<Book> _bestDuplicateMatch(List<Book> matches) async {
    if (matches.length == 1) return matches.single;

    Book? best;
    var bestScore = -1;
    for (final book in matches) {
      final readCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .and()
          .isReadEqualTo(true)
          .count();
      final favoriteCount = await isar.bookCards
          .filter()
          .bookIdEqualTo(book.id)
          .and()
          .isFavoriteEqualTo(true)
          .count();
      final score = favoriteCount * 1000000 + readCount;
      if (score > bestScore) {
        best = book;
        bestScore = score;
      }
    }

    return best ?? matches.first;
  }

  Future<void> _fillMissingIdentity({
    required Book book,
    required String contentFingerprint,
    String? fileHash,
    required String? sourceFileName,
    required int cardCount,
    required int textCharCount,
  }) async {
    final needsUpdate =
        book.contentFingerprint == null ||
        (fileHash != null && book.fileHash == null) ||
        (sourceFileName != null && book.sourceFileName == null) ||
        book.cardCount == null ||
        book.textCharCount == null ||
        book.importedAt == null;
    if (!needsUpdate) {
      return;
    }

    await isar.writeTxn(() async {
      book.contentFingerprint ??= contentFingerprint;
      if (fileHash != null) book.fileHash ??= fileHash;
      if (sourceFileName != null) book.sourceFileName ??= sourceFileName;
      book.importedAt ??= book.createdAt;
      book.cardCount ??= cardCount;
      book.textCharCount ??= textCharCount;
      await isar.books.put(book);
    });
  }

  @override
  Future<Map<int, String>> loadRemarks() async {
    final remarkIsar = _remarkIsar;
    if (remarkIsar == null) return const <int, String>{};

    final remarks = await remarkIsar.bookRemarks.where().findAll();
    return {
      for (final remark in remarks)
        if (remark.title.trim().isNotEmpty) remark.id: remark.title.trim(),
    };
  }

  @override
  Future<void> saveRemark(int bookId, String remark) async {
    final remarkIsar = _remarkIsar;
    if (remarkIsar == null) {
      throw StateError('Remark repository is not configured for Isar.');
    }

    final trimmed = remark.trim();
    await remarkIsar.writeTxn(() async {
      if (trimmed.isEmpty) {
        await remarkIsar.bookRemarks.delete(bookId);
        return;
      }

      await remarkIsar.bookRemarks.put(
        BookRemark()
          ..id = bookId
          ..title = trimmed
          ..updatedAt = DateTime.now(),
      );
    });
    LibraryChangeTracker.instance.markChanged();
  }

  @override
  Future<void> removeRemark(int bookId) async {
    final remarkIsar = _remarkIsar;
    if (remarkIsar == null) return;

    final deleted = await remarkIsar.writeTxn(
      () => remarkIsar.bookRemarks.delete(bookId),
    );
    if (deleted) {
      LibraryChangeTracker.instance.markChanged();
    }
  }

  @override
  Future<LibraryBackupSnapshot> buildBackupSnapshot() async {
    final remarkIsar = _remarkIsar;
    final remarks = remarkIsar == null
        ? const <BookRemarkSnapshot>[]
        : (await remarkIsar.bookRemarks.where().findAll())
              .map(
                (remark) => BookRemarkSnapshot(
                  bookId: remark.id,
                  title: remark.title,
                  updatedAt: remark.updatedAt,
                ),
              )
              .toList(growable: false);

    return LibraryBackupSnapshot(
      books: await isar.books.where().findAll(),
      bookCards: await isar.bookCards.where().findAll(),
      bookAssets: await isar.bookAssets.where().findAll(),
      bookRemarks: remarks,
    );
  }

  @override
  Future<void> checkpoint() async {}

  @override
  Future<void> close() async {
    await isar.close();
    await _remarkIsar?.close();
  }
}
