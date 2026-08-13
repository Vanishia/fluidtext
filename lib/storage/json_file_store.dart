import 'dart:convert';
import 'dart:io';

/// Atomic JSON file writes: same-directory temp file, flush, then rename
/// over the target so readers never observe a partially written file.
class JsonFileStore {
  const JsonFileStore._();

  /// Writes [value] as JSON to [file] atomically.
  static Future<void> writeAtomic(File file, Object? value) {
    return writeAtomicString(file, jsonEncode(value));
  }

  /// Writes raw [contents] to [file] atomically.
  ///
  /// The parent directory is created when missing. The temp file is removed
  /// if the write or rename fails.
  static Future<void> writeAtomicString(File file, String contents) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final tempFile = File('${file.path}.tmp');
    try {
      final sink = tempFile.openWrite();
      try {
        sink.write(contents);
        await sink.flush();
      } finally {
        await sink.close();
      }
      await tempFile.rename(file.path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }
}
