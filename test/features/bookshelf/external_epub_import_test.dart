import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/bookshelf/bookshelf_sheet.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/repositories/library_data_access.dart';
import 'package:fluidtext/repositories/library_repository.dart';
import 'package:fluidtext/services/book_import_service.dart';
import 'package:fluidtext/services/external_epub_service.dart';

void main() {
  late _ExternalFiles files;
  late _Library repository;

  setUp(() {
    files = _ExternalFiles();
    repository = _Library();
  });

  Future<void> pumpShelf(
    WidgetTester tester, {
    required EpubImporter importer,
    Future<String?> Function()? backupFilePicker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfSheet(
          externalEpubService: files,
          dataAccessLoader: () async =>
              LibraryDataAccess.forTesting(repository),
          migrationEntryChecker: () async => false,
          backupFilePicker: backupFilePicker,
          epubImporter: importer,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  EpubImporter importerReturning(BookImportResult result) =>
      ({
        required bytes,
        sourceFileName,
        targetCharsPerCard = 300,
        onProgress,
      }) async => result;

  BookImportResult result() => BookImportResult(
    bookId: 1,
    bookTitle: '外部书籍',
    insertedCards: 8,
    wasDuplicate: false,
  );

  for (final length in [300, 750]) {
    testWidgets('外部 EPUB 直接弹出字数框，选择 $length 后进入导入', (tester) async {
      final file = _EpubFile('中文书.epub');
      files.open(file);
      int? chosenLength;
      String? chosenName;
      Uint8List? importedBytes;
      await pumpShelf(
        tester,
        importer:
            ({
              required bytes,
              sourceFileName,
              targetCharsPerCard = 300,
              onProgress,
            }) async {
              importedBytes = bytes;
              chosenName = sourceFileName;
              chosenLength = targetCharsPerCard;
              repository.books.add(
                Book()
                  ..id = 1
                  ..title = '外部书籍',
              );
              return result();
            },
      );

      expect(find.text('选择切分长度'), findsOneWidget);
      expect(file.readCount, 0);
      await tester.tap(find.text('$length字符'));
      await tester.pumpAndSettle();

      expect(chosenLength, length);
      expect(chosenName, '中文书.epub');
      expect(importedBytes, orderedEquals([80, 75, 3, 4]));
      expect(find.text('已导入《外部书籍》 · 8 张卡片'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(files.released, [file]);
    });
  }

  testWidgets('取消字数选择不读取文件、不导入，并清理副本', (tester) async {
    final file = _EpubFile('cancel.epub');
    files.open(file);
    var imported = false;
    await pumpShelf(
      tester,
      importer:
          ({
            required bytes,
            sourceFileName,
            targetCharsPerCard = 300,
            onProgress,
          }) async {
            imported = true;
            return result();
          },
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('选择切分长度'), findsNothing);
    expect(file.readCount, 0);
    expect(imported, isFalse);
    expect(files.released, [file]);
  });

  testWidgets('已有书架收到文件后直接显示字数框', (tester) async {
    await pumpShelf(tester, importer: importerReturning(result()));
    expect(find.text('选择切分长度'), findsNothing);

    files.open(_EpubFile('warm.epub'));
    await tester.pumpAndSettle();
    expect(find.text('选择切分长度'), findsOneWidget);
    expect(find.byType(BookshelfSheet), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });

  testWidgets('连续打开的 EPUB 排队，当前导入完成后才选择下一本的字数', (tester) async {
    final first = _EpubFile('first.epub');
    final second = _EpubFile('second.epub');
    final completion = Completer<BookImportResult>();
    files.open(first);
    await pumpShelf(
      tester,
      importer:
          ({
            required bytes,
            sourceFileName,
            targetCharsPerCard = 300,
            onProgress,
          }) => completion.future,
    );
    await tester.tap(find.text('300字符'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    files.open(second);
    await tester.pump();

    expect(find.text('选择切分长度'), findsNothing);
    expect(second.readCount, 0);
    completion.complete(result());
    await tester.pumpAndSettle();
    expect(files.released, [first]);
    expect(find.text('选择切分长度'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(files.released, [first, second]);
  });

  testWidgets('读取失败显示导入错误并释放副本', (tester) async {
    final file = _EpubFile('broken.epub', fail: true);
    files.open(file);
    await pumpShelf(tester, importer: importerReturning(result()));
    await tester.tap(find.text('750字符'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('导入失败'), findsOneWidget);
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(files.released, [file]);
  });

  testWidgets('备份确认期间收到 EPUB，取消确认后再弹字数框', (tester) async {
    repository.books.add(
      Book()
        ..id = 1
        ..title = '已有书籍',
    );
    await pumpShelf(
      tester,
      importer: importerReturning(result()),
      backupFilePicker: () async => '/test/backup.zip',
    );
    await tester.tap(find.byTooltip('导入备份'));
    await tester.pumpAndSettle();
    files.open(_EpubFile('queued.epub'));
    await tester.pumpAndSettle();
    expect(find.text('选择切分长度'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('选择切分长度'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });
}

class _ExternalFiles extends ExternalEpubService {
  _ExternalFiles() : super(supported: false);

  final _files = <ExternalEpubFile>[];
  final released = <ExternalEpubFile>[];

  void open(ExternalEpubFile file) {
    _files.add(file);
    notifyListeners();
  }

  @override
  bool get hasPendingFiles => _files.isNotEmpty;

  @override
  ExternalEpubFile takeNext() => _files.removeAt(0);

  @override
  Future<void> release(ExternalEpubFile file) async => released.add(file);
}

class _EpubFile extends ExternalEpubFile {
  _EpubFile(String name, {this.fail = false}) : super(name: name);

  final bool fail;
  var readCount = 0;

  @override
  Future<Uint8List> readBytes() async {
    readCount++;
    if (fail) throw const BookImportException('无法读取外部 EPUB 文件');
    return Uint8List.fromList([80, 75, 3, 4]);
  }
}

class _Library implements LibraryRepository {
  final books = <Book>[];

  @override
  Future<List<Book>> loadBooks() async => List.of(books);

  @override
  Future<Map<int, String>> loadRemarks() async => {};

  @override
  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds) async => {};

  @override
  Future<void> logDatabaseSnapshot(String reason) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
