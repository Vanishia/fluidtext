import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/bookshelf/launch_page.dart';
import 'package:fluidtext/services/external_epub_service.dart';

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
      const MaterialApp(home: LaunchPage(resumeLastSession: false)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('已清理未完成导入的书籍'), findsNothing);
  });

  for (final coldStart in [true, false]) {
    testWidgets('${coldStart ? '冷启动' : '已启动'}收到 EPUB 后自动进入书架导入', (
      tester,
    ) async {
      final files = _ExternalFiles();
      if (coldStart) files.open();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LaunchPage(
            resumeLastSession: false,
            externalEpubService: files,
            bookshelfOpener: (_) async {
              opened++;
              files.takeNext();
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (!coldStart) {
        expect(opened, 0);
        files.open();
        await tester.pumpAndSettle();
      }
      expect(opened, 1);
      expect(files.hasPendingFiles, isFalse);
    });
  }

  testWidgets('已有书架处理文件时不重复打开，关闭后接管未处理文件', (tester) async {
    final files = _ExternalFiles()..attachBookshelf();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchPage(
          resumeLastSession: false,
          externalEpubService: files,
          bookshelfOpener: (_) async {
            opened++;
            files.takeNext();
            return null;
          },
        ),
      ),
    );
    files.open();
    await tester.pumpAndSettle();
    expect(opened, 0);

    files.detachBookshelf();
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('未完成导入提示关闭后才处理外部 EPUB', (tester) async {
    final files = _ExternalFiles()..open();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchPage(
          resumeLastSession: false,
          initialState: const LaunchState(prunedBookTitles: ['旧书']),
          externalEpubService: files,
          bookshelfOpener: (_) async {
            opened++;
            files.takeNext();
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('已清理未完成导入的书籍'), findsOneWidget);

    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}

class _ExternalFiles extends ExternalEpubService {
  _ExternalFiles() : super(supported: false);

  final _files = <ExternalEpubFile>[];

  void open() {
    _files.add(const ExternalEpubFile(name: 'book.epub'));
    notifyListeners();
  }

  @override
  bool get hasPendingFiles => _files.isNotEmpty;

  @override
  ExternalEpubFile takeNext() => _files.removeAt(0);
}
