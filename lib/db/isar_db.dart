import 'dart:async';

import 'package:isar/isar.dart';

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../services/book_asset_store.dart';
import '../storage/storage_layout.dart';

class IsarDb {
  IsarDb({StorageLayoutProvider? storageLayout, BookAssetStore? assetStore})
    : _storageLayout = storageLayout ?? AppStorageResolver.activeRuntimeLayout,
      _assetStore = assetStore;

  static final IsarDb instance = IsarDb();

  final StorageLayoutProvider _storageLayout;
  final BookAssetStore? _assetStore;
  Isar? _isar;

  Future<Isar> get isar async {
    final existing = _isar;
    if (existing != null && existing.isOpen) return existing;

    final layout = await _storageLayout();
    if (!layout.usesLegacyRuntimeLocations) {
      // The forced-Isar rollback path resets the active layout to legacy
      // before reaching this getter. Opening Isar inside the new (target)
      // data directory would silently create an empty `default.isar` there,
      // so refuse loudly instead.
      throw StateError(
        '禁止在新数据目录打开 Isar：active 布局不是 legacy 运行时位置 '
        '(${layout.libraryDatabaseDirectory.path})',
      );
    }
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

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
