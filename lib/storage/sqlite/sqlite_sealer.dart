import 'dart:io';

import 'library_database.dart';

/// Seals a SQLite database file so it can be moved or renamed without
/// depending on uncopied WAL frames.
///
/// Same semantics as `MigrationPromotion.seal` (which stays coupled to the
/// migration staging/error types): `wal_checkpoint(TRUNCATE)`, close, wait
/// for the file lock to be released, remove empty `-wal`/`-shm` sidecars and
/// only finish once both stay absent across consecutive checks.
class SqliteSealer {
  const SqliteSealer._();

  static const _maxAttempts = 40;
  static const _retryDelay = Duration(milliseconds: 50);

  static Future<void> seal(File databaseFile) async {
    final database = LibraryDatabase.file(databaseFile);
    try {
      await database.checkpoint(truncate: true);
    } catch (error) {
      throw StateError('数据库密封失败：$error');
    } finally {
      await database.close();
    }

    // Wait for the closing background connection to fully release the
    // database file FIRST: the native side may recreate the -wal/-shm
    // sidecars while it is still shutting down, so removing them before the
    // release is racy.
    for (var attempt = 0;; attempt++) {
      try {
        final handle = await databaseFile.open(mode: FileMode.append);
        await handle.close();
        break;
      } on FileSystemException catch (error) {
        if (attempt >= _maxAttempts) {
          throw StateError('数据库密封失败：$error');
        }
        await Future<void>.delayed(_retryDelay);
      }
    }

    for (final suffix in const ['-wal', '-shm']) {
      await _removeSealedSidecar('${databaseFile.path}$suffix');
    }

    // The closing connection can briefly recreate a sidecar after we removed
    // it; only finish once both stay absent across consecutive checks.
    var stableRounds = 0;
    for (var attempt = 0;; attempt++) {
      var anyPresent = false;
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('${databaseFile.path}$suffix');
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
        if (stableRounds >= 2) return;
      } else {
        stableRounds = 0;
      }
      if (attempt >= _maxAttempts) {
        throw StateError('数据库密封失败：wal/shm 残留文件在密封后再次出现');
      }
      await Future<void>.delayed(_retryDelay);
    }
  }

  static Future<void> _removeSealedSidecar(String path) async {
    final sidecar = File(path);
    for (var attempt = 0;; attempt++) {
      try {
        if (!await sidecar.exists()) return;
        if (await sidecar.length() > 0) {
          if (attempt >= _maxAttempts) {
            throw StateError('数据库密封失败：$path 在 checkpoint 后仍非空');
          }
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        await sidecar.delete();
        return;
      } on FileSystemException catch (error) {
        // The closing SQLite connection may concurrently remove or hold the
        // sidecar (PathNotFoundException included); retry briefly.
        if (attempt >= _maxAttempts) {
          if (!await sidecar.exists()) return;
          throw StateError('数据库密封失败：$error');
        }
        await Future<void>.delayed(_retryDelay);
      }
    }
  }
}
