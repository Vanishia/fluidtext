import 'dart:convert';
import 'dart:io';

import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';
import 'migration_progress.dart';

/// Lifecycle status persisted in `migration/state.json`.
enum MigrationLifecycleStatus { idle, migrating, failed, abandoned }

/// Snapshot of `migration/state.json`.
class MigrationStateSnapshot {
  const MigrationStateSnapshot({
    required this.status,
    this.attemptId,
    this.phase,
    this.message,
    this.liveDatabaseVerified = false,
  });

  static const idle = MigrationStateSnapshot(
    status: MigrationLifecycleStatus.idle,
  );

  final MigrationLifecycleStatus status;
  final String? attemptId;
  final MigrationPhase? phase;

  /// User-facing failure message (Chinese) when status is failed.
  final String? message;

  /// Whether the live database passed one full verification after the last
  /// migration/promotion. Verified databases skip the expensive integrity
  /// check on later cold starts.
  final bool liveDatabaseVerified;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': MigrationStateStore.format,
    'status': status.name,
    'attemptId': attemptId,
    'phase': phase?.name,
    'message': message,
    'liveDatabaseVerified': liveDatabaseVerified,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory MigrationStateSnapshot.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'];
    final status = MigrationLifecycleStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => MigrationLifecycleStatus.idle,
    );
    final phaseName = json['phase'];
    final phase = phaseName is String
        ? MigrationPhase.values.firstWhere(
            (value) => value.name == phaseName,
            orElse: () => MigrationPhase.detectingLegacyData,
          )
        : null;
    return MigrationStateSnapshot(
      status: status,
      attemptId: json['attemptId'] as String?,
      phase: phase,
      message: json['message'] as String?,
      liveDatabaseVerified: json['liveDatabaseVerified'] == true,
    );
  }
}

/// Manages `migration/state.json` of the target layout.
///
/// The completion marker (`migration/complete.json`) is the source of truth
/// for a finished migration; this state file records in-flight and failed
/// attempts so a crashed migration is recognised on the next launch. All
/// writes are atomic.
class MigrationStateStore {
  const MigrationStateStore({required this.targetLayout});

  static const format = 'fluidtext.migration_state';

  final StorageLayout targetLayout;

  File get stateFile => File(
    StorageLayout.joinPath([
      targetLayout.migrationDirectory.path,
      'state.json',
    ], separator: targetLayout.pathSeparator),
  );

  Future<MigrationStateSnapshot> load() async {
    final file = stateFile;
    if (!await file.exists()) return MigrationStateSnapshot.idle;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != format) {
        return MigrationStateSnapshot.idle;
      }
      return MigrationStateSnapshot.fromJson(decoded);
    } catch (_) {
      return MigrationStateSnapshot.idle;
    }
  }

  Future<void> markMigrating(String attemptId) {
    return _write(
      MigrationStateSnapshot(
        status: MigrationLifecycleStatus.migrating,
        attemptId: attemptId,
      ),
    );
  }

  Future<void> markFailed(
    String attemptId,
    MigrationPhase phase,
    String message,
  ) {
    return _write(
      MigrationStateSnapshot(
        status: MigrationLifecycleStatus.failed,
        attemptId: attemptId,
        phase: phase,
        message: message,
      ),
    );
  }

  Future<void> markAbandoned() {
    return _write(
      const MigrationStateSnapshot(status: MigrationLifecycleStatus.abandoned),
    );
  }

  Future<void> markIdle() async {
    final file = stateFile;
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Records that the live database passed one full post-migration
  /// verification, so later cold starts can skip the integrity check.
  Future<void> markLiveDatabaseVerified() {
    return _write(
      const MigrationStateSnapshot(
        status: MigrationLifecycleStatus.idle,
        liveDatabaseVerified: true,
      ),
    );
  }

  Future<void> _write(MigrationStateSnapshot snapshot) {
    return JsonFileStore.writeAtomic(stateFile, snapshot.toJson());
  }
}

/// Cleanup helpers for crash recovery. Old legacy data is never touched;
/// only staging attempts and incomplete promotion results are removed.
class MigrationRecovery {
  const MigrationRecovery._();

  /// Deletes one staging attempt directory when present.
  static Future<void> discardAttempt(
    StorageLayout targetLayout,
    String attemptId,
  ) async {
    final directory = Directory(
      StorageLayout.joinPath([
        targetLayout.migrationDirectory.path,
        'attempts',
        attemptId,
      ], separator: targetLayout.pathSeparator),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Deletes every staging attempt directory.
  static Future<void> pruneAttempts(StorageLayout targetLayout) async {
    final attempts = Directory(
      StorageLayout.joinPath([
        targetLayout.migrationDirectory.path,
        'attempts',
      ], separator: targetLayout.pathSeparator),
    );
    if (await attempts.exists()) {
      await attempts.delete(recursive: true);
    }
  }

  /// Removes a partially promoted target root: everything except the
  /// `migration/` bookkeeping directory. Only call this when the completion
  /// marker is missing or invalid, i.e. the root does not hold a valid live
  /// database.
  static Future<void> discardIncompleteTarget(StorageLayout targetLayout) async {
    final root = targetLayout.rootDirectory;
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      final name = entity.path.replaceAll(r'\', '/');
      if (name.endsWith('/${StorageLayout.migrationDirectoryName}')) {
        continue;
      }
      await entity.delete(recursive: true);
    }
  }

  /// Whether any staging attempt directories exist.
  static Future<bool> hasAttempts(StorageLayout targetLayout) async {
    final attempts = Directory(
      StorageLayout.joinPath([
        targetLayout.migrationDirectory.path,
        'attempts',
      ], separator: targetLayout.pathSeparator),
    );
    if (!await attempts.exists()) return false;
    await for (final _ in attempts.list(followLinks: false)) {
      return true;
    }
    return false;
  }
}
