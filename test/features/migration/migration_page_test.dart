import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/migration/migration_page.dart';
import 'package:fluidtext/migration/app_bootstrap_coordinator.dart';
import 'package:fluidtext/migration/legacy_backup_exporter.dart';
import 'package:fluidtext/migration/legacy_source.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_promotion.dart';
import 'package:fluidtext/migration/migration_runner.dart';
import 'package:fluidtext/repositories/library_data_access.dart';
import 'package:fluidtext/storage/storage_layout.dart';

void main() {
  // NOTE: testWidgets runs in a fake-async zone where real dart:io futures
  // never complete. All directory setup happens in setUp (real zone) and
  // every IO-touching page action is injected with a fake.
  late Directory tempRoot;
  late StorageLayout legacyLayout;
  late StorageLayout targetLayout;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('fluidtext-page-test-');
    legacyLayout = StorageLayout.legacy(
      documentsDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}documents',
      )..createSync(recursive: true),
      supportDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}support',
      )..createSync(recursive: true),
    );
    targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  AppBootstrapDecision buildDecision(AppBootstrapAction action) {
    return AppBootstrapDecision(
      action: action,
      targetLayout: targetLayout,
      legacyLayout: legacyLayout,
      detection: const LegacySourceDetection(
        status: LegacySourceStatus.trusted,
        sourceFingerprint: 'widget-fingerprint',
      ),
      reason: action == AppBootstrapAction.recoveryRequired
          ? '上次迁移未完成，可以重试；旧数据仍保留在原位置'
          : null,
    );
  }

  MigrationRunResult fakeRunResult() {
    return MigrationRunResult(
      marker: MigrationCompletionMarker(
        source: MigrationCompletionMarker.sourceMigration,
        sourceFingerprint: 'widget-fingerprint',
        sqliteSchemaVersion: 1,
        bookCount: 2,
        cardCount: 3,
        assetCount: 1,
        remarkCount: 2,
        verifiedResourceCount: 3,
        completedAt: DateTime.now().toUtc(),
      ),
      bookCount: 2,
      cardCount: 3,
      assetCount: 1,
      remarkCount: 2,
      warnings: const [],
    );
  }

  Finder filledButton(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
  }

  testWidgets('migration page shows for migrationRequired without opening '
      'the library', (tester) async {
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.migrationRequired),
        onEnterApp: () async {},
      ),
    );
    await tester.pump();

    expect(find.text('发现旧版本数据'), findsOneWidget);
    expect(find.text('导出 ZIP 备份'), findsOneWidget);
    expect(find.text('开始迁移'), findsOneWidget);
    expect(find.text('跳过备份并继续'), findsOneWidget);
    // The normal repository must not be initialized before migration.
    expect(LibraryDataAccess.isInitialized, isFalse);

    // 开始迁移 is disabled until the backup is done.
    expect(
      tester.widget<FilledButton>(filledButton('开始迁移')).onPressed,
      isNull,
    );
  });

  testWidgets('export cancel keeps detected state', (tester) async {
    final decision = buildDecision(AppBootstrapAction.migrationRequired);
    final exporter = _FakeExporter(decision: decision, result: null);
    await tester.pumpWidget(
      MigrationRootApp(
        decision: decision,
        onEnterApp: () async {},
        exporterFactory: (_) => exporter,
      ),
    );

    await tester.tap(find.text('导出 ZIP 备份'));
    await tester.pump();
    await tester.pump();

    expect(exporter.called, isTrue);
    expect(find.text('已取消导出备份'), findsOneWidget);
    expect(find.text('发现旧版本数据'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(filledButton('开始迁移')).onPressed,
      isNull,
    );
  });

  testWidgets('export failure shows a snackbar and stays on detected',
      (tester) async {
    final decision = buildDecision(AppBootstrapAction.migrationRequired);
    final exporter = _FakeExporter(
      decision: decision,
      error: const LegacyBackupException('无法读取旧数据库副本，旧数据未被修改。'),
    );
    await tester.pumpWidget(
      MigrationRootApp(
        decision: decision,
        onEnterApp: () async {},
        exporterFactory: (_) => exporter,
      ),
    );

    await tester.tap(find.text('导出 ZIP 备份'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('备份导出失败'), findsOneWidget);
    expect(find.text('发现旧版本数据'), findsOneWidget);
  });

  testWidgets('successful backup enables start; migration succeeds and enters '
      'the app', (tester) async {
    final decision = buildDecision(AppBootstrapAction.migrationRequired);
    final exporter = _FakeExporter(decision: decision, result: 'backup.zip');
    var entered = false;
    await tester.pumpWidget(
      MigrationRootApp(
        decision: decision,
        onEnterApp: () async => entered = true,
        exporterFactory: (_) => exporter,
        runTask: ({required decision, onProgress}) async => fakeRunResult(),
      ),
    );

    await tester.tap(find.text('导出 ZIP 备份'));
    await tester.pump();
    await tester.pump();
    expect(find.text('备份已完成，可以开始迁移。'), findsOneWidget);

    await tester.tap(find.text('开始迁移'));
    await tester.pump();
    await tester.pump();

    expect(find.text('迁移完成'), findsOneWidget);
    expect(find.textContaining('书籍 2 本 · 卡片 3 张 · 备注 2 条'), findsOneWidget);
    expect(find.textContaining('警告 0 条'), findsOneWidget);

    await tester.tap(find.text('进入应用'));
    await tester.pump();
    expect(entered, isTrue);
  });

  testWidgets('skip-backup confirmation is required before migration',
      (tester) async {
    var runCalled = false;
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.migrationRequired),
        onEnterApp: () async {},
        runTask: ({required decision, onProgress}) async {
          runCalled = true;
          return fakeRunResult();
        },
      ),
    );

    await tester.tap(find.text('跳过备份并继续'));
    await tester.pump();
    expect(find.text('旧数据仍会保留，但没有额外 ZIP 备份。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(runCalled, isFalse);

    await tester.tap(find.text('跳过备份并继续'));
    await tester.pump();
    await tester.tap(find.text('继续迁移'));
    await tester.pump();
    await tester.pump();
    expect(runCalled, isTrue);
    expect(find.text('迁移完成'), findsOneWidget);
  });

  testWidgets('progress text follows events and back is blocked while running',
      (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.migrationRequired),
        onEnterApp: () async {},
        throttleInterval: Duration.zero,
        runTask: ({required decision, onProgress}) async {
          onProgress?.call(
            const MigrationProgressEvent(
              phase: MigrationPhase.migratingCards,
              completed: 2,
              total: 3,
            ),
          );
          await gate.future;
          return fakeRunResult();
        },
      ),
    );

    await tester.tap(find.text('跳过备份并继续'));
    await tester.pump();
    await tester.tap(find.text('继续迁移'));
    await tester.pump();

    expect(find.text('迁移卡片（2 / 3）'), findsOneWidget);
    final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(popScope.canPop, isFalse);

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('迁移完成'), findsOneWidget);
  });

  testWidgets('failure shows the plan wording, retry and abandon flows',
      (tester) async {
    var entered = false;
    var abandoned = false;
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.migrationRequired),
        onEnterApp: () async => entered = true,
        abandonHandler: (_) async => abandoned = true,
        runTask: ({required decision, onProgress}) async {
          throw const MigrationException(
            phase: MigrationPhase.migratingCards,
            message: '旧书库中存在重复的卡片序号，已停止迁移',
            diagnostic: 'duplicate (bookId=1, cardIndex=0)',
          );
        },
      ),
    );

    await tester.tap(find.text('跳过备份并继续'));
    await tester.pump();
    await tester.tap(find.text('继续迁移'));
    await tester.pump();
    await tester.pump();

    expect(find.text('迁移失败'), findsOneWidget);
    expect(find.textContaining('旧数据仍保留，未被删除。'), findsOneWidget);
    expect(find.textContaining('导入备份'), findsOneWidget);
    expect(find.text('重试迁移'), findsOneWidget);
    expect(find.text('导出 ZIP 备份'), findsOneWidget);
    expect(find.text('放弃迁移并进入空书架'), findsOneWidget);

    // Error details are collapsed by default and expandable.
    expect(find.text('错误详情'), findsOneWidget);
    expect(find.text('复制诊断信息'), findsNothing);
    await tester.ensureVisible(find.text('错误详情'));
    await tester.tap(find.text('错误详情'));
    await tester.pump();
    expect(find.text('复制诊断信息'), findsOneWidget);

    // Abandon with second confirmation.
    await tester.ensureVisible(find.text('放弃迁移并进入空书架'));
    await tester.tap(find.text('放弃迁移并进入空书架'));
    await tester.pump();
    expect(find.textContaining('当前书架为空，旧数据仍在原位置'), findsOneWidget);
    await tester.tap(find.text('放弃迁移').last);
    await tester.pump();
    await tester.pump();

    expect(abandoned, isTrue);
    expect(entered, isTrue);
  });

  testWidgets('recovery decision shows the reason and re-detects',
      (tester) async {
    final redetected = buildDecision(AppBootstrapAction.migrationRequired);
    var cleanedUp = false;
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.recoveryRequired),
        onEnterApp: () async {},
        retryCleanupHandler: (_) async => cleanedUp = true,
        decideAgain: () async => redetected,
        runTask: ({required decision, onProgress}) async => fakeRunResult(),
      ),
    );

    expect(find.text('迁移需要继续'), findsOneWidget);
    expect(find.textContaining('上次迁移未完成'), findsOneWidget);

    await tester.tap(find.text('重新检测并迁移'));
    await tester.pump();
    await tester.pump();

    expect(cleanedUp, isTrue);
    expect(find.text('发现旧版本数据'), findsOneWidget);
  });

  testWidgets('unavailable decision explains and offers an empty shelf',
      (tester) async {
    var entered = false;
    var abandoned = false;
    await tester.pumpWidget(
      MigrationRootApp(
        decision: buildDecision(AppBootstrapAction.migrationUnavailable),
        onEnterApp: () async => entered = true,
        abandonHandler: (_) async => abandoned = true,
      ),
    );

    expect(find.text('无法自动迁移旧数据'), findsOneWidget);
    expect(find.textContaining('无法确认的 default.isar 文件'), findsOneWidget);

    await tester.tap(find.text('进入空书架'));
    await tester.pump();
    await tester.tap(find.text('放弃迁移'));
    await tester.pump();
    await tester.pump();
    expect(abandoned, isTrue);
    expect(entered, isTrue);
  });

  testWidgets('bootstrap page reports when there is nothing to migrate',
      (tester) async {
    final fresh = buildDecision(AppBootstrapAction.freshInstall);
    await tester.pumpWidget(
      MaterialApp(home: MigrationBootstrapPage(decide: () async => fresh)),
    );
    await tester.pump();

    expect(find.text('未检测到需要迁移的旧数据。'), findsOneWidget);
  });
}

class _FakeExporter extends LegacyBackupExporter {
  _FakeExporter({required AppBootstrapDecision decision, this.result, this.error})
    : super(legacyLayout: decision.legacyLayout!);

  final String? result;
  final Object? error;
  var called = false;

  @override
  Future<String?> exportToPickedFile() async {
    called = true;
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}
