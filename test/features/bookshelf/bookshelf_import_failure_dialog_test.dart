import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/bookshelf/bookshelf_sheet.dart';

void main() {
  Future<void> pumpDialogTrigger(
    WidgetTester tester, {
    required Object error,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImportFailureDialog(
                context,
                error: error,
                stackTrace: StackTrace.fromString('fake-trace'),
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('导入失败对话框展示友好文案，不暴露原始异常', (tester) async {
    await pumpDialogTrigger(tester, error: StateError('zip broken'));

    expect(find.text('导入失败'), findsOneWidget);
    expect(find.textContaining('有效的 EPUB'), findsOneWidget);
    expect(find.text('复制详情'), findsOneWidget);
    expect(find.textContaining('zip broken'), findsNothing);

    await tester.tap(find.text('好'));
    await tester.pump();
    await tester.pump();
    expect(find.text('导入失败'), findsNothing);
  });

  testWidgets('复制详情把原始异常与堆栈写入剪贴板', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpDialogTrigger(tester, error: StateError('zip broken'));
    await tester.tap(find.text('复制详情'));
    await tester.pump();
    await tester.pump();

    expect(clipboardText, contains('zip broken'));
    expect(clipboardText, contains('fake-trace'));
    expect(find.text('导入失败'), findsNothing);
  });
}
