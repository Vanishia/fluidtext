import 'package:fluidtext/features/context/context_controller.dart';
import 'package:fluidtext/features/context/context_settings.dart';
import 'package:fluidtext/features/context/context_sheet.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ContextRepository implements LibraryRepository {
  final cards = List.generate(
    5,
    (i) => BookCard()
      ..id = i + 1
      ..bookId = 1
      ..bookTitle = '测试书'
      ..cardIndex = i
      ..content = List.filled(8, '这是一段足以把目标卡片推到屏幕之外的前文。').join('\n'),
  );

  @override
  Future<List<BookCard>> loadContextCards({
    required int bookId,
    required int centerCardIndex,
    required int before,
    required int after,
  }) async => cards;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('打开上下文后自动滚动到中心卡片，重新聚焦也能定位', (tester) async {
    final repository = _ContextRepository();
    final controller = ContextController(
      repository: repository,
      bookId: 1,
      initialCard: repository.cards[3],
      initialSettings: const ContextSettings(before: 3, after: 1),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextSheet(controller: controller, bookTitle: '测试书'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前卡片 #3').hitTestable(), findsOneWidget);

    await controller.focusOn(repository.cards[1]);
    await tester.pumpAndSettle();
    expect(find.text('当前卡片 #1').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
