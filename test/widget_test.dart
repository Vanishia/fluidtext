import 'package:fluidtext/features/reader/reading_order.dart';
import 'package:fluidtext/features/settings/app_drawer.dart';
import 'package:fluidtext/widgets/side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App side panel shows reading controls and bottom actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: kSidePanelWidth,
              child: AppSidePanel(
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
            ),
          ),
        ),
      ),
    );

    expect(find.text('书架'), findsOneWidget);
    expect(find.text('顺序阅读'), findsOneWidget);
    expect(find.text('乱序阅读'), findsOneWidget);
    expect(find.text('过滤已读'), findsOneWidget);
    expect(find.byTooltip('外观设置'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('已读'), findsOneWidget);
  });
}
