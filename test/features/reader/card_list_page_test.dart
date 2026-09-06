import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/card_list_page.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/library_repository.dart';

void main() {
  Book buildBook(int id, String title) => Book()
    ..id = id
    ..title = title
    ..createdAt = DateTime(2026, 1, id);

  BookCard buildCard(
    int id,
    int bookId,
    String bookTitle,
    int cardIndex,
    String content,
    DateTime readAt,
  ) => BookCard()
    ..id = id
    ..bookId = bookId
    ..bookTitle = bookTitle
    ..cardIndex = cardIndex
    ..chapterIndex = 0
    ..chapterCardIndex = cardIndex
    ..content = content
    ..isRead = true
    ..readAt = readAt;

  _FakeRepository buildRepository() {
    return _FakeRepository(
      books: [buildBook(1, 'First'), buildBook(2, 'Second')],
      cards: [
        buildCard(10, 1, 'First', 0, 'AAA', DateTime(2026, 1, 3)),
        buildCard(11, 2, 'Second', 0, 'BBB', DateTime(2026, 1)),
        buildCard(12, 1, 'First', 1, 'CCC', DateTime(2026, 1, 2)),
      ],
    );
  }

  Widget buildPage(_FakeRepository repository) {
    return MaterialApp(
      home: CardListPage(
        kind: CardListKind.read,
        bookIds: const <int>[],
        shelfTitle: '全部书籍',
        repository: repository,
      ),
    );
  }

  testWidgets('顶部筛选条随列表滚动，默认显示全部卡片', (tester) async {
    final repository = buildRepository();
    await tester.pumpWidget(buildPage(repository));
    await tester.pumpAndSettle();

    expect(find.text('按时间'), findsOneWidget);
    expect(find.text('按书'), findsOneWidget);
    expect(find.text('从新到旧'), findsOneWidget);
    expect(find.text('3 张'), findsOneWidget);
    expect(find.text('AAA'), findsOneWidget);
    expect(find.text('BBB'), findsOneWidget);
    expect(find.text('CCC'), findsOneWidget);

    // 默认排序：从新到旧 → AAA(1/3) 在 CCC(1/2) 前，BBB(1/1) 最后。
    final topA = tester.getTopLeft(find.text('AAA')).dy;
    final topB = tester.getTopLeft(find.text('BBB')).dy;
    final topC = tester.getTopLeft(find.text('CCC')).dy;
    expect(topA < topC && topC < topB, isTrue);
  });

  testWidgets('排序切换为从旧到新后列表顺序反转', (tester) async {
    final repository = buildRepository();
    await tester.pumpWidget(buildPage(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('从新到旧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从旧到新'));
    await tester.pumpAndSettle();

    expect(repository.lastSort, CardListSort.activityAsc);
    final topA = tester.getTopLeft(find.text('AAA')).dy;
    final topB = tester.getTopLeft(find.text('BBB')).dy;
    final topC = tester.getTopLeft(find.text('CCC')).dy;
    expect(topB < topC && topC < topA, isTrue);
  });

  testWidgets('按时间筛选「今天」过滤掉历史卡片', (tester) async {
    final repository = buildRepository();
    await tester.pumpWidget(buildPage(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('按时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();

    expect(find.text('没有符合筛选条件的卡片'), findsOneWidget);
    expect(find.text('AAA'), findsNothing);
    expect(repository.lastFrom, isNotNull);
  });

  testWidgets('按书筛选可勾选显示哪些书的卡片', (tester) async {
    final repository = buildRepository();
    await tester.pumpWidget(buildPage(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('按书'));
    await tester.pumpAndSettle();

    // 对话框内取消勾选 First（两张卡片），只留 Second。
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('1 本书'), findsOneWidget);
    expect(find.text('1 张'), findsOneWidget);
    expect(find.text('BBB'), findsOneWidget);
    expect(find.text('AAA'), findsNothing);
    expect(repository.lastBookIds, [2]);
  });
}

class _FakeRepository implements LibraryRepository {
  _FakeRepository({required this.books, required this.cards});

  final List<Book> books;
  final List<BookCard> cards;

  List<int>? lastBookIds;
  DateTime? lastFrom;
  DateTime? lastTo;
  CardListSort? lastSort;

  @override
  Future<List<Book>> loadBooks() async => books;

  @override
  Future<List<Book>> loadBooksByIds(List<int> ids) async =>
      books.where((book) => ids.contains(book.id)).toList();

  @override
  Future<Map<int, String>> loadRemarks() async => const {};

  @override
  Future<List<BookCard>> loadCardsByIds(List<int> ids) async =>
      cards.where((card) => ids.contains(card.id)).toList();

  @override
  Future<List<BookCard>> loadReadCards(
    List<int> bookIds, {
    int offset = 0,
    int? limit,
    DateTime? from,
    DateTime? to,
    CardListSort sort = CardListSort.activityDesc,
  }) {
    return _query(
      bookIds,
      stateOf: (card) => card.isRead,
      timestampOf: (card) => card.readAt,
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
    return _query(
      bookIds,
      stateOf: (card) => card.isFavorite,
      timestampOf: (card) => card.favoritedAt,
      offset: offset,
      limit: limit,
      from: from,
      to: to,
      sort: sort,
    );
  }

  Future<List<BookCard>> _query(
    List<int> bookIds, {
    required bool Function(BookCard card) stateOf,
    required DateTime? Function(BookCard card) timestampOf,
    int offset = 0,
    int? limit,
    DateTime? from,
    DateTime? to,
    CardListSort sort = CardListSort.activityDesc,
    bool record = true,
  }) async {
    if (record) {
      lastBookIds = bookIds;
      lastFrom = from;
      lastTo = to;
      lastSort = sort;
    }
    var result = cards
        .where(stateOf)
        .where((card) => bookIds.isEmpty || bookIds.contains(card.bookId))
        .toList();
    if (from != null) {
      result = result.where((card) {
        final timestamp = timestampOf(card);
        return timestamp != null && !timestamp.isBefore(from);
      }).toList();
    }
    if (to != null) {
      result = result.where((card) {
        final timestamp = timestampOf(card);
        return timestamp != null && timestamp.isBefore(to);
      }).toList();
    }
    result.sort((a, b) {
      switch (sort) {
        case CardListSort.activityDesc:
          return _byActivity(timestampOf, b, a);
        case CardListSort.activityAsc:
          return _byActivity(timestampOf, a, b);
        case CardListSort.cardOrder:
          final bookCompare = a.bookId.compareTo(b.bookId);
          return bookCompare != 0
              ? bookCompare
              : a.cardIndex.compareTo(b.cardIndex);
      }
    });
    if (offset > 0) result = result.skip(offset).toList();
    if (limit != null) result = result.take(limit).toList();
    return result;
  }

  static int _byActivity(
    DateTime? Function(BookCard card) timestampOf,
    BookCard a,
    BookCard b,
  ) {
    final timeCompare = (timestampOf(a)?.millisecondsSinceEpoch ?? 0).compareTo(
      timestampOf(b)?.millisecondsSinceEpoch ?? 0,
    );
    return timeCompare != 0 ? timeCompare : a.id.compareTo(b.id);
  }

  @override
  Future<int> countReadCards(
    List<int> bookIds, {
    DateTime? from,
    DateTime? to,
  }) async => (await _query(
    bookIds,
    stateOf: (card) => card.isRead,
    timestampOf: (card) => card.readAt,
    from: from,
    to: to,
    record: false,
  )).length;

  @override
  Future<int> countFavoriteCards(
    List<int> bookIds, {
    DateTime? from,
    DateTime? to,
  }) async => (await _query(
    bookIds,
    stateOf: (card) => card.isFavorite,
    timestampOf: (card) => card.favoritedAt,
    from: from,
    to: to,
    record: false,
  )).length;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
