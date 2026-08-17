import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_promotion.dart';
import 'package:fluidtext/migration/migration_validator.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;
  late LegacyFixtureMigration harness;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-validation-test-',
    );
    harness = await LegacyFixtureMigration.setUp(tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('valid payload passes validation with matching summary', () async {
    final result = await harness.runMigration();
    final events = <MigrationProgressEvent>[];

    final summary = await MigrationValidator(
      onProgress: events.add,
    ).validate(result: result, legacyLayout: harness.legacyLayout);

    expect(summary.bookCount, 2);
    expect(summary.cardCount, 3);
    expect(summary.assetCount, 1);
    expect(summary.remarkCount, 2);
    expect(summary.maxBookId, 2);
    expect(summary.verifiedResourceCount, result.copiedResourceHashes.length);
    expect(events, isNotEmpty);
    expect(
      events.every((event) => event.phase == MigrationPhase.validating),
      isTrue,
    );
    expect(events.last.fraction, 1.0);
  });

  test('tampered resource file fails validation', () async {
    final result = await harness.runMigration();
    final cover = File(
      '${result.staging.payloadDirectory.path}'
      '${Platform.pathSeparator}book_assets'
      '${Platform.pathSeparator}asset_fixture_one'
      '${Platform.pathSeparator}images${Platform.pathSeparator}cover.png',
    );
    await cover.writeAsBytes(
      [...await cover.readAsBytes(), 0],
    );

    await expectLater(
      MigrationValidator().validate(
        result: result,
        legacyLayout: harness.legacyLayout,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.validating,
        ),
      ),
    );
  });

  test('count mismatch fails validation', () async {
    final result = await harness.runMigration();
    final database = LibraryDatabase.file(result.staging.payloadDatabaseFile);
    final card = await database
        .customSelect('SELECT id FROM book_cards ORDER BY id LIMIT 1')
        .getSingle();
    await database.customStatement(
      'DELETE FROM book_cards WHERE id = ?',
      [card.read<int>('id')],
    );
    await database.close();

    await expectLater(
      MigrationValidator().validate(
        result: result,
        legacyLayout: harness.legacyLayout,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.validating,
        ),
      ),
    );
  });

  test('per-book card mismatch fails validation', () async {
    final result = await harness.runMigration();
    final database = LibraryDatabase.file(result.staging.payloadDatabaseFile);
    // Move a card to the other book without changing totals: the aggregate
    // count stays 3 but the per-book distribution changes.
    final card = await database
        .customSelect(
          'SELECT id, book_id FROM book_cards ORDER BY id LIMIT 1',
        )
        .getSingle();
    final cardId = card.read<int>('id');
    final otherBookId = card.read<int>('book_id') == 1 ? 2 : 1;
    await database.customStatement(
      'UPDATE book_cards SET book_id = ?, card_index = 7 WHERE id = ?',
      [otherBookId, cardId],
    );
    await database.close();

    await expectLater(
      MigrationValidator().validate(
        result: result,
        legacyLayout: harness.legacyLayout,
      ),
      throwsA(
        isA<MigrationException>().having(
          (error) => error.phase,
          'phase',
          MigrationPhase.validating,
        ),
      ),
    );
  });

  test('seal removes wal sidecars and the payload stays readable', () async {
    final result = await harness.runMigration();
    await MigrationValidator().validate(
      result: result,
      legacyLayout: harness.legacyLayout,
    );

    const promotion = MigrationPromotion();
    await promotion.seal(
      staging: result.staging,
      legacyLayout: harness.legacyLayout,
    );

    await for (final entity in result.staging.payloadDirectory.list()) {
      expect(entity.path.endsWith('-wal'), isFalse);
      expect(entity.path.endsWith('-shm'), isFalse);
    }

    final database = LibraryDatabase.file(result.staging.payloadDatabaseFile);
    addTearDown(database.close);
    expect(await database.integrityCheck(), ['ok']);
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM book_cards')
        .getSingle();
    expect(row.read<int>('c'), 3);
  });

  test('completion marker verifies the live database and detects tampering',
      () async {
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
    final marker = await promotion.promote(
      staging: result.staging,
      result: result,
      validation: validation,
      legacyLayout: harness.legacyLayout,
      targetLayout: harness.targetLayout,
    );

    expect(marker.sourceFingerprint, 'test-fingerprint');
    expect(marker.sqliteSchemaVersion, LibraryDatabase.currentSchemaVersion);
    expect(marker.bookCount, 2);
    expect(marker.cardCount, 3);

    final loaded = await MigrationCompletion.load(harness.targetLayout);
    expect(loaded, isNotNull);
    expect(
      await MigrationCompletion.verifyLiveDatabase(
        harness.targetLayout,
        loaded!,
      ),
      isTrue,
    );

    // Tampering with the recorded schema version invalidates the marker.
    // (Table counts are intentionally not re-verified: legitimate user
    // writes change them after migration.)
    final tampered = MigrationCompletionMarker(
      source: loaded.source,
      sourceFingerprint: loaded.sourceFingerprint,
      sqliteSchemaVersion: loaded.sqliteSchemaVersion + 1,
      bookCount: loaded.bookCount,
      cardCount: loaded.cardCount,
      assetCount: loaded.assetCount,
      remarkCount: loaded.remarkCount,
      verifiedResourceCount: loaded.verifiedResourceCount,
      completedAt: loaded.completedAt,
    );
    expect(
      await MigrationCompletion.verifyLiveDatabase(
        harness.targetLayout,
        tampered,
      ),
      isFalse,
    );
  });
}
