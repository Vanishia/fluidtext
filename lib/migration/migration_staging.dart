import 'dart:io';
import 'dart:math';

import '../storage/storage_layout.dart';
import 'legacy_isar_reader.dart';

/// Progress callback for staging copies: [copiedBytes] of [totalBytes].
typedef MigrationCopyProgress = void Function(int copiedBytes, int totalBytes);

/// Result of copying the legacy databases into a staging attempt.
class MigrationStagingCopyResult {
  const MigrationStagingCopyResult({
    required this.totalBytes,
    required this.mainDatabaseCopied,
    required this.remarkDatabaseCopied,
  });

  /// Total bytes of the source files that were copied.
  final int totalBytes;

  /// Whether the main `default.isar` copy exists in staging.
  final bool mainDatabaseCopied;

  /// Whether a `book_remarks.isar` copy exists in staging.
  final bool remarkDatabaseCopied;
}

/// Manages one migration staging attempt directory.
///
/// Staging lives under `migration/attempts/<attemptId>/` of the target
/// (modern) storage layout. Only the two legacy database files are copied;
/// runtime `.lock` files are never copied.
class MigrationStaging {
  MigrationStaging._({required this.attemptId, required this.attemptDirectory});

  /// Unique id of this attempt, also the directory name.
  final String attemptId;

  /// `migration/attempts/<attemptId>/` of the target layout.
  final Directory attemptDirectory;

  File get mainDatabaseCopy => File(
    StorageLayout.joinPath([
      attemptDirectory.path,
      legacyMainDatabaseFileName,
    ], separator: _separator),
  );

  File get remarkDatabaseCopy => File(
    StorageLayout.joinPath([
      attemptDirectory.path,
      legacyRemarkDatabaseFileName,
    ], separator: _separator),
  );

  String get _separator => Platform.pathSeparator;

  /// Creates a new staging attempt under the target layout.
  ///
  /// Throws [StateError] when the attempt directory already exists.
  static Future<MigrationStaging> create({
    required StorageLayout targetLayout,
    String? attemptId,
  }) async {
    final separator = targetLayout.pathSeparator;
    final id = attemptId ?? _newAttemptId();
    final directory = Directory(
      StorageLayout.joinPath([
        targetLayout.migrationDirectory.path,
        'attempts',
        id,
      ], separator: separator),
    );
    if (await directory.exists()) {
      throw StateError('Migration attempt already exists: ${directory.path}');
    }
    await directory.create(recursive: true);
    return MigrationStaging._(attemptId: id, attemptDirectory: directory);
  }

  /// Copies the legacy Isar databases into this staging attempt.
  ///
  /// Copies `default.isar` and, when present, `book_remarks.isar` from the
  /// legacy layout. `.lock` runtime files are never copied. [onProgress] is
  /// invoked after each written chunk with cumulative and total bytes.
  Future<MigrationStagingCopyResult> copyLegacyDatabases({
    required StorageLayout legacyLayout,
    MigrationCopyProgress? onProgress,
  }) async {
    final separator = legacyLayout.pathSeparator;
    final mainSource = File(
      StorageLayout.joinPath([
        legacyLayout.libraryDatabaseDirectory.path,
        legacyMainDatabaseFileName,
      ], separator: separator),
    );
    if (!await mainSource.exists()) {
      throw StateError(
        'Legacy main database not found: ${mainSource.path}',
      );
    }
    final remarkSource = File(
      StorageLayout.joinPath([
        legacyLayout.bookRemarkDatabaseDirectory.path,
        legacyRemarkDatabaseFileName,
      ], separator: separator),
    );
    final hasRemarks = await remarkSource.exists();

    final sources = <File>[mainSource, if (hasRemarks) remarkSource];
    final targets = <File>[
      mainDatabaseCopy,
      if (hasRemarks) remarkDatabaseCopy,
    ];

    var totalBytes = 0;
    for (final source in sources) {
      totalBytes += await source.length();
    }

    var copiedBytes = 0;
    for (var index = 0; index < sources.length; index++) {
      copiedBytes = await _copyFile(
        source: sources[index],
        target: targets[index],
        copiedBytes: copiedBytes,
        totalBytes: totalBytes,
        onProgress: onProgress,
      );
    }

    return MigrationStagingCopyResult(
      totalBytes: totalBytes,
      mainDatabaseCopied: true,
      remarkDatabaseCopied: hasRemarks,
    );
  }

  /// Deletes this staging attempt directory.
  Future<void> dispose() async {
    if (await attemptDirectory.exists()) {
      await attemptDirectory.delete(recursive: true);
    }
  }

  static Future<int> _copyFile({
    required File source,
    required File target,
    required int copiedBytes,
    required int totalBytes,
    required MigrationCopyProgress? onProgress,
  }) async {
    final output = target.openWrite();
    var copied = copiedBytes;
    try {
      await for (final chunk in source.openRead()) {
        output.add(chunk);
        copied += chunk.length;
        onProgress?.call(copied, totalBytes);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    return copied;
  }

  static String _newAttemptId() {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}'
        '-'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final suffix = Random()
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$stamp-$suffix';
  }
}
