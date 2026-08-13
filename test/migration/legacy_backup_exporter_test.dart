import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/legacy_backup_exporter.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;
  late LegacyFixtureMigration harness;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-backup-test-',
    );
    harness = await LegacyFixtureMigration.setUp(tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('builds a v2 backup from staging copies without touching originals',
      () async {
    final legacyDocuments = harness.legacyLayout.libraryDatabaseDirectory;

    final backup = await LegacyBackupExporter(
      legacyLayout: harness.legacyLayout,
    ).buildOnly();

    expect(backup.extension, 'zip');
    final archive = ZipDecoder().decodeBytes(backup.bytes);
    final jsonEntry = archive.files.singleWhere(
      (file) => file.name == 'backup.json',
    );
    final payload =
        jsonDecode(utf8.decode(jsonEntry.content as List<int>))
            as Map<String, dynamic>;

    expect(payload['format'], 'fluidtext.backup');
    expect(payload['version'], 2);
    expect(payload['books'], hasLength(2));
    expect(payload['bookCards'], hasLength(3));
    expect(payload['bookAssets'], hasLength(1));
    expect(payload['bookRemarks'], hasLength(2));
    final session = payload['readerSession'] as Map<String, dynamic>;
    expect(session['lastOpenedBookIds'], [1, 2]);

    // The book asset file is embedded.
    expect(
      archive.files.any(
        (file) => file.name == 'book_assets/asset_fixture_one/images/cover.png',
      ),
      isTrue,
    );

    // The original directory was never opened with Isar: no lock files.
    await for (final entity in legacyDocuments.list()) {
      expect(entity.path.endsWith('.lock'), isFalse);
    }
  });
}
