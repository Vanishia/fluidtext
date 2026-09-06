import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../../models/book.dart';
import '../../models/book_asset.dart';
import '../../models/book_card.dart';
import '../../models/book_card_activity_event.dart';
import '../../repositories/library_change_tracker.dart';
import '../../repositories/library_repository.dart';
import '../../repositories/library_snapshot.dart';
import '../../services/app_logger.dart';
import '../../services/book_asset_store.dart';
import 'library_database.dart';

class SqliteLibraryRepository implements LibraryRepository {
  SqliteLibraryRepository(
    this.database, {
    BookAssetStore? assetStore,
    LibraryChangeTracker? changeTracker,
  }) : _assetStore = assetStore ?? BookAssetStore.instance,
       _changeTracker = changeTracker ?? LibraryChangeTracker.instance;

  final LibraryDatabase database;
  final BookAssetStore _assetStore;
  final LibraryChangeTracker _changeTracker;

  @override
  Future<List<Book>> loadBooks() async {
    final rows =
        await (database.select(database.sqliteBooks)..orderBy([
              (table) => OrderingTerm.desc(table.createdAtMs),
              (table) => OrderingTerm.desc(table.id),
            ]))
            .get();
    return rows.map(_bookFromRow).toList(growable: false);
  }

  @override
  Future<List<Book>> loadBooksByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Book>[];

    final rows = await (database.select(
      database.sqliteBooks,
    )..where((table) => table.id.isIn(ids))).get();
    final byId = {for (final row in rows) row.id: _bookFromRow(row)};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  @override
  Future<List<int>> loadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final idsByBook = await _loadOrderedCardIdsByBook(
      bookIds: bookIds,
      unreadOnly: false,
    );
    return [
      for (final bookId in bookIds) ...idsByBook[bookId] ?? const <int>[],
    ];
  }

  @override
  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int>[];

    final idsByBook = await _loadOrderedCardIdsByBook(
      bookIds: bookIds,
      unreadOnly: true,
    );
    return [
      for (final bookId in bookIds) ...idsByBook[bookId] ?? const <int>[],
    ];
  }

  Future<Map<int, List<int>>> _loadOrderedCardIdsByBook({
    required List<int> bookIds,
    required bool unreadOnly,
  }) async {
    final query = StringBuffer('''
      SELECT book_id, id
      FROM book_cards
      WHERE book_id IN (${_placeholders(bookIds.length)})
      ''');
    if (unreadOnly) {
      query.write(' AND is_read = 0');
    }
    query.write(' ORDER BY book_id ASC, card_index ASC');

    final rows = await database
        .customSelect(
          query.toString(),
          variables: _variables(bookIds),
          readsFrom: {database.sqliteBookCards},
        )
        .get();
    final idsByBook = <int, List<int>>{};
    for (final row in rows) {
      final bookId = row.read<int>('book_id');
      idsByBook.putIfAbsent(bookId, () => <int>[]).add(row.read<int>('id'));
    }
    return idsByBook;
  }

  @override
  Future<List<BookCard>> loadReadCards(
    List<int> bookIds, {
    int offset = 0,
    int? limit,
    DateTime? from,
    DateTime? to,
    CardListSort sort = CardListSort.activityDesc,
  }) {
    return _loadCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_read',
      timestampColumn: 'read_at_ms',
      offset: offset,
      limit: limit,
      from: from,
      to: to,
      sort: sort,
    );
  }

  @override
  Future<List<BookCard>> loadFavoriteCards(
    List<int> bookIds, {
    int offset = 0,
    int? limit,
    DateTime? from,
    DateTime? to,
    CardListSort sort = CardListSort.activityDesc,
  }) {
    return _loadCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_favorite',
      timestampColumn: 'favorited_at_ms',
      offset: offset,
      limit: limit,
      from: from,
      to: to,
      sort: sort,
    );
  }

  @override
  Future<int> countReadCards(
    List<int> bookIds, {
    DateTime? from,
    DateTime? to,
  }) {
    return _countCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_read',
      timestampColumn: 'read_at_ms',
      from: from,
      to: to,
    );
  }

  @override
  Future<int> countFavoriteCards(
    List<int> bookIds, {
    DateTime? from,
    DateTime? to,
  }) {
    return _countCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_favorite',
      timestampColumn: 'favorited_at_ms',
      from: from,
      to: to,
    );
  }

  Future<int> _countCardsWithState({
    required List<int> bookIds,
    required String stateColumn,
    required String timestampColumn,
    DateTime? from,
    DateTime? to,
  }) async {
    final query = StringBuffer(
      'SELECT COUNT(*) AS count FROM book_cards WHERE $stateColumn = 1',
    );
    final variables = <Variable<Object>>[];
    if (bookIds.isNotEmpty) {
      query.write(' AND book_id IN (${_placeholders(bookIds.length)})');
      variables.addAll(_variables(bookIds));
    }
    _appendActivityRange(
      query,
      variables,
      timestampColumn: timestampColumn,
      from: from,
      to: to,
    );

    final row = await database
        .customSelect(
          query.toString(),
          variables: variables,
          readsFrom: {database.sqliteBookCards},
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<List<BookCard>> _loadCardsWithState({
    required List<int> bookIds,
    required String stateColumn,
    required String timestampColumn,
    int offset = 0,
    int? limit,
    DateTime? from,
    DateTime? to,
    CardListSort sort = CardListSort.activityDesc,
  }) async {
    final query = StringBuffer(
      'SELECT * FROM book_cards WHERE $stateColumn = 1',
    );
    final variables = <Variable<Object>>[];
    if (bookIds.isNotEmpty) {
      query.write(' AND book_id IN (${_placeholders(bookIds.length)})');
      variables.addAll(_variables(bookIds));
    }
    _appendActivityRange(
      query,
      variables,
      timestampColumn: timestampColumn,
      from: from,
      to: to,
    );
    switch (sort) {
      case CardListSort.activityDesc:
        query.write(' ORDER BY $timestampColumn DESC, id DESC');
      case CardListSort.activityAsc:
        query.write(' ORDER BY $timestampColumn ASC, id ASC');
      case CardListSort.cardOrder:
        query.write(' ORDER BY book_id ASC, card_index ASC');
    }
    if (limit != null || offset > 0) {
      // LIMIT -1 表示不限制行数，仅用于配合 OFFSET。
      query.write(' LIMIT ? OFFSET ?');
      variables.add(Variable<int>(limit ?? -1));
      variables.add(Variable<int>(offset));
    }

    final rows = await database
        .customSelect(
          query.toString(),
          variables: variables,
          readsFrom: {database.sqliteBookCards},
        )
        .get();
    return rows.map(_bookCardFromQueryRow).toList(growable: false);
  }

  /// 动作时间范围过滤：含 from、不含 to；时间为空的卡片被排除。
  static void _appendActivityRange(
    StringBuffer query,
    List<Variable<Object>> variables, {
    required String timestampColumn,
    required DateTime? from,
    required DateTime? to,
  }) {
    if (from != null) {
      query.write(' AND $timestampColumn >= ?');
      variables.add(Variable<int>(from.millisecondsSinceEpoch));
    }
    if (to != null) {
      query.write(' AND $timestampColumn < ?');
      variables.add(Variable<int>(to.millisecondsSinceEpoch));
    }
  }

  @override
  Future<List<BookCardActivityEvent>> loadReadActivityEvents(
    List<int> bookIds,
  ) {
    return _loadActivityEvents(
      bookIds: bookIds,
      stateColumn: 'is_read',
      timestampColumn: 'read_at_ms',
    );
  }

  @override
  Future<List<BookCardActivityEvent>> loadFavoriteActivityEvents(
    List<int> bookIds,
  ) {
    return _loadActivityEvents(
      bookIds: bookIds,
      stateColumn: 'is_favorite',
      timestampColumn: 'favorited_at_ms',
    );
  }

  Future<List<BookCardActivityEvent>> _loadActivityEvents({
    required List<int> bookIds,
    required String stateColumn,
    required String timestampColumn,
  }) async {
    final query = StringBuffer('''
      SELECT id, book_id, card_index, $timestampColumn AS timestamp_ms
      FROM book_cards
      WHERE $stateColumn = 1 AND $timestampColumn IS NOT NULL
      ''');
    final variables = <Variable<Object>>[];
    if (bookIds.isNotEmpty) {
      query.write(' AND book_id IN (${_placeholders(bookIds.length)})');
      variables.addAll(_variables(bookIds));
    }
    query.write(' ORDER BY $timestampColumn DESC, id DESC');

    final rows = await database
        .customSelect(
          query.toString(),
          variables: variables,
          readsFrom: {database.sqliteBookCards},
        )
        .get();
    return rows
        .map(
          (row) => BookCardActivityEvent(
            cardId: row.read<int>('id'),
            bookId: row.read<int>('book_id'),
            cardIndex: row.read<int>('card_index'),
            timestamp: _dateFromMs(row.read<int>('timestamp_ms')),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds) async {
    if (bookIds.isEmpty) return const <int, BookCardStats>{};

    final result = <int, BookCardStats>{
      for (final bookId in bookIds) bookId: BookCardStats.empty,
    };
    final rows = await database
        .customSelect(
          '''
      SELECT
        book_id,
        COUNT(*) AS total_count,
        SUM(CASE WHEN is_read = 1 THEN 1 ELSE 0 END) AS read_count,
        SUM(CASE WHEN is_favorite = 1 THEN 1 ELSE 0 END) AS favorite_count
      FROM book_cards
      WHERE book_id IN (${_placeholders(bookIds.length)})
      GROUP BY book_id
      ''',
          variables: _variables(bookIds),
          readsFrom: {database.sqliteBookCards},
        )
        .get();

    for (final row in rows) {
      result[row.read<int>('book_id')] = BookCardStats(
        totalCount: row.read<int>('total_count'),
        readCount: row.read<int>('read_count'),
        favoriteCount: row.read<int>('favorite_count'),
      );
    }
    return result;
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
    final unknownFavoriteTime = await database
        .customSelect(
          '''
      SELECT COUNT(*) AS count
      FROM book_cards
      WHERE is_favorite = 1 AND favorited_at_ms IS NULL
      ''',
          readsFrom: {database.sqliteBookCards},
        )
        .getSingle();

    developer.log(
      'DB snapshot [$reason]: books=${books.length}, cards=$totalCards, read=$totalRead, favorites=$totalFavorites, favoritesWithoutTime=${unknownFavoriteTime.read<int>('count')}',
      name: 'SqliteLibraryRepository',
    );

    for (final book in books) {
      final item = stats[book.id] ?? BookCardStats.empty;
      developer.log(
        'Book id=${book.id}, title="${book.title}", cards=${item.totalCount}, read=${item.readCount}, favorites=${item.favoriteCount}, fileHash=${book.fileHash != null ? 'yes' : 'no'}, contentFingerprint=${book.contentFingerprint != null ? 'yes' : 'no'}, createdAt=${book.createdAt.toIso8601String()}',
        name: 'SqliteLibraryRepository',
      );
    }
  }

  @override
  Future<List<BookCard>> loadCardsByIds(List<int> ids) async {
    if (ids.isEmpty) return const <BookCard>[];

    final rows = await (database.select(
      database.sqliteBookCards,
    )..where((table) => table.id.isIn(ids))).get();
    final byId = {for (final row in rows) row.id: _bookCardFromRow(row)};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  @override
  Future<List<BookCard>> loadUnreadCardsByIds(List<int> ids) async {
    final cards = await loadCardsByIds(ids);
    return cards.where((card) => !card.isRead).toList(growable: false);
  }

  @override
  Future<List<BookAsset>> loadBookAssets({
    required int bookId,
    required List<String> assetKeys,
  }) async {
    if (assetKeys.isEmpty) return const <BookAsset>[];

    final rows =
        await (database.select(database.sqliteBookAssets)..where(
              (table) =>
                  table.bookId.equals(bookId) & table.assetKey.isIn(assetKeys),
            ))
            .get();
    final byKey = {
      for (final row in rows) row.assetKey: _bookAssetFromRow(row),
    };
    return [
      for (final key in assetKeys)
        if (byKey[key] != null) byKey[key]!,
    ];
  }

  @override
  Future<List<BookCard>> loadContextCards({
    required int bookId,
    required int centerCardIndex,
    required int before,
    required int after,
  }) async {
    final start = centerCardIndex - before;
    final end = centerCardIndex + after;
    final rows =
        await (database.select(database.sqliteBookCards)
              ..where(
                (table) =>
                    table.bookId.equals(bookId) &
                    table.cardIndex.isBiggerOrEqualValue(start) &
                    table.cardIndex.isSmallerOrEqualValue(end),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.cardIndex)]))
            .get();
    return rows.map(_bookCardFromRow).toList(growable: false);
  }

  @override
  Future<void> toggleFavorite(BookCard card) async {
    final nextValue = !card.isFavorite;
    final timestamp = nextValue ? DateTime.now() : null;

    await database.transaction(() async {
      await database.customStatement(
        '''
        UPDATE book_cards
        SET is_favorite = ?, favorited_at_ms = ?
        WHERE id = ?
        ''',
        [nextValue ? 1 : 0, _msFromDate(timestamp), card.id],
      );
    });
    card.isFavorite = nextValue;
    card.favoritedAt = timestamp;
    _changeTracker.markChanged();
  }

  @override
  Future<void> toggleRead(BookCard card) async {
    final nextValue = !card.isRead;
    final timestamp = nextValue ? DateTime.now() : null;

    await database.transaction(() async {
      await database.customStatement(
        '''
        UPDATE book_cards
        SET is_read = ?, read_at_ms = ?
        WHERE id = ?
        ''',
        [nextValue ? 1 : 0, _msFromDate(timestamp), card.id],
      );
    });
    card.isRead = nextValue;
    card.readAt = timestamp;
    _changeTracker.markChanged();
  }

  @override
  Future<void> deleteBook(int bookId) async {
    final books = await loadBooksByIds([bookId]);
    final book = books.isEmpty ? null : books.first;
    await database.transaction(() async {
      await database.customStatement('DELETE FROM books WHERE id = ?', [
        bookId,
      ]);
    });
    _changeTracker.markChanged();

    try {
      await _assetStore.deleteAssetRoot(book?.assetRootKey);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to delete book asset root: bookId=$bookId',
        name: 'SqliteLibraryRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<Book>> pruneIncompleteBooks() async {
    final books = await loadBooks();
    final actualCounts = await _cardCountsByBook();
    final incomplete = <Book>[
      for (final book in books)
        if (_isIncompleteImport(book, actualCounts[book.id] ?? 0)) book,
    ];

    for (final book in incomplete) {
      AppLogger.instance.warning(
        'SqliteLibraryRepository',
        'Pruning incomplete imported book: bookId=${book.id}, '
            'title="${book.title}", recordedCards=${book.cardCount}, '
            'actualCards=${actualCounts[book.id] ?? 0}',
      );
      await deleteBook(book.id);
    }

    // Asset roots referenced by no book are staging leftovers from imports
    // that were killed mid-flight.
    final retainedRootKeys = <String>{
      for (final book in await loadBooks())
        if ((book.assetRootKey ?? '').trim().isNotEmpty)
          book.assetRootKey!.trim(),
    };
    await _assetStore.deleteOrphanAssetRoots(activeRootKeys: retainedRootKeys);

    return incomplete;
  }

  /// A book is incomplete when its cards are missing entirely, or fewer than
  /// the count recorded at import time. A null recorded count (legacy rows)
  /// cannot be judged and is treated as complete.
  static bool _isIncompleteImport(Book book, int actualCardCount) {
    if (actualCardCount <= 0) return true;
    final recorded = book.cardCount;
    return recorded != null && recorded != actualCardCount;
  }

  Future<Map<int, int>> _cardCountsByBook() async {
    final rows = await database
        .customSelect(
          'SELECT book_id AS bookId, COUNT(*) AS cardCount '
          'FROM book_cards GROUP BY book_id',
          readsFrom: {database.sqliteBookCards},
        )
        .get();
    return <int, int>{
      for (final row in rows)
        row.read<int>('bookId'): row.read<int>('cardCount'),
    };
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
        name: 'SqliteLibraryRepository',
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
        name: 'SqliteLibraryRepository',
      );
      return LibraryImportResult(
        book: existingByFingerprint,
        insertedCards: 0,
        wasDuplicate: true,
        matchedBy: 'contentFingerprint',
      );
    }

    late final int bookId;
    await database.transaction(() async {
      bookId = await database
          .into(database.sqliteBooks)
          .insert(
            SqliteBooksCompanion.insert(
              title: draft.title,
              createdAtMs: _msFromDate(draft.createdAt)!,
              fileHash: Value(draft.fileHash),
              contentFingerprint: Value(draft.contentFingerprint),
              sourceFileName: Value(draft.sourceFileName),
              importedAtMs: Value(_msFromDate(draft.importedAt)),
              cardCount: Value(draft.cardCount),
              textCharCount: Value(draft.textCharCount),
              assetRootKey: Value(draft.assetRootKey),
            ),
          );

      await database.batch((batch) {
        if (draft.assets.isNotEmpty) {
          batch.insertAll(database.sqliteBookAssets, [
            for (final asset in draft.assets)
              SqliteBookAssetsCompanion.insert(
                bookId: bookId,
                assetKey: asset.assetKey,
                originalHref: Value(asset.originalHref),
                normalizedHref: Value(asset.normalizedHref),
                mimeType: Value(asset.mimeType),
                relativePath: asset.relativePath,
                byteLength: Value(asset.byteLength),
                createdAtMs: _msFromDate(draft.importedAt)!,
              ),
          ]);
        }

        batch.insertAll(database.sqliteBookCards, [
          for (final card in draft.cards)
            SqliteBookCardsCompanion.insert(
              bookId: bookId,
              bookTitle: card.bookTitle,
              cardIndex: card.cardIndex,
              chapterIndex: card.chapterIndex,
              chapterCardIndex: card.chapterCardIndex,
              chapterTitle: Value(card.chapterTitle),
              content: card.content,
              blocksJson: Value(card.blocksJson),
              isRead: false,
              isFavorite: false,
            ),
        ]);
      });
    });

    _changeTracker.markChanged();
    final inserted = (await loadBooksByIds([bookId])).single;
    return LibraryImportResult(
      book: inserted,
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
    final rows = await (database.select(
      database.sqliteBooks,
    )..where((table) => table.fileHash.equals(fileHash))).get();
    if (rows.isEmpty) return null;

    final completeMatches = <Book>[];
    for (final row in rows) {
      final actualCardCount = await _cardCountForBook(row.id);
      if (actualCardCount != cardCount) {
        developer.log(
          'Skipping incomplete fileHash duplicate: bookId=${row.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'SqliteLibraryRepository',
        );
        continue;
      }

      if (row.contentFingerprint == contentFingerprint) {
        completeMatches.add(_bookFromRow(row));
        continue;
      }

      if (row.contentFingerprint == null) {
        final cards = await _loadCardsForBook(row.id);
        if (LibraryContentIdentity.contentFingerprintForCards(cards) ==
            contentFingerprint) {
          completeMatches.add(_bookFromRow(row));
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
    final matches =
        await (database.select(database.sqliteBooks)..where(
              (table) => table.contentFingerprint.equals(contentFingerprint),
            ))
            .get();
    final completeMatches = <Book>[];
    for (final row in matches) {
      final actualCardCount = await _cardCountForBook(row.id);
      if (actualCardCount == cardCount) {
        completeMatches.add(_bookFromRow(row));
      } else {
        developer.log(
          'Skipping incomplete contentFingerprint duplicate: bookId=${row.id}, actualCards=$actualCardCount, expectedCards=$cardCount',
          name: 'SqliteLibraryRepository',
        );
      }
    }

    final legacyRows = await (database.select(
      database.sqliteBooks,
    )..where((table) => table.contentFingerprint.isNull())).get();
    for (final row in legacyRows) {
      final legacyCards = await _loadCardsForBook(row.id);
      if (legacyCards.isEmpty) continue;

      final legacyFingerprint =
          LibraryContentIdentity.contentFingerprintForCards(legacyCards);
      final legacyTextCharCount = LibraryContentIdentity.textCharCountForCards(
        legacyCards,
      );
      final isMatch = legacyFingerprint == contentFingerprint;
      await _fillMissingIdentity(
        bookId: row.id,
        contentFingerprint: legacyFingerprint,
        fileHash: null,
        sourceFileName: null,
        cardCount: legacyCards.length,
        textCharCount: legacyTextCharCount,
      );

      if (isMatch && legacyCards.length == cardCount) {
        completeMatches.add(
          _bookFromRow(row).toBackfilledIdentity(
            contentFingerprint: legacyFingerprint,
            cardCount: legacyCards.length,
            textCharCount: legacyTextCharCount,
          ),
        );
      } else if (isMatch) {
        developer.log(
          'Skipping incomplete legacy duplicate: bookId=${row.id}, actualCards=${legacyCards.length}, expectedCards=$cardCount',
          name: 'SqliteLibraryRepository',
        );
      }
    }

    if (completeMatches.isEmpty) return null;
    final best = await _bestDuplicateMatch(completeMatches);
    await _fillMissingIdentity(
      bookId: best.id,
      contentFingerprint: contentFingerprint,
      fileHash: fileHash,
      sourceFileName: sourceFileName,
      cardCount: cardCount,
      textCharCount: textCharCount,
    );
    return (await loadBooksByIds([best.id])).single;
  }

  Future<int> _cardCountForBook(int bookId) async {
    final row = await database
        .customSelect(
          'SELECT COUNT(*) AS count FROM book_cards WHERE book_id = ?',
          variables: [Variable<int>(bookId)],
          readsFrom: {database.sqliteBookCards},
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<List<BookCard>> _loadCardsForBook(int bookId) async {
    final rows =
        await (database.select(database.sqliteBookCards)
              ..where((table) => table.bookId.equals(bookId))
              ..orderBy([(table) => OrderingTerm.asc(table.cardIndex)]))
            .get();
    return rows.map(_bookCardFromRow).toList(growable: false);
  }

  Future<Book> _bestDuplicateMatch(List<Book> matches) async {
    if (matches.length == 1) return matches.single;

    Book? best;
    var bestScore = -1;
    for (final book in matches) {
      final stats = await loadBookStats([book.id]);
      final item = stats[book.id] ?? BookCardStats.empty;
      final score = item.favoriteCount * 1000000 + item.readCount;
      if (score > bestScore) {
        best = book;
        bestScore = score;
      }
    }

    return best ?? matches.first;
  }

  Future<void> _fillMissingIdentity({
    required int bookId,
    required String contentFingerprint,
    String? fileHash,
    required String? sourceFileName,
    required int cardCount,
    required int textCharCount,
  }) async {
    final rows = await loadBooksByIds([bookId]);
    if (rows.isEmpty) return;
    final book = rows.single;
    final needsUpdate =
        book.contentFingerprint == null ||
        (fileHash != null && book.fileHash == null) ||
        (sourceFileName != null && book.sourceFileName == null) ||
        book.cardCount == null ||
        book.textCharCount == null ||
        book.importedAt == null;
    if (!needsUpdate) return;

    await (database.update(
      database.sqliteBooks,
    )..where((table) => table.id.equals(bookId))).write(
      SqliteBooksCompanion(
        contentFingerprint: book.contentFingerprint == null
            ? Value(contentFingerprint)
            : const Value.absent(),
        fileHash: fileHash != null && book.fileHash == null
            ? Value(fileHash)
            : const Value.absent(),
        sourceFileName: sourceFileName != null && book.sourceFileName == null
            ? Value(sourceFileName)
            : const Value.absent(),
        importedAtMs: book.importedAt == null
            ? Value(_msFromDate(book.createdAt))
            : const Value.absent(),
        cardCount: book.cardCount == null
            ? Value(cardCount)
            : const Value.absent(),
        textCharCount: book.textCharCount == null
            ? Value(textCharCount)
            : const Value.absent(),
      ),
    );
  }

  @override
  Future<Map<int, String>> loadRemarks() async {
    final rows = await (database.select(
      database.sqliteBookRemarks,
    )..orderBy([(table) => OrderingTerm.asc(table.bookId)])).get();
    return {
      for (final row in rows)
        if (row.title.trim().isNotEmpty) row.bookId: row.title.trim(),
    };
  }

  @override
  Future<void> saveRemark(int bookId, String remark) async {
    final trimmed = remark.trim();
    await database.transaction(() async {
      if (trimmed.isEmpty) {
        await (database.delete(
          database.sqliteBookRemarks,
        )..where((table) => table.bookId.equals(bookId))).go();
        return;
      }

      await database
          .into(database.sqliteBookRemarks)
          .insertOnConflictUpdate(
            SqliteBookRemarksCompanion.insert(
              bookId: Value(bookId),
              title: trimmed,
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
    _changeTracker.markChanged();
  }

  @override
  Future<void> removeRemark(int bookId) async {
    final deleted = await (database.delete(
      database.sqliteBookRemarks,
    )..where((table) => table.bookId.equals(bookId))).go();
    if (deleted > 0) {
      _changeTracker.markChanged();
    }
  }

  @override
  Future<LibraryBackupSnapshot> buildBackupSnapshot() async {
    final books = await (database.select(
      database.sqliteBooks,
    )..orderBy([(table) => OrderingTerm.asc(table.id)])).get();
    final cards = await (database.select(
      database.sqliteBookCards,
    )..orderBy([(table) => OrderingTerm.asc(table.id)])).get();
    final assets = await (database.select(
      database.sqliteBookAssets,
    )..orderBy([(table) => OrderingTerm.asc(table.id)])).get();
    final remarks = await (database.select(
      database.sqliteBookRemarks,
    )..orderBy([(table) => OrderingTerm.asc(table.bookId)])).get();

    return LibraryBackupSnapshot(
      books: books.map(_bookFromRow).toList(growable: false),
      bookCards: cards.map(_bookCardFromRow).toList(growable: false),
      bookAssets: assets.map(_bookAssetFromRow).toList(growable: false),
      bookRemarks: remarks
          .map(
            (remark) => BookRemarkSnapshot(
              bookId: remark.bookId,
              title: remark.title,
              updatedAt: _dateFromMs(remark.updatedAtMs),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> checkpoint() {
    return database.checkpoint();
  }

  @override
  Future<void> close() {
    return database.close();
  }
}

extension on SqliteBook {
  Book toDomain() {
    return Book()
      ..id = id
      ..title = title
      ..createdAt = _dateFromMs(createdAtMs)
      ..fileHash = fileHash
      ..contentFingerprint = contentFingerprint
      ..sourceFileName = sourceFileName
      ..importedAt = _nullableDateFromMs(importedAtMs)
      ..cardCount = cardCount
      ..textCharCount = textCharCount
      ..assetRootKey = assetRootKey;
  }
}

extension on Book {
  Book toBackfilledIdentity({
    required String contentFingerprint,
    required int cardCount,
    required int textCharCount,
  }) {
    return this
      ..contentFingerprint ??= contentFingerprint
      ..importedAt ??= createdAt
      ..cardCount ??= cardCount
      ..textCharCount ??= textCharCount;
  }
}

extension on SqliteBookCard {
  BookCard toDomain() {
    return BookCard()
      ..id = id
      ..bookId = bookId
      ..bookTitle = bookTitle
      ..cardIndex = cardIndex
      ..chapterIndex = chapterIndex
      ..chapterCardIndex = chapterCardIndex
      ..chapterTitle = chapterTitle
      ..content = content
      ..blocksJson = blocksJson
      ..isRead = isRead
      ..readAt = _nullableDateFromMs(readAtMs)
      ..isFavorite = isFavorite
      ..favoritedAt = _nullableDateFromMs(favoritedAtMs);
  }
}

extension on SqliteBookAsset {
  BookAsset toDomain() {
    return BookAsset()
      ..id = id
      ..bookId = bookId
      ..assetKey = assetKey
      ..originalHref = originalHref
      ..normalizedHref = normalizedHref
      ..mimeType = mimeType
      ..relativePath = relativePath
      ..byteLength = byteLength
      ..createdAt = _dateFromMs(createdAtMs);
  }
}

Book _bookFromRow(SqliteBook row) => row.toDomain();

BookCard _bookCardFromRow(SqliteBookCard row) => row.toDomain();

BookAsset _bookAssetFromRow(SqliteBookAsset row) => row.toDomain();

BookCard _bookCardFromQueryRow(QueryRow row) {
  return BookCard()
    ..id = row.read<int>('id')
    ..bookId = row.read<int>('book_id')
    ..bookTitle = row.read<String>('book_title')
    ..cardIndex = row.read<int>('card_index')
    ..chapterIndex = row.read<int>('chapter_index')
    ..chapterCardIndex = row.read<int>('chapter_card_index')
    ..chapterTitle = row.read<String?>('chapter_title')
    ..content = row.read<String>('content')
    ..blocksJson = row.read<String?>('blocks_json')
    ..isRead = row.read<int>('is_read') == 1
    ..readAt = _nullableDateFromMs(row.read<int?>('read_at_ms'))
    ..isFavorite = row.read<int>('is_favorite') == 1
    ..favoritedAt = _nullableDateFromMs(row.read<int?>('favorited_at_ms'));
}

List<Variable<Object>> _variables(List<Object> values) {
  return values.map((value) => Variable<Object>(value)).toList(growable: false);
}

String _placeholders(int count) => List.filled(count, '?').join(', ');

DateTime _dateFromMs(int milliseconds) {
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

DateTime? _nullableDateFromMs(int? milliseconds) {
  if (milliseconds == null) return null;
  return _dateFromMs(milliseconds);
}

int? _msFromDate(DateTime? value) => value?.millisecondsSinceEpoch;
