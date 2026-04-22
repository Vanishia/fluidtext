import 'package:fluidtext/features/reader/reading_order.dart';
import 'package:fluidtext/features/settings/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App drawer shows reading controls and bottom actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(
            onOpenBookshelf: () {},
            readingOrder: ReadingOrder.sequential,
            onReadingOrderChanged: (_) {},
            themeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            showUnreadOnly: true,
            onShowUnreadOnlyChanged: (_) {},
            onOpenFavoriteList: () {},
            onOpenReadList: () {},
            onOpenReaderBackgroundSettings: () {},
          ),
          body: Builder(
            builder: (context) => IconButton(
              tooltip: 'open drawer',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('open drawer'));
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);
    expect(find.text('顺序阅读'), findsOneWidget);
    expect(find.text('乱序阅读'), findsOneWidget);
    expect(find.text('只看未读'), findsOneWidget);
    expect(find.byTooltip('阅读背景'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('已读'), findsOneWidget);
  });
}
