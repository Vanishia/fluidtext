import 'dart:async';

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../services/book_asset_store.dart';
import '../storage/storage_layout.dart';

class IsarDb {
  IsarDb({StorageLayoutProvider? storageLayout, BookAssetStore? assetStore})
    : _storageLayout = storageLayout ?? AppStorageResolver.legacyRuntimeLayout,
      _assetStore = assetStore;

  static final IsarDb instance = IsarDb();

  final StorageLayoutProvider _storageLayout;
  final BookAssetStore? _assetStore;
  Isar? _isar;

  Future<Isar> get isar async {
    final existing = _isar;
    if (existing != null) return existing;

    final layout = await _storageLayout();
    final opened = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: layout.libraryDatabaseDirectory.path,
      inspector: true,
    );
    unawaited(
      (_assetStore ?? BookAssetStore(storageLayout: _storageLayout))
          .cleanupOrphanAssetRoots(opened),
    );
    _isar = opened;
    return opened;
  }
}
