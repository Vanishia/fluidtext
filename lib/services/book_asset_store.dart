import 'dart:developer' as developer;
import 'dart:io';

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../storage/storage_layout.dart';
import 'app_logger.dart';

class BookAssetFileDraft {
  const BookAssetFileDraft({
    required this.assetKey,
    required this.extension,
    required this.bytes,
  });

  final String assetKey;
  final String extension;
  final List<int> bytes;
}

class BookAssetStore {
  BookAssetStore({
    StorageLayoutProvider? storageLayout,
    Future<Directory> Function()? documentsDirectory,
  }) : _storageRootDirectory = _storageRootProvider(
         storageLayout: storageLayout,
         documentsDirectory: documentsDirectory,
       );

  static final instance = BookAssetStore();
  static const assetsDirectoryName = StorageLayout.bookAssetsDirectoryName;

  final Future<Directory> Function() _storageRootDirectory;

  static Future<Directory> Function() _storageRootProvider({
    required StorageLayoutProvider? storageLayout,
    required Future<Directory> Function()? documentsDirectory,
  }) {
    if (storageLayout != null) {
      return () async => (await storageLayout()).rootDirectory;
    }
    final directoryProvider = documentsDirectory;
    if (directoryProvider == null) {
      return () async =>
          (await AppStorageResolver.activeRuntimeLayout()).rootDirectory;
    }
    return directoryProvider;
  }

  String createAssetRootKey(String fileHash) {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final hashPrefix = fileHash.length <= 12
        ? fileHash
        : fileHash.substring(0, 12);
    return 'asset_${stamp}_$hashPrefix';
  }

  String relativeImagePath({
    required String assetRootKey,
    required String assetKey,
    required String extension,
  }) {
    return '$assetsDirectoryName/$assetRootKey/images/$assetKey$extension';
  }

  Future<void> writeAssetFiles({
    required String assetRootKey,
    required Iterable<BookAssetFileDraft> assets,
  }) async {
    final uniqueAssets = <String, BookAssetFileDraft>{};
    for (final asset in assets) {
      uniqueAssets.putIfAbsent(asset.assetKey, () => asset);
    }

    for (final asset in uniqueAssets.values) {
      await writeAssetFile(
        assetRootKey: assetRootKey,
        assetKey: asset.assetKey,
        extension: asset.extension,
        bytes: asset.bytes,
      );
    }
  }

  Future<String> writeAssetFile({
    required String assetRootKey,
    required String assetKey,
    required String extension,
    required List<int> bytes,
  }) async {
    if (!_isSafeAssetRootKey(assetRootKey)) {
      throw const FormatException('Invalid book asset root key');
    }
    final relativePath = relativeImagePath(
      assetRootKey: assetRootKey,
      assetKey: assetKey,
      extension: extension,
    );
    final file = await resolveRelativeFile(relativePath);
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return relativePath;
  }

  Future<void> pruneAssetRoot({
    required String assetRootKey,
    required Set<String> retainedRelativePaths,
  }) async {
    if (!_isSafeAssetRootKey(assetRootKey)) {
      throw const FormatException('Invalid book asset root key');
    }

    final retainedPaths = <String>{};
    for (final relativePath in retainedRelativePaths) {
      final segments = _safeRelativeSegments(relativePath);
      if (segments.length != 4 ||
          segments[0] != assetsDirectoryName ||
          segments[1] != assetRootKey ||
          segments[2] != 'images') {
        throw const FormatException('Invalid retained book asset path');
      }
      retainedPaths.add(_joinPath(segments));
    }

    final dir = await _storageRootDirectory();
    final root = Directory(
      _joinPath([dir.path, assetsDirectoryName, assetRootKey]),
    );
    if (!await root.exists()) return;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File && entity is! Link) continue;
      final relativePath = _relativePathWithinDirectory(dir.path, entity.path);
      if (!retainedPaths.contains(relativePath)) {
        await entity.delete();
      }
    }
  }

  Future<File> resolveRelativeFile(String relativePath) async {
    final dir = await _storageRootDirectory();
    final segments = _safeRelativeSegments(relativePath);
    if (segments.length != 4 ||
        segments[0] != assetsDirectoryName ||
        !_isSafeAssetRootKey(segments[1]) ||
        segments[2] != 'images') {
      throw const FormatException('Invalid book asset path');
    }
    return File(_joinPath([dir.path, ...segments]));
  }

  Future<void> deleteAssetRoot(String? assetRootKey) async {
    final key = assetRootKey?.trim();
    if (key == null || !_isSafeAssetRootKey(key)) {
      return;
    }

    final dir = await _storageRootDirectory();
    final root = Directory(_joinPath([dir.path, assetsDirectoryName, key]));
    if (!await root.exists()) return;
    await root.delete(recursive: true);
  }

  Future<void> cleanupOrphanAssetRoots(Isar isar) async {
    try {
      final books = await isar.books.where().findAll();
      final assets = await isar.bookAssets.where().findAll();
      await deleteOrphanAssetRoots(
        activeRootKeys: <String>{
          for (final book in books)
            if ((book.assetRootKey ?? '').trim().isNotEmpty)
              book.assetRootKey!.trim(),
          for (final asset in assets)
            if (_assetRootKeyFromRelativePath(asset.relativePath) != null)
              _assetRootKeyFromRelativePath(asset.relativePath)!,
        },
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to cleanup orphan book asset roots',
        name: 'BookAssetStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Deletes asset root directories not referenced by [activeRootKeys] —
  /// typically staging roots left behind by a killed import.
  Future<void> deleteOrphanAssetRoots({
    required Set<String> activeRootKeys,
  }) async {
    try {
      final dir = await _storageRootDirectory();
      final assetsRoot = Directory(_joinPath([dir.path, assetsDirectoryName]));
      if (!await assetsRoot.exists()) return;

      await for (final entity in assetsRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final rootKey = _baseName(entity.path);
        if (activeRootKeys.contains(rootKey)) continue;
        await entity.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'BookAssetStore',
        'Failed to cleanup orphan book asset roots',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<String> _safeRelativeSegments(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw const FormatException('Book asset path must be relative');
    }

    final segments = normalized.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(':'),
    )) {
      throw const FormatException('Invalid book asset path segment');
    }
    return segments;
  }

  String? _assetRootKeyFromRelativePath(String relativePath) {
    late final List<String> segments;
    try {
      segments = _safeRelativeSegments(relativePath);
    } on FormatException {
      return null;
    }
    if (segments.length < 2 || segments.first != assetsDirectoryName) {
      return null;
    }
    return segments[1];
  }

  String _baseName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? normalized : parts.last;
  }

  String _joinPath(List<String> segments) {
    return segments.join(Platform.pathSeparator);
  }

  bool _isSafeAssetRootKey(String key) {
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) &&
        key != '.' &&
        key != '..';
  }

  String _relativePathWithinDirectory(String directoryPath, String filePath) {
    final base = Directory(directoryPath).absolute.path;
    final absolute = File(filePath).absolute.path;
    final prefix = base.endsWith(Platform.pathSeparator)
        ? base
        : '$base${Platform.pathSeparator}';
    if (!absolute.startsWith(prefix)) {
      throw const FormatException('Book asset resolved outside storage root');
    }
    return absolute.substring(prefix.length);
  }
}
