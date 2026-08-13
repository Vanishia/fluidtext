import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef StorageLayoutProvider = Future<StorageLayout> Function();

enum AppBuildMode {
  debug,
  profile,
  release;

  static AppBuildMode get current {
    if (kReleaseMode) return AppBuildMode.release;
    if (kProfileMode) return AppBuildMode.profile;
    return AppBuildMode.debug;
  }

  static AppBuildMode parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'debug' => AppBuildMode.debug,
      'profile' => AppBuildMode.profile,
      'release' => AppBuildMode.release,
      _ => throw FormatException('Unknown build mode: $value'),
    };
  }
}

enum AppStoragePlatform {
  windows,
  android,
  other;

  static AppStoragePlatform get current {
    if (Platform.isWindows) return AppStoragePlatform.windows;
    if (Platform.isAndroid) return AppStoragePlatform.android;
    return AppStoragePlatform.other;
  }

  String get pathSeparator {
    return switch (this) {
      AppStoragePlatform.windows => r'\',
      AppStoragePlatform.android || AppStoragePlatform.other => '/',
    };
  }
}

class StorageLayout {
  StorageLayout._({
    required this.rootDirectory,
    required this.libraryDatabaseDirectory,
    required this.bookRemarkDatabaseDirectory,
    required this.settingsDirectory,
    required this.appBehaviorSettingsFile,
    required this.readerSessionFile,
    required this.readerBackgroundSettingsFile,
    required this.appFontSettingsFile,
    required this.bookAssetsDirectory,
    required this.readerBackgroundsDirectory,
    required this.appFontsDirectory,
    required this.migrationDirectory,
    required this.recoveryDirectory,
    required this.sqliteDatabaseFile,
    required this.usesLegacyRuntimeLocations,
    required this.pathSeparator,
  });

  static const appBehaviorSettingsFileName = 'app_behavior_settings.json';
  static const readerSessionFileName = 'reader_session.json';
  static const readerBackgroundSettingsFileName = 'reader_background.json';
  static const appFontSettingsFileName = 'app_font_settings.json';
  static const bookAssetsDirectoryName = 'book_assets';
  static const readerBackgroundsDirectoryName = 'reader_backgrounds';
  static const appFontsDirectoryName = 'app_fonts';
  static const migrationDirectoryName = 'migration';
  static const recoveryDirectoryName = 'recovery';
  static const sqliteDatabaseFileName = 'fluidtext_library.sqlite';

  final Directory rootDirectory;
  final Directory libraryDatabaseDirectory;
  final Directory bookRemarkDatabaseDirectory;
  final Directory settingsDirectory;
  final File appBehaviorSettingsFile;
  final File readerSessionFile;
  final File readerBackgroundSettingsFile;
  final File appFontSettingsFile;
  final Directory bookAssetsDirectory;
  final Directory readerBackgroundsDirectory;
  final Directory appFontsDirectory;
  final Directory migrationDirectory;
  final Directory recoveryDirectory;
  final File sqliteDatabaseFile;
  final bool usesLegacyRuntimeLocations;
  final String pathSeparator;

  factory StorageLayout.legacy({
    required Directory documentsDirectory,
    required Directory supportDirectory,
    String? pathSeparator,
  }) {
    final separator = pathSeparator ?? Platform.pathSeparator;
    final documentsPath = documentsDirectory.path;
    final supportPath = supportDirectory.path;
    return StorageLayout._(
      rootDirectory: documentsDirectory,
      libraryDatabaseDirectory: documentsDirectory,
      bookRemarkDatabaseDirectory: documentsDirectory,
      settingsDirectory: documentsDirectory,
      appBehaviorSettingsFile: File(
        joinPath([
          documentsPath,
          appBehaviorSettingsFileName,
        ], separator: separator),
      ),
      readerSessionFile: File(
        joinPath([documentsPath, readerSessionFileName], separator: separator),
      ),
      readerBackgroundSettingsFile: File(
        joinPath([
          documentsPath,
          readerBackgroundSettingsFileName,
        ], separator: separator),
      ),
      appFontSettingsFile: File(
        joinPath([supportPath, appFontSettingsFileName], separator: separator),
      ),
      bookAssetsDirectory: Directory(
        joinPath([
          documentsPath,
          bookAssetsDirectoryName,
        ], separator: separator),
      ),
      readerBackgroundsDirectory: Directory(
        joinPath([
          documentsPath,
          readerBackgroundsDirectoryName,
        ], separator: separator),
      ),
      appFontsDirectory: Directory(
        joinPath([supportPath, appFontsDirectoryName], separator: separator),
      ),
      migrationDirectory: Directory(
        joinPath([documentsPath, migrationDirectoryName], separator: separator),
      ),
      recoveryDirectory: Directory(
        joinPath([documentsPath, recoveryDirectoryName], separator: separator),
      ),
      sqliteDatabaseFile: File(
        joinPath([documentsPath, sqliteDatabaseFileName], separator: separator),
      ),
      usesLegacyRuntimeLocations: true,
      pathSeparator: separator,
    );
  }

  factory StorageLayout.modern({
    required Directory rootDirectory,
    String? pathSeparator,
  }) {
    final separator = pathSeparator ?? Platform.pathSeparator;
    final rootPath = rootDirectory.path;
    final settingsPath = joinPath([rootPath, 'settings'], separator: separator);
    return StorageLayout._(
      rootDirectory: rootDirectory,
      libraryDatabaseDirectory: rootDirectory,
      bookRemarkDatabaseDirectory: rootDirectory,
      settingsDirectory: Directory(settingsPath),
      appBehaviorSettingsFile: File(
        joinPath([
          settingsPath,
          appBehaviorSettingsFileName,
        ], separator: separator),
      ),
      readerSessionFile: File(
        joinPath([settingsPath, readerSessionFileName], separator: separator),
      ),
      readerBackgroundSettingsFile: File(
        joinPath([
          settingsPath,
          readerBackgroundSettingsFileName,
        ], separator: separator),
      ),
      appFontSettingsFile: File(
        joinPath([settingsPath, appFontSettingsFileName], separator: separator),
      ),
      bookAssetsDirectory: Directory(
        joinPath([rootPath, bookAssetsDirectoryName], separator: separator),
      ),
      readerBackgroundsDirectory: Directory(
        joinPath([
          rootPath,
          readerBackgroundsDirectoryName,
        ], separator: separator),
      ),
      appFontsDirectory: Directory(
        joinPath([rootPath, appFontsDirectoryName], separator: separator),
      ),
      migrationDirectory: Directory(
        joinPath([rootPath, migrationDirectoryName], separator: separator),
      ),
      recoveryDirectory: Directory(
        joinPath([rootPath, recoveryDirectoryName], separator: separator),
      ),
      sqliteDatabaseFile: File(
        joinPath([rootPath, sqliteDatabaseFileName], separator: separator),
      ),
      usesLegacyRuntimeLocations: false,
      pathSeparator: separator,
    );
  }

  factory StorageLayout.targetForPlatform({
    required Directory baseDirectory,
    required AppStoragePlatform platform,
    required AppBuildMode buildMode,
  }) {
    final separator = platform.pathSeparator;
    final rootDirectory = switch (platform) {
      AppStoragePlatform.windows => Directory(
        joinPath([
          baseDirectory.path,
          'Vanishia',
          switch (buildMode) {
            AppBuildMode.release => 'FluidText',
            AppBuildMode.debug => 'FluidText-Debug',
            AppBuildMode.profile => 'FluidText-Profile',
          },
        ], separator: separator),
      ),
      AppStoragePlatform.android || AppStoragePlatform.other => baseDirectory,
    };
    return StorageLayout.modern(
      rootDirectory: rootDirectory,
      pathSeparator: separator,
    );
  }

  static String joinPath(Iterable<String> segments, {String separator = '/'}) {
    final iterator = segments.iterator;
    if (!iterator.moveNext()) return '';
    var result = _trimTrailingSeparators(iterator.current);
    while (iterator.moveNext()) {
      final segment = _trimSeparators(iterator.current);
      if (segment.isEmpty) continue;
      result = result.isEmpty ? segment : '$result$separator$segment';
    }
    return result;
  }

  static String _trimSeparators(String value) {
    var result = value;
    while (result.startsWith('/') || result.startsWith(r'\')) {
      result = result.substring(1);
    }
    return _trimTrailingSeparators(result);
  }

  static String _trimTrailingSeparators(String value) {
    var result = value;
    while (_hasRedundantTrailingSeparator(result)) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static bool _hasRedundantTrailingSeparator(String value) {
    if (value.length <= 1) return false;
    if (!value.endsWith('/') && !value.endsWith(r'\')) return false;
    if (RegExp(r'^[A-Za-z]:[\\/]$').hasMatch(value)) return false;
    return true;
  }
}

class AppStorageResolver {
  const AppStorageResolver({
    this.documentsDirectoryProvider = getApplicationDocumentsDirectory,
    this.supportDirectoryProvider = getApplicationSupportDirectory,
    this.localAppDataDirectoryProvider,
    this.platformProvider = _currentStoragePlatform,
    this.buildModeProvider = _currentBuildMode,
  });

  final Future<Directory> Function() documentsDirectoryProvider;
  final Future<Directory> Function() supportDirectoryProvider;
  final Future<Directory> Function()? localAppDataDirectoryProvider;
  final AppStoragePlatform Function() platformProvider;
  final AppBuildMode Function() buildModeProvider;

  static Future<StorageLayout> legacyRuntimeLayout() {
    return const AppStorageResolver().legacyLayout();
  }

  static Future<StorageLayout> targetRuntimeLayout() {
    return const AppStorageResolver().targetLayout();
  }

  Future<StorageLayout> legacyLayout() async {
    return StorageLayout.legacy(
      documentsDirectory: await documentsDirectoryProvider(),
      supportDirectory: await supportDirectoryProvider(),
    );
  }

  Future<StorageLayout> targetLayout() async {
    final platform = platformProvider();
    final baseDirectory = switch (platform) {
      AppStoragePlatform.windows =>
        await (localAppDataDirectoryProvider ??
            _defaultLocalAppDataDirectory)(),
      AppStoragePlatform.android ||
      AppStoragePlatform.other => await supportDirectoryProvider(),
    };
    return StorageLayout.targetForPlatform(
      baseDirectory: baseDirectory,
      platform: platform,
      buildMode: buildModeProvider(),
    );
  }

  static Future<Directory> _defaultLocalAppDataDirectory() async {
    if (Platform.isWindows) {
      final path = Platform.environment['LOCALAPPDATA']?.trim();
      if (path != null && path.isNotEmpty) {
        return Directory(path);
      }
    }
    return getApplicationSupportDirectory();
  }
}

AppStoragePlatform _currentStoragePlatform() => AppStoragePlatform.current;

AppBuildMode _currentBuildMode() => AppBuildMode.current;

class SafeRelativePath {
  const SafeRelativePath._(this.segments);

  final List<String> segments;

  String asPosixPath() => segments.join('/');

  String asPlatformPath({String separator = '/'}) {
    return segments.join(separator);
  }
}

class StoragePathSafety {
  const StoragePathSafety._();

  /// Whether [path] is an absolute path on either Windows or POSIX style
  /// (drive letter, UNC or leading separator).
  static bool isAbsolutePath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  }

  static SafeRelativePath parseRelativePath(
    String relativePath, {
    String label = 'relative path',
  }) {
    final normalized = relativePath.replaceAll(r'\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw FormatException('$label must be relative');
    }
    if (normalized.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw FormatException('$label contains control characters');
    }

    final segments = normalized.split('/');
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(':')) {
        throw FormatException('$label contains an unsafe segment');
      }
    }
    return SafeRelativePath._(List<String>.unmodifiable(segments));
  }

  static File resolveRelativeFile({
    required Directory rootDirectory,
    required String relativePath,
    String? label,
    String separator = '/',
  }) {
    final safePath = parseRelativePath(
      relativePath,
      label: label ?? 'relative path',
    );
    return File(
      StorageLayout.joinPath([
        rootDirectory.path,
        safePath.asPlatformPath(separator: separator),
      ], separator: separator),
    );
  }

  static bool isLexicallyWithinDirectory({
    required String directoryPath,
    required String filePath,
  }) {
    final directory = _normalizeAbsolutePath(directoryPath);
    final file = _normalizeAbsolutePath(filePath);
    final prefix = directory.endsWith(Platform.pathSeparator)
        ? directory
        : '$directory${Platform.pathSeparator}';
    return file == directory || file.startsWith(prefix);
  }

  static Future<bool> isCanonicalFileWithinDirectory({
    required File file,
    required Directory directory,
  }) async {
    final filePath = await _canonicalPath(file);
    final directoryPath = await _canonicalPath(directory);
    return isLexicallyWithinDirectory(
      directoryPath: directoryPath,
      filePath: filePath,
    );
  }

  static Future<bool> isLink(FileSystemEntity entity) async {
    return await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.link;
  }

  static Future<String> _canonicalPath(FileSystemEntity entity) async {
    try {
      return await entity.resolveSymbolicLinks();
    } on FileSystemException {
      return entity.absolute.path;
    }
  }

  static String _normalizeAbsolutePath(String path) {
    final normalized = Directory(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
