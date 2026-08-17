import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/storage_layout.dart';
import 'legacy_isar_reader.dart';

/// Outcome of probing a legacy storage layout for FluidText data.
enum LegacySourceStatus {
  /// No legacy main database exists at all.
  absent,

  /// A `default.isar` file exists but cannot be confirmed as FluidText data.
  untrusted,

  /// The legacy source is confirmed and stable; safe to migrate from.
  trusted,

  /// The source changed between two snapshots, so it may still be written by
  /// an old app instance or sync software.
  unstable,
}

/// Result of a [LegacySourceProbe.detect] run.
class LegacySourceDetection {
  const LegacySourceDetection({
    required this.status,
    this.companionSignals = const [],
    this.sourceFingerprint,
    this.schemaProbeSucceeded = false,
  });

  final LegacySourceStatus status;

  /// Names of FluidText companion files or directories found next to the
  /// main database (e.g. `book_remarks.isar`, `book_assets`).
  final List<String> companionSignals;

  /// Deterministic SHA-256 fingerprint of the migration-relevant source
  /// files. Only set when [status] is [LegacySourceStatus.trusted].
  final String? sourceFingerprint;

  /// Whether a schema probe on a temporary copy succeeded. Only attempted
  /// when no companion signals were found.
  final bool schemaProbeSucceeded;

  bool get isTrusted => status == LegacySourceStatus.trusted;
}

/// Detects and fingerprints legacy FluidText data in a given legacy layout.
///
/// The probe never writes to the legacy layout: schema probes run against a
/// temporary copy. Platform auto-scan policy is decided by a later stage; this
/// probe only inspects the injected [legacyLayout].
class LegacySourceProbe {
  const LegacySourceProbe({
    required this.legacyLayout,
    this.stabilityInterval = const Duration(milliseconds: 250),
    this.stabilityPause,
  });

  /// The legacy layout to inspect (a fixture root in tests).
  final StorageLayout legacyLayout;

  /// Delay between the two stability snapshots.
  final Duration stabilityInterval;

  /// Test hook invoked between the two stability snapshots instead of
  /// waiting [stabilityInterval].
  final Future<void> Function()? stabilityPause;

  File get mainDatabaseFile => File(
    StorageLayout.joinPath([
      legacyLayout.libraryDatabaseDirectory.path,
      legacyMainDatabaseFileName,
    ], separator: legacyLayout.pathSeparator),
  );

  File get remarkDatabaseFile => File(
    StorageLayout.joinPath([
      legacyLayout.bookRemarkDatabaseDirectory.path,
      legacyRemarkDatabaseFileName,
    ], separator: legacyLayout.pathSeparator),
  );

  /// Detects whether the legacy layout holds trustworthy FluidText data.
  Future<LegacySourceDetection> detect() async {
    if (!await mainDatabaseFile.exists()) {
      return const LegacySourceDetection(status: LegacySourceStatus.absent);
    }

    final signals = await _detectCompanionSignals();
    var probeSucceeded = false;
    var candidateTrusted = signals.isNotEmpty;
    if (!candidateTrusted) {
      // A lone default.isar may belong to another application; only trust it
      // when a copy opens with the legacy schema.
      probeSucceeded = await _probeTemporaryCopy();
      candidateTrusted = probeSucceeded;
    }
    if (!candidateTrusted) {
      return LegacySourceDetection(
        status: LegacySourceStatus.untrusted,
        companionSignals: signals,
        schemaProbeSucceeded: probeSucceeded,
      );
    }

    final firstPayload = await _computeFingerprintPayload();
    final pause = stabilityPause;
    if (pause != null) {
      await pause();
    } else {
      await Future<void>.delayed(stabilityInterval);
    }
    final secondPayload = await _computeFingerprintPayload();
    if (firstPayload != secondPayload) {
      return LegacySourceDetection(
        status: LegacySourceStatus.unstable,
        companionSignals: signals,
        schemaProbeSucceeded: probeSucceeded,
      );
    }

    return LegacySourceDetection(
      status: LegacySourceStatus.trusted,
      companionSignals: signals,
      sourceFingerprint: sha256.convert(utf8.encode(secondPayload)).toString(),
      schemaProbeSucceeded: probeSucceeded,
    );
  }

  /// Computes the deterministic source fingerprint without stability checks.
  Future<String> computeFingerprint() async {
    final payload = await _computeFingerprintPayload();
    return sha256.convert(utf8.encode(payload)).toString();
  }

  Future<List<String>> _detectCompanionSignals() async {
    final signals = <String>[];
    if (await remarkDatabaseFile.exists()) {
      signals.add(legacyRemarkDatabaseFileName);
    }
    if (await legacyLayout.readerSessionFile.exists()) {
      signals.add(StorageLayout.readerSessionFileName);
    }
    if (await legacyLayout.appBehaviorSettingsFile.exists()) {
      signals.add(StorageLayout.appBehaviorSettingsFileName);
    }
    if (await legacyLayout.readerBackgroundSettingsFile.exists()) {
      signals.add(StorageLayout.readerBackgroundSettingsFileName);
    }
    if (await legacyLayout.appFontSettingsFile.exists()) {
      signals.add(StorageLayout.appFontSettingsFileName);
    }
    if (await legacyLayout.bookAssetsDirectory.exists()) {
      signals.add(StorageLayout.bookAssetsDirectoryName);
    }
    if (await legacyLayout.readerBackgroundsDirectory.exists()) {
      signals.add(StorageLayout.readerBackgroundsDirectoryName);
    }
    if (await legacyLayout.appFontsDirectory.exists()) {
      signals.add(StorageLayout.appFontsDirectoryName);
    }
    return signals;
  }

  Future<bool> _probeTemporaryCopy() async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-legacy-probe-',
    );
    try {
      final mainCopy = File(
        StorageLayout.joinPath([
          tempDirectory.path,
          legacyMainDatabaseFileName,
        ], separator: legacyLayout.pathSeparator),
      );
      await mainDatabaseFile.copy(mainCopy.path);
      return await LegacyIsarReader.probeCopy(
        stagingRoot: tempDirectory,
        mainDatabaseCopy: mainCopy,
      );
    } catch (_) {
      return false;
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  /// Builds a canonical, deterministic payload describing every source file
  /// in migration scope. Two identical payloads mean the source is stable.
  Future<String> _computeFingerprintPayload() async {
    final lines = <String>[];

    Future<void> addHashedFile(String label, File file) async {
      if (!await file.exists()) return;
      final digest = await sha256.bind(file.openRead()).first;
      lines.add('file|$label|${await file.length()}|$digest');
    }

    await addHashedFile(legacyMainDatabaseFileName, mainDatabaseFile);
    await addHashedFile(legacyRemarkDatabaseFileName, remarkDatabaseFile);
    await addHashedFile(
      'settings/${StorageLayout.appBehaviorSettingsFileName}',
      legacyLayout.appBehaviorSettingsFile,
    );
    await addHashedFile(
      'settings/${StorageLayout.readerSessionFileName}',
      legacyLayout.readerSessionFile,
    );
    await addHashedFile(
      'settings/${StorageLayout.readerBackgroundSettingsFileName}',
      legacyLayout.readerBackgroundSettingsFile,
    );
    await addHashedFile(
      'settings/${StorageLayout.appFontSettingsFileName}',
      legacyLayout.appFontSettingsFile,
    );

    // Resource directories are summarized as a manifest of
    // relative path + size + mtime to avoid hashing large binaries twice.
    await _addResourceManifest(
      lines,
      StorageLayout.bookAssetsDirectoryName,
      legacyLayout.bookAssetsDirectory,
    );
    await _addResourceManifest(
      lines,
      StorageLayout.readerBackgroundsDirectoryName,
      legacyLayout.readerBackgroundsDirectory,
    );
    await _addResourceManifest(
      lines,
      StorageLayout.appFontsDirectoryName,
      legacyLayout.appFontsDirectory,
    );

    lines.sort();
    return (StringBuffer('fluidtext.legacy_source.v1\n')
          ..writeAll(lines, '\n')
          ..write('\n'))
        .toString();
  }

  Future<void> _addResourceManifest(
    List<String> lines,
    String directoryName,
    Directory directory,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (await StoragePathSafety.isLink(entity)) continue;
      final stat = await entity.stat();
      final relative = _relativePosixPath(directory, entity);
      lines.add(
        'resource|$directoryName/$relative|'
        '${stat.size}|${stat.modified.microsecondsSinceEpoch}',
      );
    }
  }

  static String _relativePosixPath(Directory root, File file) {
    final rootPath = root.path.replaceAll(r'\', '/');
    var filePath = file.path.replaceAll(r'\', '/');
    if (filePath.startsWith('$rootPath/')) {
      filePath = filePath.substring(rootPath.length + 1);
    }
    return filePath;
  }
}
