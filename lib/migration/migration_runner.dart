import '../storage/sqlite/library_database.dart';
import '../storage/storage_layout.dart';
import 'app_bootstrap_coordinator.dart';
import 'library_migrator.dart';
import 'migration_progress.dart';
import 'migration_promotion.dart';
import 'migration_staging.dart';
import 'migration_state.dart';
import 'migration_validator.dart';

/// Successful end-to-end migration run.
class MigrationRunResult {
  const MigrationRunResult({
    required this.marker,
    required this.bookCount,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.warnings,
  });

  factory MigrationRunResult.fromMigration(
    MigrationResult migration,
    MigrationCompletionMarker marker,
  ) {
    return MigrationRunResult(
      marker: marker,
      bookCount: migration.bookCount,
      cardCount: migration.cardCount,
      assetCount: migration.assetCount,
      remarkCount: migration.remarkCount,
      warnings: migration.warnings,
    );
  }

  /// The completion marker written during promotion.
  final MigrationCompletionMarker marker;

  final int bookCount;
  final int cardCount;
  final int assetCount;
  final int remarkCount;

  /// Non-fatal warnings collected during migration (Chinese).
  final List<String> warnings;
}

/// Task signature used by the migration page so tests can inject fakes.
typedef MigrationRunTask =
    Future<MigrationRunResult> Function({
      required AppBootstrapDecision decision,
      MigrationProgressCallback? onProgress,
    });

/// Single facade that orchestrates staging → migrate → validate → seal →
/// promote and keeps `migration/state.json` in sync (plan steps 2-13).
class MigrationRunner {
  MigrationRunner({this.batchSize = 500});

  final int batchSize;

  /// The default task implementation used by the migration page.
  static Future<MigrationRunResult> runDecision({
    required AppBootstrapDecision decision,
    MigrationProgressCallback? onProgress,
  }) {
    return MigrationRunner().run(decision: decision, onProgress: onProgress);
  }

  Future<MigrationRunResult> run({
    required AppBootstrapDecision decision,
    MigrationProgressCallback? onProgress,
  }) async {
    final legacyLayout = decision.legacyLayout;
    final detection = decision.detection;
    if (legacyLayout == null || detection == null || !detection.isTrusted) {
      throw ArgumentError(
        'MigrationRunner requires a decision with a trusted detection',
      );
    }
    final targetLayout = decision.targetLayout;

    // Retries always start from a clean slate; old attempts are copies.
    await MigrationRecovery.pruneAttempts(targetLayout);
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    final stateStore = MigrationStateStore(targetLayout: targetLayout);
    await stateStore.markMigrating(staging.attemptId);

    var phase = MigrationPhase.copyingDatabase;
    try {
      final result = await LibraryMigrator(
        batchSize: batchSize,
        onProgress: onProgress,
      ).migrate(
        detection: detection,
        legacyLayout: legacyLayout,
        staging: staging,
      );

      phase = MigrationPhase.validating;
      final validation = await MigrationValidator(
        onProgress: onProgress,
      ).validate(result: result, legacyLayout: legacyLayout);

      phase = MigrationPhase.finalizing;
      final promotion = MigrationPromotion(onProgress: onProgress);
      await promotion.seal(staging: staging, legacyLayout: legacyLayout);
      final marker = await promotion.promote(
        staging: staging,
        result: result,
        validation: validation,
        legacyLayout: legacyLayout,
        targetLayout: targetLayout,
      );

      return MigrationRunResult.fromMigration(result, marker);
    } on MigrationException catch (error) {
      await stateStore.markFailed(staging.attemptId, error.phase, error.message);
      rethrow;
    } catch (error) {
      await stateStore.markFailed(staging.attemptId, phase, '迁移失败');
      throw MigrationException(
        phase: phase,
        message: '迁移失败',
        diagnostic: error.toString(),
      );
    }
  }
}

/// Initializes an empty live SQLite database and writes the fresh-install
/// completion marker (fresh install and abandon-migration paths).
Future<void> initializeFreshStorage(StorageLayout targetLayout) async {
  await targetLayout.rootDirectory.create(recursive: true);
  final database = await openLibraryDatabaseForLayout(() async => targetLayout);
  // Force the background connection to actually open the file: schema
  // creation and storage_metadata writes happen on first use.
  await database.integrityCheck();
  await database.close();
  await MigrationCompletion.writeFreshInstall(targetLayout);
  await MigrationStateStore(targetLayout: targetLayout).markIdle();
}

/// Abandons the migration: marks the state abandoned, removes staging
/// attempts and any incomplete promotion result, then initializes a fresh
/// empty database so the app can start normally.
Future<void> abandonMigration(StorageLayout targetLayout) async {
  await MigrationStateStore(targetLayout: targetLayout).markAbandoned();
  await MigrationRecovery.pruneAttempts(targetLayout);
  await MigrationRecovery.discardIncompleteTarget(targetLayout);
  await initializeFreshStorage(targetLayout);
}

/// Cleans up after a failed/interrupted migration so a retry starts from a
/// clean slate. Legacy data is never touched.
Future<void> prepareMigrationRetry(StorageLayout targetLayout) async {
  await MigrationRecovery.discardIncompleteTarget(targetLayout);
  await MigrationRecovery.pruneAttempts(targetLayout);
  await MigrationStateStore(targetLayout: targetLayout).markIdle();
}
