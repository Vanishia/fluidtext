import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/reading_order.dart';
import 'package:fluidtext/features/settings/app_drawer.dart';

void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: AppSidePanel(
              onOpenBookshelf: () {},
              readingOrder: ReadingOrder.sequential,
              onReadingOrderChanged: (_) {},
              themeMode: ThemeMode.system,
              onThemeModeChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('侧边栏标题第一次点击无提示，第二次点击弹出仓库提示', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('FluidText'));
    await tester.pump();
    expect(find.text('再点击一次将打开项目仓库页面'), findsNothing);

    await tester.tap(find.text('FluidText'));
    await tester.pump();
    expect(find.text('再点击一次将打开项目仓库页面'), findsOneWidget);
  });

  testWidgets('第三次点击收起提示且不抛异常', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('FluidText'));
    await tester.pump();
    await tester.tap(find.text('FluidText'));
    await tester.pump();
    expect(find.text('再点击一次将打开项目仓库页面'), findsOneWidget);

    await tester.tap(find.text('FluidText'));
    await tester.pump();
    expect(find.text('再点击一次将打开项目仓库页面'), findsNothing);

    // 计数已重置：再次单击不应出现提示。
    await tester.tap(find.text('FluidText'));
    await tester.pump();
    expect(find.text('再点击一次将打开项目仓库页面'), findsNothing);
  });
}
