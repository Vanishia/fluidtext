import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../features/settings/app_font_settings.dart';
import '../storage/json_file_store.dart';
import '../storage/storage_layout.dart';

typedef AppFontDirectoryProvider = Future<Directory> Function();
typedef AppFontPicker = Future<PlatformFile?> Function();
typedef AppFontRegistrar = Future<void> Function(String family, File file);

class AppFontService {
  AppFontService({
    StorageLayoutProvider? storageLayout,
    AppFontDirectoryProvider? supportDirectory,
    AppFontPicker? picker,
    AppFontRegistrar? registrar,
  }) : _settingsFileProvider = _settingsFileProviderFor(
         storageLayout: storageLayout,
         supportDirectory: supportDirectory,
       ),
       _fontsDirectoryProvider = _fontsDirectoryProviderFor(
         storageLayout: storageLayout,
         supportDirectory: supportDirectory,
       ),
       _picker = picker ?? _pickFontFile,
       _registrar = registrar ?? _registerFont;

  static final instance = AppFontService();
  static const _settingsFileName = StorageLayout.appFontSettingsFileName;
  static const _fontsDirectoryName = StorageLayout.appFontsDirectoryName;
  static const maxFontBytes = 32 * 1024 * 1024;

  final Future<File> Function() _settingsFileProvider;
  final Future<Directory> Function() _fontsDirectoryProvider;
  final AppFontPicker _picker;
  final AppFontRegistrar _registrar;
  final Set<String> _registeredFamilies = <String>{};

  static Future<File> Function() _settingsFileProviderFor({
    required StorageLayoutProvider? storageLayout,
    required AppFontDirectoryProvider? supportDirectory,
  }) {
    if (storageLayout != null) {
      return () async => (await storageLayout()).appFontSettingsFile;
    }
    final directoryProvider = supportDirectory;
    if (directoryProvider == null) {
      return () async =>
          (await AppStorageResolver.activeRuntimeLayout()).appFontSettingsFile;
    }
    return () async {
      final directory = await directoryProvider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return File(
        '${directory.path}${Platform.pathSeparator}$_settingsFileName',
      );
    };
  }

  static Future<Directory> Function() _fontsDirectoryProviderFor({
    required StorageLayoutProvider? storageLayout,
    required AppFontDirectoryProvider? supportDirectory,
  }) {
    if (storageLayout != null) {
      return () async => (await storageLayout()).appFontsDirectory;
    }
    final directoryProvider = supportDirectory;
    if (directoryProvider == null) {
      return () async =>
          (await AppStorageResolver.activeRuntimeLayout()).appFontsDirectory;
    }
    return () async {
      final support = await directoryProvider();
      return Directory(
        '${support.path}${Platform.pathSeparator}$_fontsDirectoryName',
      );
    };
  }

  Future<AppFontSettings> load() async {
    try {
      final settingsFile = await _settingsFile();
      if (!await settingsFile.exists()) {
        return const AppFontSettings.system();
      }

      final decoded = jsonDecode(await settingsFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const AppFontSettings.system();
      }

      final settings = AppFontSettings.fromJson(decoded);
      if (!settings.usesCustomFont) return settings;

      final fontFile = await _resolveStoredFontPath(settings.fontPath!);
      if (fontFile == null || !await fontFile.exists()) {
        await _restoreSystemSettings();
        return const AppFontSettings.system();
      }

      await _register(settings.fontFamily!, fontFile);
      // Consumers use fontPath directly; always expose a resolved path.
      return AppFontSettings(
        source: settings.source,
        fontFamily: settings.fontFamily,
        displayName: settings.displayName,
        fontPath: fontFile.path,
      );
    } catch (_) {
      await _restoreSystemSettings();
      return const AppFontSettings.system();
    }
  }

  Future<AppFontSettings?> importFont(AppFontSettings current) async {
    final picked = await _picker();
    if (picked == null) return null;

    final extension = _normalizedExtension(picked.name);
    if (extension != 'ttf' && extension != 'otf') {
      throw const AppFontImportException('仅支持 TTF 或 OTF 字体文件。');
    }
    if (picked.size > maxFontBytes) {
      throw const AppFontImportException('字体文件不能超过 32 MB。');
    }

    final bytes = await _readPickedBytes(picked);
    if (bytes.isEmpty) {
      throw const AppFontImportException('字体文件为空。');
    }
    if (bytes.length > maxFontBytes) {
      throw const AppFontImportException('字体文件不能超过 32 MB。');
    }
    if (!_looksLikeSupportedFont(bytes)) {
      throw const AppFontImportException('字体文件格式无效或不受支持。');
    }

    final fileHash = sha256.convert(bytes).toString();
    final family = 'FluidTextUserFont_${fileHash.substring(0, 16)}';
    final directory = await _fontsDirectory();
    final target = File(
      '${directory.path}${Platform.pathSeparator}${fileHash.substring(0, 24)}.$extension',
    );
    if (!await target.exists()) {
      await target.writeAsBytes(bytes, flush: true);
    }

    try {
      await _register(family, target);
    } catch (_) {
      await _deleteIfExists(target);
      throw const AppFontImportException('字体文件无法加载，可能已损坏或格式不受支持。');
    }

    final next = AppFontSettings(
      source: AppFontSource.custom,
      fontFamily: family,
      displayName: _displayName(picked.name),
      fontPath: target.path,
    );
    await _writeSettings(next);
    if (current.fontPath != next.fontPath) {
      await _deleteManagedFont(current.fontPath);
    }
    return next;
  }

  Future<AppFontSettings> useSystemFont(AppFontSettings current) async {
    const next = AppFontSettings.system();
    await _writeSettings(next);
    await _deleteManagedFont(current.fontPath);
    return next;
  }

  Future<void> _register(String family, File file) async {
    if (_registeredFamilies.contains(family)) return;
    await _registrar(family, file);
    _registeredFamilies.add(family);
  }

  Future<Uint8List> _readPickedBytes(PlatformFile file) async {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      try {
        return await File(path).readAsBytes();
      } on FileSystemException {
        throw const AppFontImportException('无法读取所选字体文件。');
      }
    }
    final bytes = file.bytes;
    if (bytes != null) return bytes;
    throw const AppFontImportException('无法读取所选字体文件。');
  }

  Future<File> _settingsFile() async {
    final file = await _settingsFileProvider();
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<Directory> _fontsDirectory() async {
    final directory = await _fontsDirectoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _writeSettings(AppFontSettings settings) async {
    final file = await _settingsFile();
    final payload = <String, Object?>{
      ...settings.toJson(),
      'savedAt': DateTime.now().toIso8601String(),
    };
    final fontPath = settings.fontPath;
    if (settings.usesCustomFont && fontPath != null) {
      // Persist managed fonts as controlled relative paths so the settings
      // survive storage directory moves; foreign paths stay absolute.
      final relative = await _managedRelativeFontPath(fontPath);
      if (relative != null) payload['fontPath'] = relative;
    }
    await JsonFileStore.writeAtomic(file, payload);
  }

  /// Resolves a stored font path to a file. Absolute paths are used as-is;
  /// controlled relative paths (`app_fonts/<name>`) resolve inside the
  /// managed fonts directory. Returns null for unsafe paths.
  Future<File?> _resolveStoredFontPath(String fontPath) async {
    if (StoragePathSafety.isAbsolutePath(fontPath)) return File(fontPath);
    final SafeRelativePath safePath;
    try {
      safePath = StoragePathSafety.parseRelativePath(
        fontPath,
        label: 'font path',
      );
    } on FormatException {
      return null;
    }
    const directoryName = StorageLayout.appFontsDirectoryName;
    if (safePath.segments.length < 2 ||
        safePath.segments.first != directoryName) {
      return null;
    }
    final directory = await _fontsDirectoryProvider();
    return File(
      StorageLayout.joinPath([
        directory.path,
        ...safePath.segments.sublist(1),
      ], separator: Platform.pathSeparator),
    );
  }

  /// Returns `app_fonts/<name>` when [fontPath] points inside the managed
  /// fonts directory, or null otherwise.
  Future<String?> _managedRelativeFontPath(String fontPath) async {
    if (!StoragePathSafety.isAbsolutePath(fontPath)) return null;
    final directory = await _fontsDirectory();
    if (!StoragePathSafety.isLexicallyWithinDirectory(
      directoryPath: directory.path,
      filePath: fontPath,
    )) {
      return null;
    }
    final directoryPath = directory.path.replaceAll(r'\', '/');
    final relative = fontPath
        .replaceAll(r'\', '/')
        .substring(directoryPath.length + 1);
    return '${StorageLayout.appFontsDirectoryName}/$relative';
  }

  Future<void> _restoreSystemSettings() async {
    try {
      await _writeSettings(const AppFontSettings.system());
    } catch (_) {
      // Falling back to the system font must not block app startup.
    }
  }

  Future<void> _deleteManagedFont(String? path) async {
    if (path == null || path.isEmpty) return;
    final directory = await _fontsDirectory();
    final fontFile = File(path).absolute;
    final directoryPath = directory.absolute.path;
    final prefix = directoryPath.endsWith(Platform.pathSeparator)
        ? directoryPath
        : '$directoryPath${Platform.pathSeparator}';
    if (!fontFile.path.startsWith(prefix)) return;
    await _deleteIfExists(fontFile);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  static Future<PlatformFile?> _pickFontFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      allowMultiple: false,
      withData: false,
      dialogTitle: '选择字体文件',
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single;
  }

  static Future<void> _registerFont(String family, File file) async {
    final loader = FontLoader(family);
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await loader.load();
  }

  String _normalizedExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _displayName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final name = dot <= 0 ? fileName : fileName.substring(0, dot);
    final trimmed = name.trim();
    return trimmed.isEmpty ? '自定义字体' : trimmed;
  }

  bool _looksLikeSupportedFont(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final tag = String.fromCharCodes(bytes.take(4));
    return tag == 'OTTO' ||
        (bytes[0] == 0x00 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x00 &&
            bytes[3] == 0x00);
  }
}

class AppFontImportException implements Exception {
  const AppFontImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
