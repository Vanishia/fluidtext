import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/search/search_page.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/library_repository.dart';

void main() {
  testWidgets('搜索结果默认折叠为 3 行摘要，点击展开为整卡', (tester) async {
    final repository = _FakeSearchRepository();

    await tester.pumpWidget(
      MaterialApp(home: SearchPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('输入关键词搜索全部书籍正文'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' Flutter ');
    // 300ms 防抖后触发搜索。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.queries, ['Flutter']);
    // 折叠态：显示书名与摘要，不显示整卡内容。
    expect(find.text('搜索样例'), findsOneWidget);
    expect(find.byType(RichText), findsWidgets);
    expect(find.textContaining('完整正文第一行'), findsNothing);

    // 点击展开为整张阅读卡片（BookCardTile 展示全量内容与已读/收藏按钮）。
    await tester.tap(find.text('搜索样例'));
    await tester.pumpAndSettle();
    expect(find.textContaining('完整正文第一行'), findsOneWidget);
    expect(find.byTooltip('标记已读'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
  });

  testWidgets('空结果显示提示文案', (tester) async {
    final repository = _FakeSearchRepository()..results = const [];

    await tester.pumpWidget(
      MaterialApp(home: SearchPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('没有找到包含“不存在”的卡片'), findsOneWidget);
  });
}

class _FakeSearchRepository implements LibraryRepository {
  final queries = <String>[];

  List<CardSearchResult> results = [
    CardSearchResult(
      card: BookCard()
        ..id = 1
        ..bookId = 1
        ..bookTitle = '搜索样例'
        ..cardIndex = 0
        ..chapterIndex = 0
        ..chapterCardIndex = 0
        ..chapterTitle = '第一章'
        ..content = '完整正文第一行。Flutter 出现在这里。完整正文其余部分。'
        ..isRead = false
        ..isFavorite = false,
      snippet: '摘要：<mark>Flutter</mark> 出现在这里。',
    ),
  ];

  @override
  Future<List<CardSearchResult>> searchCards(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    queries.add(query);
    return offset == 0 ? results : const [];
  }

  @override
  Future<bool> isSearchIndexReady() async => true;

  @override
  Future<void> ensureSearchIndexBuilt() async {}

  @override
  Future<void> toggleRead(BookCard card) async {}

  @override
  Future<void> toggleFavorite(BookCard card) async {}

  @override
  Future<List<BookCard>> loadCardsByIds(List<int> ids) async =>
      [results.first.card];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
