import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../features/reader/reader_background_settings.dart';

class ReaderBackgroundService {
  ReaderBackgroundService._();

  static final instance = ReaderBackgroundService._();
  static const _fileName = 'reader_background.json';

  Future<ReaderBackgroundSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) {
        return const ReaderBackgroundSettings();
      }

      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final settings = ReaderBackgroundSettings.fromJson(json);
      if (!settings.hasCustomImage) return settings;

      final imageFile = File(settings.imagePath!);
      if (await imageFile.exists()) return settings;

      return settings.copyWith(
        source: ReaderBackgroundSource.color,
        clearImagePath: true,
      );
    } catch (_) {
      return const ReaderBackgroundSettings();
    }
  }

  Future<void> save(ReaderBackgroundSettings settings) async {
    final file = await _settingsFile();
    final payload = <String, Object?>{
      ...settings.toJson(),
      'savedAt': DateTime.now().toIso8601String(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<ReaderBackgroundSettings?> importImage(
    ReaderBackgroundSettings current,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final importedPath = await _persistPickedImage(result.files.single);
    if (importedPath == null) return null;

    await _deleteManagedImage(current.imagePath);
    return current.copyWith(
      source: ReaderBackgroundSource.image,
      imagePath: importedPath,
    );
  }

  Future<ReaderBackgroundSettings> clearImportedImage(
    ReaderBackgroundSettings current,
  ) async {
    await _deleteManagedImage(current.imagePath);
    return current.copyWith(
      source: ReaderBackgroundSource.color,
      clearImagePath: true,
    );
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  Future<String?> _persistPickedImage(PlatformFile file) async {
    final dir = await _imageDirectory();
    final extension = _normalizedExtension(file);
    final targetPath =
        '${dir.path}${Platform.pathSeparator}custom_background_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final targetFile = File(targetPath);

    if (file.path case final sourcePath?) {
      await File(sourcePath).copy(targetPath);
      return targetFile.path;
    }

    final bytes = file.bytes;
    if (bytes == null) return null;

    await targetFile.writeAsBytes(bytes, flush: true);
    return targetFile.path;
  }

  Future<Directory> _imageDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(
      '${dir.path}${Platform.pathSeparator}reader_backgrounds',
    );
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  Future<void> _deleteManagedImage(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return;
    if (!await _isManagedImage(imagePath)) return;

    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> _isManagedImage(String imagePath) async {
    final managedDir = await _imageDirectory();
    final normalizedImagePath = File(imagePath).absolute.path;
    final normalizedDirPath = managedDir.absolute.path;
    return normalizedImagePath.startsWith(normalizedDirPath);
  }

  String _normalizedExtension(PlatformFile file) {
    final extension = file.extension;
    if (extension != null && extension.isNotEmpty) {
      return extension.toLowerCase();
    }

    final path = file.path;
    if (path == null) return 'jpg';

    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return 'jpg';
    return path.substring(dotIndex + 1).toLowerCase();
  }
}
