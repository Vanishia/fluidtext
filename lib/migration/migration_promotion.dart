import 'dart:convert';
import 'dart:io';

import '../storage/json_file_store.dart';
import '../storage/sqlite/library_database.dart';
import '../storage/storage_layout.dart';
import 'library_migrator.dart';
import 'migration_progress.dart';
import 'migration_staging.dart';
import 'migration_state.dart';
import 'migration_validator.dart';

/// Completion marker written after a successful promotion (plan step 13).
class MigrationCompletionMarker {
  const MigrationCompletionMarker({
    required this.source,
    required this.sourceFingerprint,
    required this.sqliteSchemaVersion,
    required this.bookCount,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.verifiedResourceCount,
    required this.completedAt,
  });

  static const format = 'fluidtext.migration_complete';
  static const formatVersion = 1;

  /// Marker written by a real legacy migration.
  static const sourceMigration = 'migration';

  /// Marker written when a fresh install initializes an empty database, so
  /// the next launch takes the normal-start path instead of recovery.
  static const sourceFreshInstall = 'fresh';

  /// `migration` or `fresh`.
  final String source;
  final String? sourceFingerprint;
  final int sqliteSchemaVersion;

  /// Table counts at promotion time, kept for diagnostics. They are NOT
  /// re-verified against the live database on later launches: legitimate
  /// user writes change the counts after migration.
  final int bookCount;
  final int cardCount;
  final int assetCount;
  final int remarkCount;
  final int verifiedResourceCount;
  final DateTime completedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'formatVersion': formatVersion,
    'source': source,
    'sourceFingerprint': sourceFingerprint,
    'sqliteSchemaVersion': sqliteSchemaVersion,
    'counts': <String, Object?>{
      'books': bookCount,
      'bookCards': cardCount,
      'bookAssets': assetCount,
      'bookRemarks': remarkCount,
    },
    'verifiedResources': verifiedResourceCount,
    'integrityCheck': 'ok',
    'completedAt': completedAt.toIso8601String(),
  };

  factory MigrationCompletionMarker.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format || json['formatVersion'] != formatVersion) {
      throw const FormatException('unsupported completion marker format');
    }
    final counts = json['counts'];
    if (counts is! Map<String, dynamic>) {
      throw const FormatException('completion marker misses counts');
    }
    int countOf(String key) {
      final value = counts[key];
      if (value is! num) {
        throw FormatException('completion marker misses count $key');
      }
      return value.toInt();
    }

    final schemaVersion = json['sqliteSchemaVersion'];
    final verifiedResources = json['verifiedResources'];
    final completedAt = DateTime.tryParse(json['completedAt'] as String? ?? '');
    if (schemaVersion is! num || verifiedResources is! num) {
      throw const FormatException('completion marker misses versions');
    }
    return MigrationCompletionMarker(
      source: json['source'] as String? ?? sourceMigration,
      sourceFingerprint: json['sourceFingerprint'] as String?,
      sqliteSchemaVersion: schemaVersion.toInt(),
      bookCount: countOf('books'),
      cardCount: countOf('bookCards'),
      assetCount: countOf('bookAssets'),
      remarkCount: countOf('bookRemarks'),
      verifiedResourceCount: verifiedResources.toInt(),
      completedAt: completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Loads, writes and verifies the migration completion marker.
class MigrationCompletion {
  const MigrationCompletion._();

  static File markerFile(StorageLayout targetLayout) {
    return File(
      StorageLayout.joinPath([
        targetLayout.migrationDirectory.path,
        'complete.json',
      ], separator: targetLayout.pathSeparator),
    );
  }

  /// Returns null when the marker is missing or unreadable.
  static Future<MigrationCompletionMarker?> load(
    StorageLayout targetLayout,
  ) async {
    final file = markerFile(targetLayout);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return MigrationCompletionMarker.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    StorageLayout targetLayout,
    MigrationCompletionMarker marker,
  ) {
    return JsonFileStore.writeAtomic(markerFile(targetLayout), marker.toJson());
  }

  /// Writes the fresh-install marker for a newly initialized empty database.
  static Future<void> writeFreshInstall(StorageLayout targetLayout) {
    return write(
      targetLayout,
      MigrationCompletionMarker(
        source: MigrationCompletionMarker.sourceFreshInstall,
        sourceFingerprint: null,
        sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
        bookCount: 0,
        cardCount: 0,
        assetCount: 0,
        remarkCount: 0,
        verifiedResourceCount: 0,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Verifies the marker against the live database: it must open, pass
  /// integrity and foreign key checks and match the recorded schema version.
  /// Table counts are intentionally not compared because legitimate user
  /// writes change them after migration.
  static Future<bool> verifyLiveDatabase(
    StorageLayout targetLayout,
    MigrationCompletionMarker marker,
  ) async {
    final databaseFile = targetLayout.sqliteDatabaseFile;
    if (!await databaseFile.exists()) return false;
    LibraryDatabase? database;
    try {
      database = LibraryDatabase.file(databaseFile);
      final integrity = await database.integrityCheck();
      if (integrity.length != 1 || integrity.single != 'ok') return false;
      if ((await database.foreignKeyCheck()).isNotEmpty) return false;
      final metadata = await database
          .customSelect(
            "SELECT value FROM storage_metadata WHERE key = 'schema_version'",
          )
          .getSingleOrNull();
      if (metadata == null ||
          metadata.read<String>('value') !=
              marker.sqliteSchemaVersion.toString()) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await database?.close();
    }
  }
}

/// Seals the staging payload and promotes it to the live storage directory
/// (plan steps 11-13).
class MigrationPromotion {
  const MigrationPromotion({MigrationProgressCallback? onProgress})
    : _onProgress = onProgress;

  final MigrationProgressCallback? _onProgress;

  static const _promotionSteps = 3;

  /// Seals the payload database: `wal_checkpoint(TRUNCATE)`, closes the
  /// connection and verifies no non-empty `-wal`/`-shm` remain, so the
  /// promoted directory never depends on uncopied WAL frames.
  Future<void> seal({
    required MigrationStaging staging,
    required StorageLayout legacyLayout,
  }) async {
    _emit(0, _promotionSteps);
    final databaseFile = staging.payloadDatabaseFile;
    final database = LibraryDatabase.file(databaseFile);
    try {
      await database.checkpoint(truncate: true);
    } catch (error) {
      throw _failure(
        '迁移数据库密封失败',
        error,
        staging,
        legacyLayout,
      );
    } finally {
      await database.close();
    }
    // Wait for the closing background connection to fully release the
    // database file FIRST: the native side may recreate the -wal/-shm
    // sidecars while it is still shutting down, so removing them before the
    // release is racy (observed as flaky leftovers on Windows).
    const maxAttempts = 40;
    for (var attempt = 0;; attempt++) {
      try {
        final handle = await databaseFile.open(mode: FileMode.append);
        await handle.close();
        break;
      } on FileSystemException catch (error) {
        if (attempt >= maxAttempts) {
          throw _failure('迁移数据库密封失败', error, staging, legacyLayout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    for (final suffix in const ['-wal', '-shm']) {
      await _removeSealedSidecar(
        '${databaseFile.path}$suffix',
        staging,
        legacyLayout,
      );
    }
    // The closing connection can briefly recreate a sidecar after we removed
    // it; only finish once both stay absent across consecutive checks.
    var stableRounds = 0;
    for (var attempt = 0;; attempt++) {
      final leftovers = <String>[
        for (final suffix in const ['-wal', '-shm'])
          '${databaseFile.path}$suffix',
      ];
      var anyPresent = false;
      for (final path in leftovers) {
        final sidecar = File(path);
        if (await sidecar.exists()) {
          anyPresent = true;
          try {
            if (await sidecar.length() == 0) await sidecar.delete();
          } on FileSystemException {
            // Still held by the closing connection; handled by the retry.
          }
        }
      }
      if (!anyPresent) {
        stableRounds++;
        if (stableRounds >= 2) break;
      } else {
        stableRounds = 0;
      }
      if (attempt >= maxAttempts) {
        throw _failure(
          '迁移数据库密封失败',
          'wal/shm sidecars reappeared after sealing',
          staging,
          legacyLayout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Removes a sealed WAL sidecar, tolerating the race with the background
  /// isolate connection that may still hold or delete the file right after
  /// `close()`.
  Future<void> _removeSealedSidecar(
    String path,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) async {
    final sidecar = File(path);
    const maxAttempts = 40;
    for (var attempt = 0;; attempt++) {
      try {
        if (!await sidecar.exists()) return;
        if (await sidecar.length() > 0) {
          if (attempt >= maxAttempts) {
            throw _failure(
              '迁移数据库密封失败',
              'non-empty $path after checkpoint',
              staging,
              legacyLayout,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        await sidecar.delete();
        return;
      } on FileSystemException catch (error) {
        // The closing SQLite connection may concurrently remove or hold the
        // sidecar (PathNotFoundException included); retry briefly before
        // giving up.
        if (attempt >= maxAttempts) {
          if (!await sidecar.exists()) return;
          throw _failure('迁移数据库密封失败', error, staging, legacyLayout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Promotes the sealed payload into the target root and writes the
  /// completion marker.
  ///
  /// Never overwrites: if any payload entry already exists in the target
  /// root (e.g. after an interrupted promotion), a [MigrationException] with
  /// [MigrationPhase.finalizing] is thrown and the situation must go through
  /// crash recovery instead of a silent overwrite.
  Future<MigrationCompletionMarker> promote({
    required MigrationStaging staging,
    required MigrationResult result,
    required MigrationValidationSummary validation,
    required StorageLayout legacyLayout,
    required StorageLayout targetLayout,
  }) async {
    final root = targetLayout.rootDirectory;
    if (await targetLayout.sqliteDatabaseFile.exists()) {
      throw MigrationException(
        phase: MigrationPhase.finalizing,
        message: '目标目录已存在数据库，已停止切换以保护现有数据',
        diagnostic: 'live database already exists: '
            '${_sanitize(targetLayout.sqliteDatabaseFile.path, staging, legacyLayout)}',
      );
    }
    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    // Rename each payload entry into the root. All entries live on the same
    // volume; individual renames are atomic and a crash between them is
    // detected through the missing completion marker.
    final entries = await staging.payloadDirectory.list().toList();
    final total = _promotionSteps + entries.length;
    var step = 1;
    for (final entity in entries) {
      final name = _basename(entity.path);
      final destination =
          '${root.path}${targetLayout.pathSeparator}$name';
      if (await FileSystemEntity.type(destination) !=
          FileSystemEntityType.notFound) {
        throw MigrationException(
          phase: MigrationPhase.finalizing,
          message: '目标目录已存在同名数据，已停止切换以保护现有数据',
          diagnostic: 'refusing to overwrite: '
              '${_sanitize(destination, staging, legacyLayout)}',
        );
      }
      try {
        await entity.rename(destination);
      } catch (error) {
        throw _failure('迁移切换失败', error, staging, legacyLayout);
      }
      _emit(++step, total);
    }

    final marker = MigrationCompletionMarker(
      source: MigrationCompletionMarker.sourceMigration,
      sourceFingerprint: result.sourceFingerprint,
      sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
      bookCount: result.bookCount,
      cardCount: result.cardCount,
      assetCount: result.assetCount,
      remarkCount: result.remarkCount,
      verifiedResourceCount: validation.verifiedResourceCount,
      completedAt: DateTime.now().toUtc(),
    );
    await MigrationCompletion.write(targetLayout, marker);
    await MigrationStateStore(targetLayout: targetLayout).markIdle();

    // The payload directory is empty after promotion; drop the attempt.
    await staging.dispose();
    _emit(total, total);
    return marker;
  }

  MigrationException _failure(
    String message,
    Object diagnostic,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) {
    return MigrationException(
      phase: MigrationPhase.finalizing,
      message: message,
      diagnostic: _sanitize(diagnostic, staging, legacyLayout),
    );
  }

  String _sanitize(
    Object value,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) {
    var text = value.toString();
    final replacements = <String, String>{
      staging.attemptDirectory.path: '<staging>',
      legacyLayout.rootDirectory.path: '<legacy>',
      legacyLayout.appFontSettingsFile.parent.path: '<legacySupport>',
    };
    final keys = replacements.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (key.isNotEmpty) text = text.replaceAll(key, replacements[key]!);
    }
    return text;
  }

  void _emit(int completed, int total) {
    _onProgress?.call(
      MigrationProgressEvent(
        phase: MigrationPhase.finalizing,
        completed: completed,
        total: total,
      ),
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
