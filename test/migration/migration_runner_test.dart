import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/app_bootstrap_coordinator.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_promotion.dart';
import 'package:fluidtext/migration/migration_runner.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/migration/migration_state.dart';
import 'package:fluidtext/storage/storage_layout.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;
  late LegacyFixtureMigration harness;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-runner-test-',
    );
    harness = await LegacyFixtureMigration.setUp(tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  AppBootstrapCoordinator coordinator() {
    return AppBootstrapCoordinator(
      legacyLayoutProvider: () async => harness.legacyLayout,
      targetLayoutProvider: () async => harness.targetLayout,
    );
  }

  test('decide → runner → marker valid → next decide is normalStart',
      () async {
    final decision = await coordinator().decide();
    expect(decision.action, AppBootstrapAction.migrationRequired);

    final events = <MigrationProgressEvent>[];
    final result = await MigrationRunner().run(
      decision: decision,
      onProgress: events.add,
    );

    expect(
      result.marker.sourceFingerprint,
      decision.detection?.sourceFingerprint,
    );
    expect(result.bookCount, 2);
    expect(result.warnings, isEmpty);
    expect(events.map((event) => event.phase).toSet(), containsAll([
      MigrationPhase.copyingDatabase,
      MigrationPhase.validating,
      MigrationPhase.finalizing,
    ]));

    // State cleared and no attempts remain.
    final state = await MigrationStateStore(
      targetLayout: harness.targetLayout,
    ).load();
    expect(state.status, MigrationLifecycleStatus.idle);
    expect(
      await MigrationRecovery.hasAttempts(harness.targetLayout),
      isFalse,
    );

    // Legacy data untouched: same hash, no lock files created in place.
    final legacyMain = File(
      '${harness.legacyLayout.libraryDatabaseDirectory.path}'
      '${Platform.pathSeparator}default.isar',
    );
    expect(
      sha256.convert(await legacyMain.readAsBytes()).toString(),
      sha256
          .convert(
            await File(
              '${legacyFixtureRoot.path}${Platform.pathSeparator}documents'
              '${Platform.pathSeparator}default.isar',
            ).readAsBytes(),
          )
          .toString(),
    );
    await for (final entity in harness
        .legacyLayout
        .libraryDatabaseDirectory
        .list()) {
      expect(entity.path.endsWith('.lock'), isFalse);
    }

    final next = await coordinator().decide();
    expect(next.action, AppBootstrapAction.normalStart);
  });

  test('failed runner marks state failed and keeps legacy data', () async {
    final decision = await coordinator().decide();
    final sessionBefore = await harness.legacyLayout.readerSessionFile
        .readAsString();

    // Removing the main database makes the staging copy fail deterministically.
    await File(
      '${harness.legacyLayout.libraryDatabaseDirectory.path}'
      '${Platform.pathSeparator}default.isar',
    ).delete();

    await expectLater(
      MigrationRunner().run(decision: decision),
      throwsA(isA<MigrationException>()),
    );

    final state = await MigrationStateStore(
      targetLayout: harness.targetLayout,
    ).load();
    expect(state.status, MigrationLifecycleStatus.failed);
    expect(state.attemptId, isNotNull);
    expect(state.message, isNotEmpty);

    // The target root must not contain a half-promoted database.
    expect(
      await harness.targetLayout.sqliteDatabaseFile.exists(),
      isFalse,
    );
    expect(
      await harness.legacyLayout.readerSessionFile.readAsString(),
      sessionBefore,
    );
  });

  test('abandonMigration cleans staging, marks abandoned and starts fresh',
      () async {
    final staging = await MigrationStaging.create(
      targetLayout: harness.targetLayout,
    );
    await MigrationStateStore(targetLayout: harness.targetLayout).markFailed(
      staging.attemptId,
      MigrationPhase.migratingCards,
      '模拟失败',
    );

    await abandonMigration(harness.targetLayout);

    expect(await staging.attemptDirectory.exists(), isFalse);
    expect(
      await MigrationRecovery.hasAttempts(harness.targetLayout),
      isFalse,
    );
    expect(
      await harness.targetLayout.sqliteDatabaseFile.exists(),
      isTrue,
    );
    final marker = await MigrationCompletion.load(harness.targetLayout);
    expect(marker?.source, MigrationCompletionMarker.sourceFreshInstall);

    // abandoned + valid fresh marker + live database → normal start.
    final next = await coordinator().decide();
    expect(next.action, AppBootstrapAction.normalStart);
  });

  test('fresh install loop: initialize → next decide is normalStart',
      () async {
    final documents = Directory(
      '${tempRoot.path}${Platform.pathSeparator}documents',
    )..createSync();
    final support = Directory(
      '${tempRoot.path}${Platform.pathSeparator}support',
    )..createSync();
    final legacyLayout = StorageLayout.legacy(
      documentsDirectory: documents,
      supportDirectory: support,
    );
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
    final coordinator = AppBootstrapCoordinator(
      legacyLayoutProvider: () async => legacyLayout,
      targetLayoutProvider: () async => targetLayout,
    );

    expect(
      (await coordinator.decide()).action,
      AppBootstrapAction.freshInstall,
    );

    await initializeFreshStorage(targetLayout);

    final next = await coordinator.decide();
    expect(next.action, AppBootstrapAction.normalStart);
    expect(next.marker?.source, 'fresh');

    // And it stays normalStart after user data exists (counts are not
    // re-verified against the marker).
    final again = await coordinator.decide();
    expect(again.action, AppBootstrapAction.normalStart);
  });
}
