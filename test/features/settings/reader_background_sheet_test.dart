import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/features/settings/app_font_settings.dart';
import 'package:fluidtext/features/settings/reader_background_sheet.dart';

void main() {
  testWidgets('appearance settings exposes the two requested font options', (
    tester,
  ) async {
    var usedSystemFont = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showReaderBackgroundSheet(
                  context,
                  initialSettings: const ReaderBackgroundSettings(),
                  onChanged: (_) async {},
                  onImportImage: (_) async => null,
                  onClearImage: (settings) async => settings,
                  initialFontSettings: const AppFontSettings.system(),
                  onImportFont: () async => null,
                  onUseSystemFont: () async {
                    usedSystemFont = true;
                    return const AppFontSettings.system();
                  },
                ),
                child: const Text('打开外观设置'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开外观设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观设置'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('字体设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('字体设置'));
    await tester.pumpAndSettle();

    expect(find.text('使用系统字体'), findsWidgets);
    expect(find.text('导入字体'), findsOneWidget);

    await tester.tap(find.text('使用系统字体').last);
    await tester.pumpAndSettle();
    expect(usedSystemFont, isTrue);
  });
}
