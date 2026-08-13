import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_promotion.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/migration/migration_state.dart';
import 'package:fluidtext/migration/migration_validator.dart';
import 'package:fluidtext/storage/storage_layout.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;
  late LegacyFixtureMigration harness;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-promotion-test-',
    );
    harness = await LegacyFixtureMigration.setUp(tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<MigrationCompletionMarker> migrateValidateSealPromote() async {
    final result = await harness.runMigration();
    final validation = await MigrationValidator().validate(
      result: result,
      legacyLayout: harness.legacyLayout,
    );
    const promotion = MigrationPromotion();
    await promotion.seal(
      staging: result.staging,
      legacyLayout: harness.legacyLayout,
    );
    return promotion.promote(
      staging: result.staging,
      result: result,
      validation: validation,
      legacyLayout: harness.legacyLayout,
      targetLayout: harness.targetLayout,
    );
  }

  test('promote moves the payload into the target root', () async {
    final result = await harness.runMigration();
    final attemptDirectory = result.staging.attemptDirectory;
    final validation = await MigrationValidator().validate(
      result: result,
      legacyLayout: harness.legacyLayout,
    );
    final events = <MigrationProgressEvent>[];
    final promotion = MigrationPromotion(onProgress: events.add);
    await promotion.seal(
      staging: result.staging,
      legacyLayout: harness.legacyLayout,
    );
    final marker = await promotion.promote(
      staging: result.staging,
      result: result,
      validation: validation,
      legacyLayout: harness.legacyLayout,
      targetLayout: harness.targetLayout,
    );

    final root = harness.targetLayout.rootDirectory;
    expect(await harness.targetLayout.sqliteDatabaseFile.exists(), isTrue);
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}settings'
        '${Platform.pathSeparator}${StorageLayout.readerSessionFileName}',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}book_assets'
        '${Platform.pathSeparator}asset_fixture_one'
        '${Platform.pathSeparator}images${Platform.pathSeparator}cover.png',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}app_fonts'
        '${Platform.pathSeparator}legacy.ttf',
      ).exists(),
      isTrue,
    );

    // Completion marker with fingerprint, counts and schema version.
    final markerFile = MigrationCompletion.markerFile(harness.targetLayout);
    expect(await markerFile.exists(), isTrue);
    final decoded =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    expect(decoded['format'], MigrationCompletionMarker.format);
    expect(decoded['sourceFingerprint'], 'test-fingerprint');
    expect(
      decoded['sqliteSchemaVersion'],
      marker.sqliteSchemaVersion,
    );
    expect(
      (decoded['counts'] as Map<String, dynamic>)['bookCards'],
      3,
    );

    // State cleared and attempt removed.
    final state = await MigrationStateStore(
      targetLayout: harness.targetLayout,
    ).load();
    expect(state.status, MigrationLifecycleStatus.idle);
    expect(await attemptDirectory.exists(), isFalse);
    expect(events.last.phase, MigrationPhase.finalizing);
    expect(events.last.fraction, 1.0);
  });

  test('promote refuses to overwrite an existing live database', () async {
    final result = await harness.runMigration();
    final validation = await MigrationValidator().validate(
      result: result,
      legacyLayout: harness.legacyLayout,
    );
    const promotion = MigrationPromotion();
    await promotion.seal(
      staging: result.staging,
      legacyLayout: harness.legacyLayout,
    );

    // Simulate an interrupted earlier promotion: live db file exists but no
    // completion marker.
    await harness.targetLayout.rootDirectory.create(recursive: true);
    await harness.targetLayout.sqliteDatabaseFile.writeAsBytes(const [1]);

    await expectLater(
      promotion.promote(
        staging: result.staging,
        result: result,
        validation: validation,
        legacyLayout: harness.legacyLayout,
        targetLayout: harness.targetLayout,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.finalizing,
        ),
      ),
    );
    // The pre-existing file is untouched.
    expect(await harness.targetLayout.sqliteDatabaseFile.readAsBytes(), [1]);
  });

  test('state store round trip and recovery cleanup', () async {
    final store = MigrationStateStore(targetLayout: harness.targetLayout);

    expect((await store.load()).status, MigrationLifecycleStatus.idle);

    await store.markMigrating('attempt-1');
    var snapshot = await store.load();
    expect(snapshot.status, MigrationLifecycleStatus.migrating);
    expect(snapshot.attemptId, 'attempt-1');

    await store.markFailed('attempt-1', MigrationPhase.migratingCards, '失败原因');
    snapshot = await store.load();
    expect(snapshot.status, MigrationLifecycleStatus.failed);
    expect(snapshot.phase, MigrationPhase.migratingCards);
    expect(snapshot.message, '失败原因');

    await store.markAbandoned();
    expect(
      (await store.load()).status,
      MigrationLifecycleStatus.abandoned,
    );

    await store.markIdle();
    expect(await store.stateFile.exists(), isFalse);
    expect((await store.load()).status, MigrationLifecycleStatus.idle);

    // Recovery cleanup removes attempts and incomplete target content but
    // keeps the migration bookkeeping directory.
    final staging = await MigrationStaging.create(
      targetLayout: harness.targetLayout,
      attemptId: 'stale-attempt',
    );
    expect(await MigrationRecovery.hasAttempts(harness.targetLayout), isTrue);
    await MigrationRecovery.discardAttempt(
      harness.targetLayout,
      staging.attemptId,
    );
    expect(await staging.attemptDirectory.exists(), isFalse);

    final strayDb = harness.targetLayout.sqliteDatabaseFile;
    await strayDb.writeAsBytes(const [1, 2]);
    await MigrationRecovery.discardIncompleteTarget(harness.targetLayout);
    expect(await strayDb.exists(), isFalse);
    expect(
      await harness.targetLayout.migrationDirectory.exists(),
      isTrue,
    );
  });

  test('interrupted promotion without marker is recoverable', () async {
    await migrateValidateSealPromote();

    // Corrupt the marker to simulate an incomplete switch.
    final markerFile = MigrationCompletion.markerFile(harness.targetLayout);
    final decoded =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    (decoded['counts'] as Map<String, dynamic>)['books'] = 99;
    await markerFile.writeAsString(jsonEncode(decoded));

    final loaded = await MigrationCompletion.load(harness.targetLayout);
    expect(loaded, isNotNull);
    expect(
      await MigrationCompletion.verifyLiveDatabase(
        harness.targetLayout,
        loaded!,
      ),
      isFalse,
    );
  });
}
