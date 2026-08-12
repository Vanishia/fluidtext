import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../../models/book.dart';
import '../../models/book_asset.dart';
import '../../models/book_card.dart';
import '../../models/book_card_activity_event.dart';
import '../../repositories/library_change_tracker.dart';
import '../../repositories/library_repository.dart';
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
  Future<List<BookCard>> loadReadCards(List<int> bookIds) {
    return _loadCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_read',
      timestampColumn: 'read_at_ms',
    );
  }

  @override
  Future<List<BookCard>> loadFavoriteCards(List<int> bookIds) {
    return _loadCardsWithState(
      bookIds: bookIds,
      stateColumn: 'is_favorite',
      timestampColumn: 'favorited_at_ms',
    );
  }

  Future<List<BookCard>> _loadCardsWithState({
    required List<int> bookIds,
    required String stateColumn,
    required String timestampColumn,
  }) async {
    final query = StringBuffer(
      'SELECT * FROM book_cards WHERE $stateColumn = 1',
    );
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
    return rows.map(_bookCardFromQueryRow).toList(growable: false);
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
