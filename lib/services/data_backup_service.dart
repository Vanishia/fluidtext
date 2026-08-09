import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import 'book_asset_store.dart';
import 'book_remark_service.dart';
import 'reader_session_service.dart';

class DataBackupService {
  const DataBackupService({
    BookAssetStore? assetStore,
    Future<List<Map<String, dynamic>>> Function()? remarksExporter,
    Future<Map<String, dynamic>?> Function()? readerSessionExporter,
  }) : _assetStore = assetStore,
       _remarksExporter = remarksExporter,
       _readerSessionExporter = readerSessionExporter;

  static const backupFormatVersion = 2;

  final BookAssetStore? _assetStore;
  final Future<List<Map<String, dynamic>>> Function()? _remarksExporter;
  final Future<Map<String, dynamic>?> Function()? _readerSessionExporter;

  Future<String?> exportBackup(Isar isar) async {
    final backup = await buildBackup(isar);

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出 FluidText 备份',
      fileName: backup.fileName,
      type: FileType.custom,
      allowedExtensions: [backup.extension],
      bytes: backup.bytes,
    );

    if (savedPath == null) return null;

    return savedPath;
  }

  Future<BackupFile> buildBackup(Isar isar, {DateTime? exportedAt}) async {
    final timestamp = (exportedAt ?? DateTime.now()).toUtc();
    final bookAssets = await isar.bookAssets.where().findAll();
    final payload = <String, Object?>{
      'format': 'fluidtext.backup',
      'version': backupFormatVersion,
      'exportedAt': timestamp.toIso8601String(),
      'books': await isar.books.where().exportJson(),
      'bookAssets': bookAssets.map(_bookAssetToJson).toList(),
      'bookCards': await isar.bookCards.where().exportJson(),
      'bookRemarks':
          await (_remarksExporter?.call() ??
              BookRemarkService.instance.exportJson()),
      'readerSession':
          await (_readerSessionExporter?.call() ??
              ReaderSessionService.instance.exportJson()),
    };
    final prettyJson = const JsonEncoder.withIndent('  ').convert(payload);
    final hasAssets = bookAssets.isNotEmpty;
    final fileName = _backupFileName(timestamp, asZip: hasAssets);
    final bytes = hasAssets
        ? await _zipBackupBytes(prettyJson, bookAssets)
        : Uint8List.fromList(utf8.encode(prettyJson));
    return BackupFile(
      fileName: fileName,
      extension: hasAssets ? 'zip' : 'json',
      bytes: bytes,
    );
  }

  Future<Uint8List> _zipBackupBytes(
    String backupJson,
    List<BookAsset> assets,
  ) async {
    final archive = Archive();
    final jsonBytes = utf8.encode(backupJson);
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));

    final seenPaths = <String>{};
    for (final asset in assets) {
      if (!seenPaths.add(asset.relativePath)) continue;
      final file = await (_assetStore ?? BookAssetStore.instance)
          .resolveRelativeFile(asset.relativePath);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile(
          asset.relativePath.replaceAll(r'\', '/'),
          bytes.length,
          bytes,
        ),
      );
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Map<String, Object?> _bookAssetToJson(BookAsset asset) {
    return {
      'id': asset.id,
      'bookId': asset.bookId,
      'assetKey': asset.assetKey,
      'originalHref': asset.originalHref,
      'normalizedHref': asset.normalizedHref,
      'mimeType': asset.mimeType,
      'relativePath': asset.relativePath,
      'byteLength': asset.byteLength,
      'createdAt': asset.createdAt.toIso8601String(),
    };
  }

  String _backupFileName(DateTime exportedAt, {required bool asZip}) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final local = exportedAt.toLocal();
    final date =
        '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}';
    final time =
        '${twoDigits(local.hour)}${twoDigits(local.minute)}${twoDigits(local.second)}';
    return 'fluidtext-backup-$date-$time.${asZip ? 'zip' : 'json'}';
  }
}

class BackupFile {
  const BackupFile({
    required this.fileName,
    required this.extension,
    required this.bytes,
  });

  final String fileName;
  final String extension;
  final Uint8List bytes;
}
