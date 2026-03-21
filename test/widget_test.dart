import 'package:flutter_test/flutter_test.dart';

import 'package:fluidtext/main.dart';

void main() {
  testWidgets('App shows drawer import and reading order settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('导入 EPUB'), findsOneWidget);
    expect(find.text('顺序阅读'), findsOneWidget);
    expect(find.text('乱序阅读'), findsOneWidget);
  });
}
