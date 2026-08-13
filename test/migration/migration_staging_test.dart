import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/legacy_isar_reader.dart';
import 'package:fluidtext/migration/migration_staging.dart';
import 'package:fluidtext/storage/storage_layout.dart';

import '../support/legacy_fixture.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-staging-test-',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<(MigrationStaging, StorageLayout)> createStagingWithFixture() async {
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
    final staging = await MigrationStaging.create(targetLayout: targetLayout);
    return (staging, legacyLayout);
  }

  test('staging is created under migration/attempts with unique ids', () async {
    final targetLayout = StorageLayout.modern(
      rootDirectory: Directory(
        '${tempRoot.path}${Platform.pathSeparator}target',
      ),
    );

    final first = await MigrationStaging.create(targetLayout: targetLayout);
    final second = await MigrationStaging.create(targetLayout: targetLayout);

    final expectedPrefix = StorageLayout.joinPath([
      targetLayout.migrationDirectory.path,
      'attempts',
    ], separator: targetLayout.pathSeparator);
    expect(first.attemptDirectory.path.startsWith(expectedPrefix), isTrue);
    expect(first.attemptId, isNot(second.attemptId));
    expect(await first.attemptDirectory.exists(), isTrue);
    expect(await second.attemptDirectory.exists(), isTrue);
  });

  test('copies both databases, skips lock files and reports bytes', () async {
    final (staging, legacyLayout) = await createStagingWithFixture();

    // Runtime lock files next to the sources must never be copied.
    await File(
      '${legacyLayout.libraryDatabaseDirectory.path}'
      '${Platform.pathSeparator}default.isar.lock',
    ).writeAsBytes([1, 2, 3]);
    await File(
      '${legacyLayout.bookRemarkDatabaseDirectory.path}'
      '${Platform.pathSeparator}book_remarks.isar.lock',
    ).writeAsBytes([4, 5, 6]);

    final progressEvents = <(int, int)>[];
    final result = await staging.copyLegacyDatabases(
      legacyLayout: legacyLayout,
      onProgress: (copied, total) => progressEvents.add((copied, total)),
    );

    final mainSource = File(
      '${legacyLayout.libraryDatabaseDirectory.path}'
      '${Platform.pathSeparator}$legacyMainDatabaseFileName',
    );
    final remarkSource = File(
      '${legacyLayout.bookRemarkDatabaseDirectory.path}'
      '${Platform.pathSeparator}$legacyRemarkDatabaseFileName',
    );
    final expectedTotal =
        await mainSource.length() + await remarkSource.length();

    expect(result.totalBytes, expectedTotal);
    expect(result.mainDatabaseCopied, isTrue);
    expect(result.remarkDatabaseCopied, isTrue);
    expect(await staging.mainDatabaseCopy.length(), await mainSource.length());
    expect(
      await staging.remarkDatabaseCopy.length(),
      await remarkSource.length(),
    );

    expect(progressEvents, isNotEmpty);
    expect(progressEvents.last, (expectedTotal, expectedTotal));
    for (var index = 1; index < progressEvents.length; index++) {
      expect(progressEvents[index].$1 >= progressEvents[index - 1].$1, isTrue);
      expect(progressEvents[index].$2, expectedTotal);
    }

    await for (final entity in staging.attemptDirectory.list()) {
      expect(entity.path.endsWith('.lock'), isFalse);
    }
  });

  test('copy succeeds when remark database is missing', () async {
    final (staging, legacyLayout) = await createStagingWithFixture();
    await File(
      '${legacyLayout.bookRemarkDatabaseDirectory.path}'
      '${Platform.pathSeparator}$legacyRemarkDatabaseFileName',
    ).delete();

    final result = await staging.copyLegacyDatabases(
      legacyLayout: legacyLayout,
    );

    expect(result.mainDatabaseCopied, isTrue);
    expect(result.remarkDatabaseCopied, isFalse);
    expect(await staging.mainDatabaseCopy.exists(), isTrue);
    expect(await staging.remarkDatabaseCopy.exists(), isFalse);
  });

  test('dispose removes the staging attempt directory', () async {
    final (staging, legacyLayout) = await createStagingWithFixture();
    await staging.copyLegacyDatabases(legacyLayout: legacyLayout);
    expect(await staging.attemptDirectory.exists(), isTrue);

    await staging.dispose();

    expect(await staging.attemptDirectory.exists(), isFalse);
  });
}
