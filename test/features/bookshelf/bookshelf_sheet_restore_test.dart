import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/bookshelf/bookshelf_sheet.dart';
import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/models/book_card_activity_event.dart';
import 'package:fluidtext/repositories/library_data_access.dart';
import 'package:fluidtext/repositories/library_repository.dart';
import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/services/backup/backup_restore_service.dart';

void main() {
  // NOTE: testWidgets runs in a fake-async zone where real dart:io futures
  // never complete, so every IO-touching piece of the sheet is injected.

  LibraryDataAccess accessWith(List<Book> books) {
    return LibraryDataAccess.forTesting(_FakeLibraryRepository(books));
  }

  Finder restoreButton() {
    return find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '导入备份',
    );
  }

  BackupRestoreResult restoreResult({int formatVersion = 3}) {
    return BackupRestoreResult(
      formatVersion: formatVersion,
      bookCount: 2,
      cardCount: 5,
      assetCount: 1,
      remarkCount: 0,
      settingsIncluded: formatVersion != 2,
      warnings: const [],
    );
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required LibraryDataAccess dataAccess,
    Future<String?> Function()? backupFilePicker,
    Future<String> Function()? preRestoreBackup,
    Future<BackupRestoreResult> Function(File)? backupRestoreRunner,
    Future<void> Function()? settingsReloader,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfSheet(
          dataAccessLoader: () async => dataAccess,
          migrationEntryChecker: () async => false,
          backupFilePicker: backupFilePicker,
          preRestoreBackup: preRestoreBackup,
          backupRestoreRunner: backupRestoreRunner,
          settingsReloader: settingsReloader,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('书库非空时点击导入备份出现替换确认对话框，取消则不恢复', (tester) async {
    var restoreCalled = false;
    await pumpSheet(
      tester,
      dataAccess: accessWith([_book(1, '测试书')]),
      backupFilePicker: () async => '/tmp/backup.zip',
      preRestoreBackup: () async => '/tmp/pre-restore.zip',
      backupRestoreRunner: (_) async {
        restoreCalled = true;
        return restoreResult();
      },
    );

    expect(restoreButton(), findsOneWidget);
    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();

    expect(find.text('恢复备份将替换当前书库（1 本书），是否继续？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump();
    expect(restoreCalled, isFalse);
  });

  testWidgets('恢复期间按钮禁用，成功后显示摘要文案并重载设置', (tester) async {
    final gate = Completer<BackupRestoreResult>();
    var insuranceCalled = false;
    var settingsReloaded = false;
    await pumpSheet(
      tester,
      dataAccess: accessWith([_book(1, '测试书')]),
      backupFilePicker: () async => '/tmp/backup.zip',
      preRestoreBackup: () async {
        insuranceCalled = true;
        return '/tmp/pre-restore.zip';
      },
      backupRestoreRunner: (_) => gate.future,
      settingsReloader: () async {
        settingsReloaded = true;
      },
    );

    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('继续恢复'));
    await tester.pump();
    await tester.pump();

    expect(insuranceCalled, isTrue);
    expect(tester.widget<IconButton>(restoreButton()).onPressed, isNull);

    gate.complete(restoreResult());
    await tester.pump();
    await tester.pump();
    expect(find.text('已恢复备份（v3）：书籍 2 本 · 卡片 5 张 · 警告 0 条'), findsOneWidget);
    expect(tester.widget<IconButton>(restoreButton()).onPressed, isNotNull);
    expect(settingsReloaded, isTrue);
  });

  testWidgets('空书库不弹确认直接恢复，v2 备份追加外观设置提示', (tester) async {
    var restoreCalled = false;
    var insuranceCalled = false;
    await pumpSheet(
      tester,
      dataAccess: accessWith(const []),
      backupFilePicker: () async => '/tmp/backup.json',
      preRestoreBackup: () async {
        insuranceCalled = true;
        return '/tmp/pre-restore.zip';
      },
      backupRestoreRunner: (_) async {
        restoreCalled = true;
        return restoreResult(formatVersion: 2);
      },
      settingsReloader: () async {},
    );

    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('恢复备份将替换当前书库'), findsNothing);
    expect(restoreCalled, isTrue);
    expect(insuranceCalled, isFalse);
    expect(
      find.textContaining('核心书库已恢复，外观设置未包含在旧版备份中'),
      findsOneWidget,
    );
  });

  testWidgets('恢复失败显示错误状态文案', (tester) async {
    await pumpSheet(
      tester,
      dataAccess: accessWith([_book(1, '测试书')]),
      backupFilePicker: () async => '/tmp/broken.zip',
      preRestoreBackup: () async => '/tmp/pre-restore.zip',
      backupRestoreRunner: (_) async =>
          throw const FormatException('ZIP 文件损坏或已被截断'),
    );

    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('继续恢复'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('恢复失败'), findsOneWidget);
    expect(find.textContaining('当前书库未受影响'), findsOneWidget);
    expect(find.textContaining('ZIP 文件损坏或已被截断'), findsOneWidget);
  });

  testWidgets('保险备份失败时需要用户确认后才继续恢复', (tester) async {
    var restoreCalled = false;
    await pumpSheet(
      tester,
      dataAccess: accessWith([_book(1, '测试书')]),
      backupFilePicker: () async => '/tmp/backup.zip',
      preRestoreBackup: () async => throw StateError('磁盘已满'),
      backupRestoreRunner: (_) async {
        restoreCalled = true;
        return restoreResult();
      },
      settingsReloader: () async {},
    );

    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('继续恢复'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('恢复前备份当前书库失败'), findsOneWidget);
    expect(restoreCalled, isFalse);

    await tester.tap(find.text('仍要继续恢复'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(restoreCalled, isTrue);
    expect(find.textContaining('已恢复备份（v3）'), findsOneWidget);
  });

  testWidgets('未选择文件时显示提示且不恢复', (tester) async {
    var restoreCalled = false;
    await pumpSheet(
      tester,
      dataAccess: accessWith([_book(1, '测试书')]),
      backupFilePicker: () async => null,
      preRestoreBackup: () async => '/tmp/pre-restore.zip',
      backupRestoreRunner: (_) async {
        restoreCalled = true;
        return restoreResult();
      },
    );

    await tester.tap(restoreButton());
    await tester.pump();
    await tester.pump();

    expect(find.text('未选择文件'), findsOneWidget);
    expect(restoreCalled, isFalse);
  });
}

Book _book(int id, String title) {
  return Book()
    ..id = id
    ..title = title
    ..createdAt = DateTime.utc(2026);
}

class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository(this._books);

  final List<Book> _books;

  @override
  Future<List<Book>> loadBooks() async => List.of(_books);

  @override
  Future<Map<int, String>> loadRemarks() async => const {};

  @override
  Future<Map<int, BookCardStats>> loadBookStats(List<int> bookIds) async {
    return {for (final id in bookIds) id: BookCardStats.empty};
  }

  @override
  Future<void> logDatabaseSnapshot(String reason) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> checkpoint() async {}

  @override
  Future<LibraryBackupSnapshot> buildBackupSnapshot() {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteBook(int bookId) => throw UnimplementedError();

  @override
  Future<List<Book>> pruneIncompleteBooks() async => const <Book>[];

  @override
  Future<LibraryImportResult> importBookDraft(ImportBookDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<List<BookAsset>> loadBookAssets({
    required int bookId,
    required List<String> assetKeys,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Book>> loadBooksByIds(List<int> ids) =>
      throw UnimplementedError();

  @override
  Future<List<BookCard>> loadCardsByIds(List<int> ids) =>
      throw UnimplementedError();

  @override
  Future<List<BookCard>> loadContextCards({
    required int bookId,
    required int centerCardIndex,
    required int before,
    required int after,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<BookCardActivityEvent>> loadFavoriteActivityEvents(
    List<int> bookIds,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<BookCard>> loadFavoriteCards(List<int> bookIds) =>
      throw UnimplementedError();

  @override
  Future<List<int>> loadOrderedCardIds(List<int> bookIds) =>
      throw UnimplementedError();

  @override
  Future<List<BookCardActivityEvent>> loadReadActivityEvents(
    List<int> bookIds,
  ) =>
      throw UnimplementedError();

  @override
  Future<List<BookCard>> loadReadCards(List<int> bookIds) =>
      throw UnimplementedError();

  @override
  Future<List<int>> loadUnreadOrderedCardIds(List<int> bookIds) =>
      throw UnimplementedError();

  @override
  Future<List<BookCard>> loadUnreadCardsByIds(List<int> ids) =>
      throw UnimplementedError();

  @override
  Future<void> removeRemark(int bookId) => throw UnimplementedError();

  @override
  Future<void> saveRemark(int bookId, String remark) =>
      throw UnimplementedError();

  @override
  Future<void> toggleFavorite(BookCard card) => throw UnimplementedError();

  @override
  Future<void> toggleRead(BookCard card) => throw UnimplementedError();
}
