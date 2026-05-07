import 'dart:developer' as developer;
import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';
import '../models/book_asset.dart';

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
  BookAssetStore._();

  static final instance = BookAssetStore._();
  static const assetsDirectoryName = 'book_assets';

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
      final relativePath = relativeImagePath(
        assetRootKey: assetRootKey,
        assetKey: asset.assetKey,
        extension: asset.extension,
      );
      final file = await resolveRelativeFile(relativePath);
      await file.parent.create(recursive: true);
      if (await file.exists()) continue;
      await file.writeAsBytes(asset.bytes, flush: true);
    }
  }

  Future<File> resolveRelativeFile(String relativePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final segments = _safeRelativeSegments(relativePath);
    return File(_joinPath([dir.path, ...segments]));
  }

  Future<void> deleteAssetRoot(String? assetRootKey) async {
    final key = assetRootKey?.trim();
    if (key == null || key.isEmpty || key.contains('/') || key.contains(r'\')) {
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(_joinPath([dir.path, assetsDirectoryName, key]));
    if (!await root.exists()) return;
    await root.delete(recursive: true);
  }

  Future<void> cleanupOrphanAssetRoots(Isar isar) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final assetsRoot = Directory(_joinPath([dir.path, assetsDirectoryName]));
      if (!await assetsRoot.exists()) return;

      final books = await isar.books.where().findAll();
      final assets = await isar.bookAssets.where().findAll();
      final activeRoots = <String>{
        for (final book in books)
          if ((book.assetRootKey ?? '').trim().isNotEmpty)
            book.assetRootKey!.trim(),
        for (final asset in assets)
          if (_assetRootKeyFromRelativePath(asset.relativePath) != null)
            _assetRootKeyFromRelativePath(asset.relativePath)!,
      };

      await for (final entity in assetsRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final rootKey = _baseName(entity.path);
        if (activeRoots.contains(rootKey)) continue;
        await entity.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to cleanup orphan book asset roots',
        name: 'BookAssetStore',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<String> _safeRelativeSegments(String relativePath) {
    return relativePath
        .replaceAll(r'\', '/')
        .split('/')
        .where((segment) {
          final trimmed = segment.trim();
          return trimmed.isNotEmpty && trimmed != '.' && trimmed != '..';
        })
        .toList(growable: false);
  }

  String? _assetRootKeyFromRelativePath(String relativePath) {
    final segments = _safeRelativeSegments(relativePath);
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
}
