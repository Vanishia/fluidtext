import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/app_bootstrap_coordinator.dart';
import 'package:fluidtext/migration/legacy_source.dart';
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

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-bootstrap-test-',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  AppBootstrapCoordinator coordinatorFor(
    LegacyFixtureMigration harness, {
    LegacySourceProbe Function(StorageLayout)? probeFactory,
  }) {
    return AppBootstrapCoordinator(
      legacyLayoutProvider: () async => harness.legacyLayout,
      targetLayoutProvider: () async => harness.targetLayout,
      probeFactory: probeFactory,
    );
  }

  Future<void> promoteFully(LegacyFixtureMigration harness) async {
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
    await promotion.promote(
      staging: result.staging,
      result: result,
      validation: validation,
      legacyLayout: harness.legacyLayout,
      targetLayout: harness.targetLayout,
    );
  }

  test('no legacy data and no database is a fresh install', () async {
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
      rootDirectory: Directory('${tempRoot.path}${Platform.pathSeparator}t'),
    );
    final coordinator = AppBootstrapCoordinator(
      legacyLayoutProvider: () async => legacyLayout,
      targetLayoutProvider: () async => targetLayout,
    );

    final decision = await coordinator.decide();

    expect(decision.action, AppBootstrapAction.freshInstall);
    expect(decision.detection?.status, LegacySourceStatus.absent);
  });

  test('trusted legacy data requires migration', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.migrationRequired);
    expect(decision.detection?.isTrusted, isTrue);
  });

  test('untrusted default.isar makes migration unavailable', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    // Replace the main database with garbage and remove companion signals.
    await File(
      '${harness.legacyLayout.libraryDatabaseDirectory.path}'
      '${Platform.pathSeparator}default.isar',
    ).writeAsBytes(List<int>.generate(4096, (i) => i % 251));
    for (final entity in [
      harness.legacyLayout.readerSessionFile,
      harness.legacyLayout.readerBackgroundSettingsFile,
      harness.legacyLayout.appBehaviorSettingsFile,
      harness.legacyLayout.appFontSettingsFile,
      File(
        '${harness.legacyLayout.bookRemarkDatabaseDirectory.path}'
        '${Platform.pathSeparator}book_remarks.isar',
      ),
    ]) {
      if (await entity.exists()) await entity.delete();
    }
    for (final directory in [
      harness.legacyLayout.bookAssetsDirectory,
      harness.legacyLayout.readerBackgroundsDirectory,
      harness.legacyLayout.appFontsDirectory,
    ]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.migrationUnavailable);
    expect(decision.detection?.status, LegacySourceStatus.untrusted);
  });

  test('valid completion marker allows normal start', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    await promoteFully(harness);

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.normalStart);
    expect(decision.marker, isNotNull);
  });

  test('migrating state without completion requires recovery', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    await MigrationStateStore(
      targetLayout: harness.targetLayout,
    ).markMigrating('attempt-x');

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.recoveryRequired);
    expect(decision.reason, contains('未完成'));
  });

  test('promoted database without completion marker requires recovery',
      () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    final result = await harness.runMigration();
    const promotion = MigrationPromotion();
    await promotion.seal(
      staging: result.staging,
      legacyLayout: harness.legacyLayout,
    );
    // Simulate a crash after the rename but before the marker: move the
    // payload database into the root manually, without the marker.
    await harness.targetLayout.rootDirectory.create(recursive: true);
    await result.staging.payloadDatabaseFile.rename(
      harness.targetLayout.sqliteDatabaseFile.path,
    );
    await result.staging.dispose();

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.recoveryRequired);
    expect(decision.reason, contains('完成标记'));
  });

  test('tampered completion marker requires recovery', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    await promoteFully(harness);
    final markerFile = MigrationCompletion.markerFile(harness.targetLayout);
    final decoded =
        jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
    (decoded['counts'] as Map<String, dynamic>)['books'] = 99;
    await markerFile.writeAsString(jsonEncode(decoded));

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.recoveryRequired);
  });

  test('unstable legacy source requires recovery', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);

    final decision = await coordinatorFor(
      harness,
      probeFactory: (layout) => LegacySourceProbe(
        legacyLayout: layout,
        stabilityPause: () async {
          await layout.appBehaviorSettingsFile.writeAsString('{"x":1}');
        },
      ),
    ).decide();

    expect(decision.action, AppBootstrapAction.recoveryRequired);
    expect(decision.detection?.status, LegacySourceStatus.unstable);
  });

  test('stale staging attempt without state requires recovery', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    await MigrationStaging.create(targetLayout: harness.targetLayout);

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.recoveryRequired);
  });

  test('abandoned state starts fresh', () async {
    final harness = await LegacyFixtureMigration.setUp(tempRoot);
    await MigrationStateStore(
      targetLayout: harness.targetLayout,
    ).markAbandoned();

    final decision = await coordinatorFor(harness).decide();

    expect(decision.action, AppBootstrapAction.freshInstall);
  });

  test('debug and profile builds never auto-scan real Documents', () async {
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory('${tempRoot.path}${Platform.pathSeparator}t'),
    );
    for (final mode in [AppBuildMode.debug, AppBuildMode.profile]) {
      // No legacy layout provider: on Windows non-release builds the
      // coordinator must not scan the real Documents directory.
      final decision = await AppBootstrapCoordinator(
        targetLayoutProvider: () async => targetLayout,
        platformProvider: () => AppStoragePlatform.windows,
        buildModeProvider: () => mode,
      ).decide();
      expect(decision.action, AppBootstrapAction.freshInstall);
      expect(decision.detection, isNull);
    }
  });
}
