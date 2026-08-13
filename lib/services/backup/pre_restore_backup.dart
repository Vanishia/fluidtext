import 'dart:io';

import '../../repositories/library_repository.dart';
import '../../storage/storage_layout.dart';
import 'backup_export_service.dart';

/// Writes a pre-restore insurance backup of the current library into the
/// recovery directory (plan 7.4 step 3) without involving a file picker.
class PreRestoreBackup {
  const PreRestoreBackup._();

  static Future<File> write({
    required BackupSnapshotRepository repository,
    required StorageLayout layout,
    String appVersion = 'unknown',
    DateTime? createdAt,
  }) async {
    final backup = await const BackupExportService().exportV3(
      repository: repository,
      layout: layout,
      appVersion: appVersion,
      exportedAt: createdAt,
    );
    final timestamp = _timestamp(createdAt ?? DateTime.now());
    final file = File(
      StorageLayout.joinPath([
        layout.recoveryDirectory.path,
        'pre-restore-$timestamp.zip',
      ], separator: layout.pathSeparator),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(backup.bytes, flush: true);
    return file;
  }

  static String _timestamp(DateTime value) {
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}'
        '-${twoDigits(local.hour)}${twoDigits(local.minute)}'
        '${twoDigits(local.second)}';
  }
}
