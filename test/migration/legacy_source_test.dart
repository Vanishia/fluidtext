import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/migration/legacy_source.dart';
import 'package:fluidtext/storage/storage_layout.dart';

import '../support/isar_test_core.dart';
import '../support/legacy_fixture.dart';

void main() {
  setUpAll(initializeIsarTestCore);

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-source-test-',
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  StorageLayout legacyLayoutFor(Directory fixtureCopy) {
    return StorageLayout.legacy(
      documentsDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}documents',
      ),
      supportDirectory: Directory(
        '${fixtureCopy.path}${Platform.pathSeparator}support',
      ),
    );
  }

  test('fixture root is detected as trusted with a fingerprint', () async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    final probe = LegacySourceProbe(
      legacyLayout: legacyLayoutFor(fixtureCopy),
      stabilityInterval: const Duration(milliseconds: 10),
    );

    final detection = await probe.detect();

    expect(detection.status, LegacySourceStatus.trusted);
    expect(detection.isTrusted, isTrue);
    expect(detection.companionSignals, isNotEmpty);
    expect(detection.companionSignals, contains('book_remarks.isar'));
    expect(detection.companionSignals, contains('book_assets'));
    expect(detection.sourceFingerprint, isNotNull);
    expect(detection.sourceFingerprint, hasLength(64));
  });

  test('empty directory is detected as absent', () async {
    final emptyDocuments = Directory(
      '${tempRoot.path}${Platform.pathSeparator}empty-documents',
    );
    final emptySupport = Directory(
      '${tempRoot.path}${Platform.pathSeparator}empty-support',
    );
    await emptyDocuments.create(recursive: true);
    await emptySupport.create(recursive: true);
    final probe = LegacySourceProbe(
      legacyLayout: StorageLayout.legacy(
        documentsDirectory: emptyDocuments,
        supportDirectory: emptySupport,
      ),
    );

    final detection = await probe.detect();

    expect(detection.status, LegacySourceStatus.absent);
    expect(detection.sourceFingerprint, isNull);
  });

  test('orphan default.isar failing the schema probe is untrusted', () async {
    final documents = Directory(
      '${tempRoot.path}${Platform.pathSeparator}documents',
    )..createSync(recursive: true);
    final support = Directory(
      '${tempRoot.path}${Platform.pathSeparator}support',
    )..createSync(recursive: true);
    // Random bytes with the right file name must not be trusted.
    await File(
      '${documents.path}${Platform.pathSeparator}default.isar',
    ).writeAsBytes(List<int>.generate(4096, (index) => index % 251));
    final probe = LegacySourceProbe(
      legacyLayout: StorageLayout.legacy(
        documentsDirectory: documents,
        supportDirectory: support,
      ),
    );

    final detection = await probe.detect();

    expect(detection.status, LegacySourceStatus.untrusted);
    expect(detection.companionSignals, isEmpty);
    expect(detection.schemaProbeSucceeded, isFalse);
    expect(detection.sourceFingerprint, isNull);
  });

  test('fingerprint is deterministic and changes with source content', () async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    final layout = legacyLayoutFor(fixtureCopy);
    final probe = LegacySourceProbe(
      legacyLayout: layout,
      stabilityInterval: const Duration(milliseconds: 10),
    );

    final first = await probe.computeFingerprint();
    final second = await probe.computeFingerprint();
    expect(second, first);

    final detection = await probe.detect();
    expect(detection.sourceFingerprint, first);

    // Changing any in-scope source file must change the fingerprint.
    await layout.readerSessionFile.writeAsString('{"changed":true}');
    final third = await probe.computeFingerprint();
    expect(third, isNot(first));
  });

  test('source changing between snapshots is detected as unstable', () async {
    final fixtureCopy = await copyLegacyFixture(
      Directory('${tempRoot.path}${Platform.pathSeparator}fixture'),
    );
    final layout = legacyLayoutFor(fixtureCopy);
    final probe = LegacySourceProbe(
      legacyLayout: layout,
      stabilityPause: () async {
        // Simulate a sync tool or old instance writing between snapshots.
        await layout.appBehaviorSettingsFile.writeAsString(
          '{"theme":"mutated"}',
        );
      },
    );

    final detection = await probe.detect();

    expect(detection.status, LegacySourceStatus.unstable);
    expect(detection.sourceFingerprint, isNull);
  });
}
