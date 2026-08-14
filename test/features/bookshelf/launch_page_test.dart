import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/bookshelf/launch_page.dart';

void main() {
  testWidgets('启动时存在半截导入书籍则弹窗提示重新导入', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LaunchPage(
          resumeLastSession: false,
          initialState: LaunchState(prunedBookTitles: ['测试书甲', '测试书乙']),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('已清理未完成导入的书籍'), findsOneWidget);
    expect(find.textContaining('《测试书甲》'), findsOneWidget);
    expect(find.textContaining('《测试书乙》'), findsOneWidget);

    await tester.tap(find.text('好'));
    await tester.pump();
    await tester.pump();
    expect(find.text('已清理未完成导入的书籍'), findsNothing);
  });

  testWidgets('没有半截导入书籍时不弹窗', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LaunchPage(resumeLastSession: false),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('已清理未完成导入的书籍'), findsNothing);
  });
}
