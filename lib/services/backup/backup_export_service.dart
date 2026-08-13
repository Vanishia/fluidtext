import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../repositories/library_repository.dart';
import '../../storage/sqlite/library_database.dart';
import '../../storage/storage_layout.dart';
import '../data_backup_service.dart' show BackupFile;
import 'backup_format.dart';

/// Builds v3 backup archives: a full application backup containing the
/// manifest, the backend-neutral library payload, the four settings JSON
/// files and every managed resource (book assets, reader backgrounds, app
/// fonts).
class BackupExportService {
  const BackupExportService();

  static const backupFormatVersion = 3;

  static const _settingsDirectoryName = 'settings';
  static const _libraryJsonPath = 'data/library.json';

  /// Exports the library of [repository] plus all managed files under
  /// [layout] as a single v3 ZIP archive.
  ///
  /// The file picker / save-dialog flow deliberately lives in the caller.
  Future<BackupFile> exportV3({
    required BackupSnapshotRepository repository,
    required StorageLayout layout,
    String appVersion = 'unknown',
    DateTime? exportedAt,
    void Function(String warning)? onWarning,
  }) async {
    final snapshot = await repository.buildBackupSnapshot();
    final timestamp = (exportedAt ?? DateTime.now()).toUtc();
    final data = BackupLibraryData.fromSnapshot(snapshot);

    final archive = Archive();
    final manifestFiles = <BackupManifestFile>[];

    void addBytesEntry(String path, List<int> bytes) {
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
      manifestFiles.add(
        BackupManifestFile(
          path: path,
          bytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        ),
      );
    }

    final libraryJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(data.toLibraryJson());
    addBytesEntry(_libraryJsonPath, utf8.encode(libraryJson));

    // Settings: include only the files that actually exist, read verbatim.
    final settingsFiles = <String, File>{
      StorageLayout.appBehaviorSettingsFileName: layout.appBehaviorSettingsFile,
      StorageLayout.readerSessionFileName: layout.readerSessionFile,
      StorageLayout.readerBackgroundSettingsFileName:
          layout.readerBackgroundSettingsFile,
      StorageLayout.appFontSettingsFileName: layout.appFontSettingsFile,
    };
    for (final entry in settingsFiles.entries) {
      final file = entry.value;
      if (!await file.exists()) continue;
      addBytesEntry(
        '$_settingsDirectoryName/${entry.key}',
        await file.readAsBytes(),
      );
    }

    // Book assets referenced by the snapshot: include only files that exist
    // and pass the path-safety checks.
    final seenAssetPaths = <String>{};
    for (final asset in snapshot.bookAssets) {
      final relativePath = asset.relativePath.replaceAll(r'\', '/');
      if (!seenAssetPaths.add(relativePath)) continue;
      final SafeRelativePath safePath;
      try {
        safePath = StoragePathSafety.parseRelativePath(
          relativePath,
          label: 'book asset path',
        );
      } on FormatException {
        onWarning?.call('跳过路径不安全的书籍资源：$relativePath');
        continue;
      }
      final file = File(
        StorageLayout.joinPath([
          layout.rootDirectory.path,
          safePath.asPlatformPath(separator: Platform.pathSeparator),
        ], separator: Platform.pathSeparator),
      );
      if (!await file.exists()) {
        onWarning?.call('书籍资源文件缺失，未写入备份：$relativePath');
        continue;
      }
      addBytesEntry(relativePath, await file.readAsBytes());
    }

    // Managed background images and fonts: include every regular file, skip
    // symlinks with a warning.
    for (final directory in [
      layout.readerBackgroundsDirectory,
      layout.appFontsDirectory,
    ]) {
      if (!await directory.exists()) continue;
      final directoryName = directory.path
          .replaceAll(r'\', '/')
          .split('/')
          .last;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          if (await StoragePathSafety.isLink(entity)) {
            onWarning?.call('跳过符号链接：${entity.path}');
          }
          continue;
        }
        final fileName = entity.path.replaceAll(r'\', '/').split('/').last;
        addBytesEntry(
          '$directoryName/$fileName',
          await entity.readAsBytes(),
        );
      }
    }

    final manifest = BackupManifest(
      sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
      appVersion: appVersion,
      platform: Platform.operatingSystem,
      exportedAt: timestamp,
      counts: BackupManifestCounts(
        books: snapshot.books.length,
        bookCards: snapshot.bookCards.length,
        bookAssets: snapshot.bookAssets.length,
        bookRemarks: snapshot.bookRemarks.length,
      ),
      files: manifestFiles,
    );
    final manifestJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(manifest.toJson());
    // manifest.json itself is not part of manifest.files.
    final manifestBytes = utf8.encode(manifestJson);
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return BackupFile(
      fileName: _backupFileName(timestamp),
      extension: 'zip',
      bytes: bytes,
    );
  }

  String _backupFileName(DateTime exportedAt) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final local = exportedAt.toLocal();
    final date =
        '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}';
    final time =
        '${twoDigits(local.hour)}${twoDigits(local.minute)}${twoDigits(local.second)}';
    return 'fluidtext-backup-$date-$time.zip';
  }
}
