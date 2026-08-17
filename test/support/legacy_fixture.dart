import 'dart:convert';
import 'dart:io';

import 'package:fluidtext/migration/legacy_source.dart';
import 'package:fluidtext/migration/library_migrator.dart';
import 'package:fluidtext/migration/migration_progress.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/storage/storage_layout.dart';

/// Root of the checked-in 1.0.0 legacy Isar fixture.
final Directory legacyFixtureRoot = Directory('test/fixtures/legacy_isar_1_0_0');

/// Copies the legacy fixture into [target], which must not exist yet.
Future<Directory> copyLegacyFixture(Directory target) async {
  await copyDirectoryRecursive(legacyFixtureRoot, target);
  return target;
}

Future<void> copyDirectoryRecursive(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: false, followLinks: false)) {
    final targetPath =
        '${target.path}${Platform.pathSeparator}${pathBaseName(entity.path)}';
    if (entity is Directory) {
      await copyDirectoryRecursive(entity, Directory(targetPath));
    } else if (entity is File) {
      await entity.copy(targetPath);
    }
  }
}

String pathBaseName(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

/// Hermetic fixture-based migration harness: copies the 1.0.0 fixture into
/// a temp directory, builds legacy/target layouts and rewrites the fixture's
/// absolute background/font paths to point inside the temp copy.
class LegacyFixtureMigration {
  LegacyFixtureMigration._({
    required this.fixtureCopy,
    required this.legacyLayout,
    required this.targetLayout,
  });

  final Directory fixtureCopy;
  final StorageLayout legacyLayout;
  final StorageLayout targetLayout;

  /// Trusted detection used to drive [LibraryMigrator] in tests.
  static const detection = LegacySourceDetection(
    status: LegacySourceStatus.trusted,
    companionSignals: ['book_remarks.isar'],
    sourceFingerprint: 'test-fingerprint',
  );

  static Future<LegacyFixtureMigration> setUp(Directory tempRoot) async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    final legacyLayout = StorageLayout.legacy(
      documentsDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}documents',
      ),
      supportDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}support',
      ),
    );
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );
    // The checked-in fixture stores absolute paths into the original fixture
    // location; point them at this temp copy so tests are hermetic.
    await rewriteJsonValue(
      legacyLayout.readerBackgroundSettingsFile,
      'imagePath',
      '${legacyLayout.readerBackgroundsDirectory.path}'
      '${Platform.pathSeparator}legacy_background.png',
    );
    await rewriteJsonValue(
      legacyLayout.appFontSettingsFile,
      'fontPath',
      '${legacyLayout.appFontsDirectory.path}'
      '${Platform.pathSeparator}legacy.ttf',
    );
    return LegacyFixtureMigration._(
      fixtureCopy: fixtureCopy,
      legacyLayout: legacyLayout,
      targetLayout: targetLayout,
    );
  }

  /// Creates a fresh staging attempt and runs the migration into it.
  Future<MigrationResult> runMigration({
    int batchSize = 500,
    MigrationProgressCallback? onProgress,
  }) async {
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    return LibraryMigrator(batchSize: batchSize, onProgress: onProgress)
        .migrate(
          detection: detection,
          legacyLayout: legacyLayout,
          staging: staging,
        );
  }
}

Future<void> rewriteJsonValue(File file, String key, Object? value) async {
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  json[key] = value;
  await file.writeAsString(jsonEncode(json));
}
