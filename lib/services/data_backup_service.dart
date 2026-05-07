import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_card.dart';
import 'book_remark_service.dart';
import 'reader_session_service.dart';

class DataBackupService {
  const DataBackupService();

  static const backupFormatVersion = 1;

  Future<String?> exportBackup(Isar isar) async {
    final exportedAt = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'format': 'fluidtext.backup',
      'version': backupFormatVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'books': await isar.books.where().exportJson(),
      'bookCards': await isar.bookCards.where().exportJson(),
      'bookRemarks': await BookRemarkService.instance.exportJson(),
      'readerSession': await ReaderSessionService.instance.exportJson(),
    };
    final prettyJson = const JsonEncoder.withIndent('  ').convert(payload);
    final fileName = _backupFileName(exportedAt);
    final bytes = Uint8List.fromList(utf8.encode(prettyJson));

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出 FluidText 备份',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );

    if (savedPath == null) return null;

    return savedPath;
  }

  String _backupFileName(DateTime exportedAt) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final local = exportedAt.toLocal();
    final date =
        '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}';
    final time =
        '${twoDigits(local.hour)}${twoDigits(local.minute)}${twoDigits(local.second)}';
    return 'fluidtext-backup-$date-$time.json';
  }
}
