import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../features/reader/reader_background_settings.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';

class ReaderBackgroundService {
  ReaderBackgroundService({
    StorageLayoutProvider? storageLayout,
    Future<Directory> Function()? documentsDirectory,
  }) : _fileProvider = _settingsFileProvider(
         storageLayout: storageLayout,
         documentsDirectory: documentsDirectory,
       ),
       _imageDirectoryProvider = _managedImageDirectoryProvider(
         storageLayout: storageLayout,
         documentsDirectory: documentsDirectory,
       );

  static final instance = ReaderBackgroundService();
  static const _fileName = StorageLayout.readerBackgroundSettingsFileName;

  final Future<File> Function() _fileProvider;
  final Future<Directory> Function() _imageDirectoryProvider;

  static Future<File> Function() _settingsFileProvider({
    required StorageLayoutProvider? storageLayout,
    required Future<Directory> Function()? documentsDirectory,
  }) {
    if (storageLayout != null) {
      return () async => (await storageLayout()).readerBackgroundSettingsFile;
    }
    final directoryProvider =
        documentsDirectory ?? getApplicationDocumentsDirectory;
    return () async {
      final dir = await directoryProvider();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    };
  }

  static Future<Directory> Function() _managedImageDirectoryProvider({
    required StorageLayoutProvider? storageLayout,
    required Future<Directory> Function()? documentsDirectory,
  }) {
    if (storageLayout != null) {
      return () async => (await storageLayout()).readerBackgroundsDirectory;
    }
    final directoryProvider =
        documentsDirectory ?? getApplicationDocumentsDirectory;
    return () async {
      final dir = await directoryProvider();
      return Directory(
        '${dir.path}${Platform.pathSeparator}'
        '${StorageLayout.readerBackgroundsDirectoryName}',
      );
    };
  }

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

      final imageFile = await _resolveStoredImagePath(settings.imagePath!);
      if (imageFile != null && await imageFile.exists()) {
        // Consumers use imagePath directly; always expose a resolved path.
        return settings.copyWith(imagePath: imageFile.path);
      }

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
    if (settings.hasCustomImage) {
      // Persist managed images as controlled relative paths so the settings
      // survive storage directory moves; foreign paths stay absolute.
      final relative = await _managedRelativeImagePath(settings.imagePath!);
      if (relative != null) payload['imagePath'] = relative;
    }
    await JsonFileStore.writeAtomic(file, payload);
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
    return _fileProvider();
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
    final imageDir = await _imageDirectoryProvider();
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  Future<void> _deleteManagedImage(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return;
    final file = await _resolveStoredImagePath(imagePath);
    if (file == null || !await file.exists()) return;
    if (!await _isManagedImage(file)) return;
    await file.delete();
  }

  /// Resolves a stored image path to a file. Absolute paths are used as-is;
  /// controlled relative paths (`reader_backgrounds/<name>`) resolve inside
  /// the managed backgrounds directory. Returns null for unsafe paths.
  Future<File?> _resolveStoredImagePath(String imagePath) async {
    if (StoragePathSafety.isAbsolutePath(imagePath)) return File(imagePath);
    final SafeRelativePath safePath;
    try {
      safePath = StoragePathSafety.parseRelativePath(
        imagePath,
        label: 'background image path',
      );
    } on FormatException {
      return null;
    }
    const directoryName = StorageLayout.readerBackgroundsDirectoryName;
    if (safePath.segments.length < 2 || safePath.segments.first != directoryName) {
      return null;
    }
    final directory = await _imageDirectoryProvider();
    return File(
      StorageLayout.joinPath([
        directory.path,
        ...safePath.segments.sublist(1),
      ], separator: Platform.pathSeparator),
    );
  }

  /// Returns `reader_backgrounds/<name>` when [imagePath] points inside the
  /// managed backgrounds directory, or null otherwise.
  Future<String?> _managedRelativeImagePath(String imagePath) async {
    if (!StoragePathSafety.isAbsolutePath(imagePath)) return null;
    final directory = await _imageDirectory();
    if (!StoragePathSafety.isLexicallyWithinDirectory(
      directoryPath: directory.path,
      filePath: imagePath,
    )) {
      return null;
    }
    final directoryPath = directory.path.replaceAll(r'\', '/');
    final relative = imagePath
        .replaceAll(r'\', '/')
        .substring(directoryPath.length + 1);
    return '${StorageLayout.readerBackgroundsDirectoryName}/$relative';
  }

  Future<bool> _isManagedImage(File imageFile) async {
    final managedDir = await _imageDirectory();
    final normalizedImagePath = await imageFile.resolveSymbolicLinks();
    final normalizedDirPath = await managedDir.resolveSymbolicLinks();
    final directoryPrefix = normalizedDirPath.endsWith(Platform.pathSeparator)
        ? normalizedDirPath
        : '$normalizedDirPath${Platform.pathSeparator}';
    return normalizedImagePath.startsWith(directoryPrefix);
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
