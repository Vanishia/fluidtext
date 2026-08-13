import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;

import '../models/book.dart';
import '../models/book_asset.dart';
import '../models/book_card.dart';
import '../models/book_remark.dart';
import '../storage/json_file_store.dart';
import '../storage/sqlite/library_database.dart';
import '../storage/storage_layout.dart';
import 'legacy_isar_reader.dart';
import 'legacy_source.dart';
import 'migration_progress.dart';
import 'migration_staging.dart';

/// Migration failure carrying the failing [phase] and sanitized diagnostics.
class MigrationException implements Exception {
  const MigrationException({
    required this.phase,
    required this.message,
    this.diagnostic,
  });

  final MigrationPhase phase;

  /// User-facing message (Chinese).
  final String message;

  /// Diagnostic detail with absolute paths replaced by placeholders.
  final String? diagnostic;

  @override
  String toString() =>
      'MigrationException(${phase.name}): $message'
      '${diagnostic == null ? '' : ' — $diagnostic'}';
}

/// Outcome of a successful [LibraryMigrator] run.
class MigrationResult {
  const MigrationResult({
    required this.staging,
    required this.bookCount,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.maxBookId,
    required this.maxCardId,
    required this.maxAssetId,
    required this.cardCountByBook,
    required this.warnings,
    required this.sourceFingerprint,
    required this.copiedResourceHashes,
  });

  /// The staging attempt holding the migrated payload.
  final MigrationStaging staging;

  final int bookCount;
  final int cardCount;
  final int assetCount;
  final int remarkCount;

  /// Largest preserved Isar id per table, null when the table is empty.
  /// Validation compares these against `MAX(id)` in the staging SQLite so
  /// future auto-assigned rowids can never collide with migrated ids.
  final int? maxBookId;
  final int? maxCardId;
  final int? maxAssetId;

  /// Number of migrated cards per book id, used by validation to reconcile
  /// against `GROUP BY book_id` in the staging database.
  final Map<int, int> cardCountByBook;

  /// Non-fatal issues encountered during migration (Chinese, user-facing).
  final List<String> warnings;

  /// Fingerprint of the trusted legacy source, copied from the detection.
  final String? sourceFingerprint;

  /// SHA-256 (hex) of every copied resource file, keyed by the posix path
  /// relative to the payload directory (e.g. `book_assets/x/images/c.png`).
  final Map<String, String> copiedResourceHashes;
}

/// Internal counters collected while writing the staging database.
class _LibraryWriteOutcome {
  _LibraryWriteOutcome({
    required this.bookIds,
    required this.migratedAssetPaths,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.maxCardId,
    required this.maxAssetId,
    required this.cardCountByBook,
  });

  final Set<int> bookIds;
  final List<String> migratedAssetPaths;
  final int cardCount;
  final int assetCount;
  final int remarkCount;
  final int? maxCardId;
  final int? maxAssetId;
  final Map<int, int> cardCountByBook;
}

/// Batch engine for the one-shot legacy Isar → SQLite migration.
///
/// Covers plan steps 5-9: copy legacy databases, stream records into a
/// staging SQLite inside one transaction (preserving Isar ids), copy
/// resource files while hashing them and migrate the settings JSON files
/// with controlled relative paths. Validation, sealing and the atomic
/// promotion are implemented by a later commit.
class LibraryMigrator {
  LibraryMigrator({this.batchSize = 500, MigrationProgressCallback? onProgress})
    : assert(batchSize > 0, 'batchSize must be positive'),
      _onProgress = onProgress;

  /// Batch size for both legacy reads and SQLite inserts.
  final int batchSize;

  final MigrationProgressCallback? _onProgress;

  /// Runs the migration into [staging].
  ///
  /// [detection] must be a trusted probe result for [legacyLayout]. The
  /// legacy layout is never modified. On failure a [MigrationException] is
  /// thrown and the staging directory is left in place for recovery logic.
  Future<MigrationResult> migrate({
    required LegacySourceDetection detection,
    required StorageLayout legacyLayout,
    required MigrationStaging staging,
  }) async {
    if (!detection.isTrusted) {
      throw ArgumentError.value(
        detection.status,
        'detection',
        'migration requires a trusted legacy source',
      );
    }

    final warnings = <String>[];
    _emit(MigrationPhase.copyingDatabase, 0);
    final copyResult = await _guarded(
      MigrationPhase.copyingDatabase,
      () => staging.copyLegacyDatabases(
        legacyLayout: legacyLayout,
        onProgress: (copied, total) =>
            _emit(MigrationPhase.copyingDatabase, copied, total),
      ),
      legacyLayout: legacyLayout,
      staging: staging,
    );

    final reader = LegacyIsarReader(
      stagingRoot: staging.legacyDirectory,
      mainDatabaseCopy: staging.mainDatabaseCopy,
      remarkDatabaseCopy: copyResult.remarkDatabaseCopied
          ? staging.remarkDatabaseCopy
          : null,
      batchSize: batchSize,
    );

    LibraryDatabase? database;
    try {
      await _guarded(
        MigrationPhase.readingBooks,
        reader.open,
        legacyLayout: legacyLayout,
        staging: staging,
      );

      database = LibraryDatabase.file(staging.payloadDatabaseFile);
      final outcome = await _writeLibrary(
        database,
        reader,
        warnings,
        legacyLayout: legacyLayout,
        staging: staging,
      );
      await database.close();
      database = null;

      final copiedHashes = await _guarded(
        MigrationPhase.copyingBookAssets,
        () => _copyResources(legacyLayout, staging, warnings),
        legacyLayout: legacyLayout,
        staging: staging,
      );
      _warnOnMissingAssetFiles(
        outcome.migratedAssetPaths,
        copiedHashes,
        legacyLayout,
        warnings,
      );

      await _guarded(
        MigrationPhase.migratingSettings,
        () => _migrateSettings(legacyLayout, staging, outcome.bookIds, warnings),
        legacyLayout: legacyLayout,
        staging: staging,
      );

      return MigrationResult(
        staging: staging,
        bookCount: outcome.bookIds.length,
        cardCount: outcome.cardCount,
        assetCount: outcome.assetCount,
        remarkCount: outcome.remarkCount,
        maxBookId: outcome.bookIds.isEmpty
            ? null
            : outcome.bookIds.reduce((a, b) => a > b ? a : b),
        maxCardId: outcome.maxCardId,
        maxAssetId: outcome.maxAssetId,
        cardCountByBook: Map.unmodifiable(outcome.cardCountByBook),
        warnings: List.unmodifiable(warnings),
        sourceFingerprint: detection.sourceFingerprint,
        copiedResourceHashes: Map.unmodifiable(copiedHashes),
      );
    } finally {
      await reader.close();
      await database?.close();
    }
  }

  /// Reads all legacy collections and writes them into the staging SQLite
  /// inside a single transaction, preserving Isar ids.
  Future<_LibraryWriteOutcome> _writeLibrary(
    LibraryDatabase database,
    LegacyIsarReader reader,
    List<String> warnings, {
    required StorageLayout legacyLayout,
    required MigrationStaging staging,
  }) async {
    final totalBooks = await reader.countBooks();
    final totalCards = await reader.countBookCards();
    final totalAssets = await reader.countBookAssets();
    final totalRemarks = await reader.countBookRemarks();

    final bookIds = <int>{};
    final cardIds = <int>{};
    final assetIds = <int>{};
    final remarkIds = <int>{};
    final migratedAssetPaths = <String>[];
    final cardCountByBook = <int, int>{};
    var cardCount = 0;
    var assetCount = 0;
    var remarkCount = 0;
    int? maxCardId;
    int? maxAssetId;
    var phase = MigrationPhase.readingBooks;
    try {
      await database.transaction(() async {
        _emit(MigrationPhase.readingBooks, 0, totalBooks);
        await for (final batch in reader.readBooks()) {
          for (final book in batch) {
            _requireValidId(book.id, MigrationPhase.readingBooks, '书籍');
            if (!bookIds.add(book.id)) {
              throw MigrationException(
                phase: MigrationPhase.readingBooks,
                message: '旧书库中存在重复的书籍 ID，已停止迁移',
                diagnostic: 'duplicate book id=${book.id}',
              );
            }
          }
          await database.batch(
            (b) => b.insertAll(database.sqliteBooks, [
              for (final book in batch) _bookCompanion(book),
            ]),
          );
          _emit(MigrationPhase.readingBooks, bookIds.length, totalBooks);
        }

        phase = MigrationPhase.migratingCards;
        (cardCount, maxCardId) = await _insertCards(
          database,
          reader,
          bookIds,
          cardIds,
          totalCards,
          cardCountByBook,
          warnings,
        );

        phase = MigrationPhase.migratingRemarksAndAssets;
        (assetCount, maxAssetId) = await _insertAssets(
          database,
          reader,
          bookIds,
          assetIds,
          totalAssets,
          totalRemarks,
          migratedAssetPaths,
          warnings,
        );
        remarkCount = await _insertRemarks(
          database,
          reader,
          bookIds,
          remarkIds,
          totalAssets,
          totalRemarks,
          warnings,
        );
      });
    } on MigrationException {
      rethrow;
    } catch (error) {
      throw MigrationException(
        phase: phase,
        message: '写入迁移数据库失败',
        diagnostic: _sanitize(error, legacyLayout, staging),
      );
    }
    return _LibraryWriteOutcome(
      bookIds: bookIds,
      migratedAssetPaths: migratedAssetPaths,
      cardCount: cardCount,
      assetCount: assetCount,
      remarkCount: remarkCount,
      maxCardId: maxCardId,
      maxAssetId: maxAssetId,
      cardCountByBook: cardCountByBook,
    );
  }

  Future<(int, int?)> _insertCards(
    LibraryDatabase database,
    LegacyIsarReader reader,
    Set<int> bookIds,
    Set<int> cardIds,
    int totalCards,
    Map<int, int> cardCountByBook,
    List<String> warnings,
  ) async {
    final cardKeys = <String>{};
    var normalizedTimestamps = 0;
    var missingChapterInfo = 0;
    var completed = 0;
    int? maxId;
    _emit(MigrationPhase.migratingCards, 0, totalCards);
    await for (final batch in reader.readBookCards()) {
      for (final card in batch) {
        _requireValidId(card.id, MigrationPhase.migratingCards, '卡片');
        if (card.chapterIndex == _unsetIntSentinel ||
            card.chapterCardIndex == _unsetIntSentinel) {
          missingChapterInfo++;
        }
        if (!cardIds.add(card.id)) {
          throw MigrationException(
            phase: MigrationPhase.migratingCards,
            message: '旧书库中存在重复的卡片 ID，已停止迁移',
            diagnostic: 'duplicate card id=${card.id}',
          );
        }
        if (!bookIds.contains(card.bookId)) {
          throw MigrationException(
            phase: MigrationPhase.migratingCards,
            message: '旧书库中存在指向缺失书籍的卡片，已停止迁移',
            diagnostic: 'card id=${card.id} references bookId=${card.bookId}',
          );
        }
        // (bookId, cardIndex) is unique in SQLite; a duplicate would change
        // the card order silently, so stop instead.
        final cardKey = '${card.bookId}:${card.cardIndex}';
        if (!cardKeys.add(cardKey)) {
          throw MigrationException(
            phase: MigrationPhase.migratingCards,
            message: '旧书库中存在重复的卡片序号，已停止迁移',
            diagnostic:
                'duplicate (bookId=${card.bookId}, cardIndex=${card.cardIndex})',
          );
        }
        if ((!card.isRead && card.readAt != null) ||
            (!card.isFavorite && card.favoritedAt != null)) {
          normalizedTimestamps++;
        }
        cardCountByBook[card.bookId] = (cardCountByBook[card.bookId] ?? 0) + 1;
        if (maxId == null || card.id > maxId) maxId = card.id;
      }
      await database.batch(
        (b) => b.insertAll(database.sqliteBookCards, [
          for (final card in batch) _cardCompanion(card),
        ]),
      );
      completed += batch.length;
      _emit(MigrationPhase.migratingCards, completed, totalCards);
    }
    if (normalizedTimestamps > 0) {
      warnings.add(
        '部分卡片的阅读/收藏时间与其状态不一致，已按状态修正（$normalizedTimestamps 条）',
      );
    }
    if (missingChapterInfo > 0) {
      warnings.add(
        '部分早期导入的卡片缺少章节信息，已按第 0 章处理（$missingChapterInfo 张）',
      );
    }
    return (completed, maxId);
  }

  Future<(int, int?)> _insertAssets(
    LibraryDatabase database,
    LegacyIsarReader reader,
    Set<int> bookIds,
    Set<int> assetIds,
    int totalAssets,
    int totalRemarks,
    List<String> migratedAssetPaths,
    List<String> warnings,
  ) async {
    var kept = 0;
    var skippedOrphans = 0;
    var completed = 0;
    int? maxId;
    _emit(
      MigrationPhase.migratingRemarksAndAssets,
      0,
      totalAssets + totalRemarks,
    );
    await for (final batch in reader.readBookAssets()) {
      final insertable = <BookAsset>[];
      for (final asset in batch) {
        _requireValidId(
          asset.id,
          MigrationPhase.migratingRemarksAndAssets,
          '资源',
        );
        if (!assetIds.add(asset.id)) {
          throw MigrationException(
            phase: MigrationPhase.migratingRemarksAndAssets,
            message: '旧书库中存在重复的资源 ID，已停止迁移',
            diagnostic: 'duplicate asset id=${asset.id}',
          );
        }
        if (!bookIds.contains(asset.bookId)) {
          // Orphan asset metadata must not block the text migration.
          skippedOrphans++;
          continue;
        }
        insertable.add(asset);
        migratedAssetPaths.add(asset.relativePath);
        if (maxId == null || asset.id > maxId) maxId = asset.id;
        kept++;
      }
      if (insertable.isNotEmpty) {
        await database.batch(
          (b) => b.insertAll(database.sqliteBookAssets, [
            for (final asset in insertable) _assetCompanion(asset),
          ]),
        );
      }
      completed += batch.length;
      _emit(
        MigrationPhase.migratingRemarksAndAssets,
        completed,
        totalAssets + totalRemarks,
      );
    }
    if (skippedOrphans > 0) {
      warnings.add('跳过 $skippedOrphans 条指向缺失书籍的资源记录');
    }
    return (kept, maxId);
  }

  Future<int> _insertRemarks(
    LibraryDatabase database,
    LegacyIsarReader reader,
    Set<int> bookIds,
    Set<int> remarkIds,
    int totalAssets,
    int totalRemarks,
    List<String> warnings,
  ) async {
    var kept = 0;
    var skippedOrphans = 0;
    var completed = 0;
    await for (final batch in reader.readBookRemarks()) {
      final insertable = <BookRemark>[];
      for (final remark in batch) {
        _requireValidId(
          remark.id,
          MigrationPhase.migratingRemarksAndAssets,
          '备注',
        );
        if (!remarkIds.add(remark.id)) {
          throw MigrationException(
            phase: MigrationPhase.migratingRemarksAndAssets,
            message: '旧备注库中存在重复的备注 ID，已停止迁移',
            diagnostic: 'duplicate remark id=${remark.id}',
          );
        }
        if (!bookIds.contains(remark.id)) {
          skippedOrphans++;
          continue;
        }
        insertable.add(remark);
        kept++;
      }
      if (insertable.isNotEmpty) {
        await database.batch(
          (b) => b.insertAll(database.sqliteBookRemarks, [
            for (final remark in insertable)
              SqliteBookRemarksCompanion.insert(
                bookId: Value(remark.id),
                title: remark.title,
                updatedAtMs: remark.updatedAt.millisecondsSinceEpoch,
              ),
          ]),
        );
      }
      completed += batch.length;
      _emit(
        MigrationPhase.migratingRemarksAndAssets,
        totalAssets + completed,
        totalAssets + totalRemarks,
      );
    }
    if (skippedOrphans > 0) {
      warnings.add('跳过 $skippedOrphans 条指向缺失书籍的备注');
    }
    return kept;
  }

  /// Copies book_assets/, reader_backgrounds/ and app_fonts/ into the
  /// payload mirror while computing a SHA-256 per file.
  Future<Map<String, String>> _copyResources(
    StorageLayout legacyLayout,
    MigrationStaging staging,
    List<String> warnings,
  ) async {
    final separator = legacyLayout.pathSeparator;
    final pairs = <(String, Directory)>[
      (StorageLayout.bookAssetsDirectoryName, legacyLayout.bookAssetsDirectory),
      (
        StorageLayout.readerBackgroundsDirectoryName,
        legacyLayout.readerBackgroundsDirectory,
      ),
      (StorageLayout.appFontsDirectoryName, legacyLayout.appFontsDirectory),
    ];

    // Manifest first: regular files only, links are skipped with a warning.
    final files = <(String, File, Directory)>[];
    var totalBytes = 0;
    for (final (dirName, sourceDir) in pairs) {
      if (!await sourceDir.exists()) continue;
      await for (final entity in sourceDir.list(
        recursive: true,
        followLinks: false,
      )) {
        // Symlinks/junctions surface as Link (or as File on some file
        // systems); never follow them.
        if (entity is Link) {
          warnings.add('跳过符号链接资源：$dirName/${_basename(entity.path)}');
          continue;
        }
        if (entity is! File) continue;
        if (await StoragePathSafety.isLink(entity)) {
          warnings.add('跳过符号链接资源：$dirName/${_basename(entity.path)}');
          continue;
        }
        totalBytes += await entity.length();
        files.add((dirName, entity, sourceDir));
      }
    }

    final hashes = <String, String>{};
    var copiedBytes = 0;
    _emit(MigrationPhase.copyingBookAssets, 0, totalBytes);
    for (final (dirName, source, sourceDir) in files) {
      final relative = _relativePosixPath(sourceDir, source);
      final target = File(
        StorageLayout.joinPath([
          staging.payloadDirectory.path,
          dirName,
          ...relative.split('/'),
        ], separator: separator),
      );
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      final digest = _DigestCollector();
      final digestSink = sha256.startChunkedConversion(digest);
      final output = target.openWrite();
      try {
        await for (final chunk in source.openRead()) {
          output.add(chunk);
          digestSink.add(chunk);
          copiedBytes += chunk.length;
          _emit(MigrationPhase.copyingBookAssets, copiedBytes, totalBytes);
        }
        await output.flush();
      } finally {
        await output.close();
        digestSink.close();
      }
      hashes['$dirName/$relative'] = digest.value.toString();
    }
    return hashes;
  }

  /// Warns when a migrated asset record has no corresponding copied file.
  void _warnOnMissingAssetFiles(
    List<String> migratedAssetPaths,
    Map<String, String> copiedHashes,
    StorageLayout legacyLayout,
    List<String> warnings,
  ) {
    for (final relativePath in migratedAssetPaths) {
      final posix = relativePath.replaceAll(r'\', '/');
      if (copiedHashes.containsKey(posix)) continue;
      try {
        final source = StoragePathSafety.resolveRelativeFile(
          rootDirectory: legacyLayout.rootDirectory,
          relativePath: relativePath,
          label: 'book asset path',
          separator: legacyLayout.pathSeparator,
        );
        if (source.existsSync()) {
          warnings.add('书籍图片未被复制（可能是不支持的文件类型）：$posix');
        } else {
          warnings.add('书籍图片文件缺失，已保留资源记录：$posix');
        }
      } on FormatException {
        warnings.add('书籍图片资源路径无效，已保留资源记录：$posix');
      }
    }
  }

  /// Migrates the four settings JSON files into payload/settings/.
  Future<void> _migrateSettings(
    StorageLayout legacyLayout,
    MigrationStaging staging,
    Set<int> migratedBookIds,
    List<String> warnings,
  ) async {
    var completed = 0;
    const total = 4;
    _emit(MigrationPhase.migratingSettings, completed, total);

    await _migrateBehaviorSettings(legacyLayout, staging);
    _emit(MigrationPhase.migratingSettings, ++completed, total);
    await _migrateReaderSession(legacyLayout, staging, migratedBookIds, warnings);
    _emit(MigrationPhase.migratingSettings, ++completed, total);
    await _migrateBackgroundSettings(legacyLayout, staging, warnings);
    _emit(MigrationPhase.migratingSettings, ++completed, total);
    await _migrateFontSettings(legacyLayout, staging, warnings);
    _emit(MigrationPhase.migratingSettings, ++completed, total);
  }

  Future<void> _migrateBehaviorSettings(
    StorageLayout legacyLayout,
    MigrationStaging staging,
  ) async {
    final source = legacyLayout.appBehaviorSettingsFile;
    if (!await source.exists()) return;
    // Copied verbatim: the behavior settings loader tolerates bad content.
    await JsonFileStore.writeAtomicString(
      _payloadSettingsFile(
        staging,
        StorageLayout.appBehaviorSettingsFileName,
        legacyLayout.pathSeparator,
      ),
      await source.readAsString(),
    );
  }

  Future<void> _migrateReaderSession(
    StorageLayout legacyLayout,
    MigrationStaging staging,
    Set<int> migratedBookIds,
    List<String> warnings,
  ) async {
    final source = legacyLayout.readerSessionFile;
    if (!await source.exists()) return;
    final target = _payloadSettingsFile(
      staging,
      StorageLayout.readerSessionFileName,
      legacyLayout.pathSeparator,
    );
    final decoded = await _tryDecodeJson(source);
    if (decoded == null) {
      warnings.add('阅读记录文件已损坏，已重置为默认值');
      await JsonFileStore.writeAtomic(target, const <String, Object?>{
        'lastOpenedBookIds': <int>[],
      });
      return;
    }
    final ids = decoded['lastOpenedBookIds'];
    final filtered = <int>[
      if (ids is List)
        for (final value in ids.whereType<num>())
          if (migratedBookIds.contains(value.toInt())) value.toInt(),
    ];
    await JsonFileStore.writeAtomic(target, <String, Object?>{
      ...decoded,
      'lastOpenedBookIds': filtered,
    });
  }

  Future<void> _migrateBackgroundSettings(
    StorageLayout legacyLayout,
    MigrationStaging staging,
    List<String> warnings,
  ) async {
    final source = legacyLayout.readerBackgroundSettingsFile;
    if (!await source.exists()) return;
    final target = _payloadSettingsFile(
      staging,
      StorageLayout.readerBackgroundSettingsFileName,
      legacyLayout.pathSeparator,
    );
    final decoded = await _tryDecodeJson(source);
    if (decoded == null) {
      warnings.add('阅读背景设置已损坏，已重置为默认值');
      await JsonFileStore.writeAtomic(target, const <String, Object?>{
        'source': 'color',
        'paletteKey': 'warmPaper',
        'texture': 'none',
        'imagePath': null,
      });
      return;
    }

    if (decoded['source'] != 'image') {
      await JsonFileStore.writeAtomic(target, decoded);
      return;
    }
    final rewritten = await _rewriteManagedPath(
      decoded['imagePath'],
      managedDirectoryName: StorageLayout.readerBackgroundsDirectoryName,
      managedDirectory: legacyLayout.readerBackgroundsDirectory,
      legacyLayout: legacyLayout,
      staging: staging,
      pathLabel: 'imagePath',
    );
    if (rewritten == null) {
      warnings.add('阅读背景图片缺失或不在受管目录内，已回退为纯色背景');
      await JsonFileStore.writeAtomic(target, <String, Object?>{
        ...decoded,
        'source': 'color',
        'imagePath': null,
      });
      return;
    }
    await JsonFileStore.writeAtomic(target, <String, Object?>{
      ...decoded,
      'imagePath': rewritten,
    });
  }

  Future<void> _migrateFontSettings(
    StorageLayout legacyLayout,
    MigrationStaging staging,
    List<String> warnings,
  ) async {
    final source = legacyLayout.appFontSettingsFile;
    if (!await source.exists()) return;
    final target = _payloadSettingsFile(
      staging,
      StorageLayout.appFontSettingsFileName,
      legacyLayout.pathSeparator,
    );
    final decoded = await _tryDecodeJson(source);
    if (decoded == null) {
      warnings.add('字体设置已损坏，已重置为系统字体');
      await JsonFileStore.writeAtomic(target, const <String, Object?>{
        'source': 'system',
        'fontFamily': null,
        'displayName': null,
        'fontPath': null,
      });
      return;
    }

    if (decoded['source'] != 'custom') {
      await JsonFileStore.writeAtomic(target, decoded);
      return;
    }
    final rewritten = await _rewriteManagedPath(
      decoded['fontPath'],
      managedDirectoryName: StorageLayout.appFontsDirectoryName,
      managedDirectory: legacyLayout.appFontsDirectory,
      legacyLayout: legacyLayout,
      staging: staging,
      pathLabel: 'fontPath',
    );
    if (rewritten == null) {
      warnings.add('自定义字体文件缺失或不在受管目录内，已回退为系统字体');
      await JsonFileStore.writeAtomic(target, const <String, Object?>{
        'source': 'system',
        'fontFamily': null,
        'displayName': null,
        'fontPath': null,
      });
      return;
    }
    await JsonFileStore.writeAtomic(target, <String, Object?>{
      ...decoded,
      'fontPath': rewritten,
    });
  }

  /// Rewrites an absolute (or already relative) managed file path to the
  /// controlled relative form `<managedDirName>/<name>`. Returns null when
  /// the referenced file is missing, unsafe, outside the legacy managed
  /// directory or was not copied into the payload mirror.
  Future<String?> _rewriteManagedPath(
    Object? rawPath, {
    required String managedDirectoryName,
    required Directory managedDirectory,
    required StorageLayout legacyLayout,
    required MigrationStaging staging,
    required String pathLabel,
  }) async {
    if (rawPath is! String || rawPath.isEmpty) return null;

    File candidate;
    String managedRelative;
    if (StoragePathSafety.isAbsolutePath(rawPath)) {
      candidate = File(rawPath);
      if (!StoragePathSafety.isLexicallyWithinDirectory(
        directoryPath: managedDirectory.path,
        filePath: candidate.path,
      )) {
        return null;
      }
      managedRelative = _relativePosixPath(managedDirectory, candidate);
    } else {
      try {
        final safe = StoragePathSafety.parseRelativePath(
          rawPath,
          label: pathLabel,
        );
        if (safe.segments.length < 2 ||
            safe.segments.first != managedDirectoryName) {
          return null;
        }
        managedRelative = safe.segments.sublist(1).join('/');
        candidate = File(
          StorageLayout.joinPath([
            managedDirectory.path,
            ...safe.segments.sublist(1),
          ], separator: legacyLayout.pathSeparator),
        );
      } on FormatException {
        return null;
      }
    }

    if (!await candidate.exists()) return null;
    // The file must have been copied into the payload mirror.
    final payloadFile = File(
      StorageLayout.joinPath([
        staging.payloadDirectory.path,
        managedDirectoryName,
        ...managedRelative.split('/'),
      ], separator: legacyLayout.pathSeparator),
    );
    if (!await payloadFile.exists()) return null;
    return '$managedDirectoryName/$managedRelative';
  }

  Future<Map<String, dynamic>?> _tryDecodeJson(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  File _payloadSettingsFile(
    MigrationStaging staging,
    String fileName,
    String separator,
  ) {
    return File(
      StorageLayout.joinPath([
        staging.payloadSettingsDirectory.path,
        fileName,
      ], separator: separator),
    );
  }

  void _requireValidId(int id, MigrationPhase phase, String label) {
    if (id <= 0) {
      throw MigrationException(
        phase: phase,
        message: '旧书库中存在无效的$label ID，已停止迁移',
        diagnostic: 'invalid id=$id',
      );
    }
  }

  Future<T> _guarded<T>(
    MigrationPhase phase,
    Future<T> Function() action, {
    required StorageLayout legacyLayout,
    required MigrationStaging staging,
  }) async {
    try {
      return await action();
    } on MigrationException {
      rethrow;
    } catch (error) {
      throw MigrationException(
        phase: phase,
        message: switch (phase) {
          MigrationPhase.copyingDatabase => '复制旧数据库失败',
          MigrationPhase.readingBooks => '读取旧数据库失败',
          MigrationPhase.copyingBookAssets => '复制资源文件失败',
          MigrationPhase.migratingSettings => '迁移设置失败',
          _ => '迁移失败',
        },
        diagnostic: _sanitize(error, legacyLayout, staging),
      );
    }
  }

  String _sanitize(
    Object error,
    StorageLayout legacyLayout,
    MigrationStaging staging,
  ) {
    var text = error.toString();
    // SqliteException.toString() appends the causing SQL statement and its
    // bound parameters, which can contain card content or book titles. The
    // plan forbids book content in diagnostics, so strip that section.
    for (final marker in const ['Causing statement', 'parameters:']) {
      final cutoff = text.indexOf(marker);
      if (cutoff != -1) {
        text = text.substring(0, cutoff).trimRight();
      }
    }
    final replacements = <String, String>{
      staging.attemptDirectory.path: '<staging>',
      legacyLayout.rootDirectory.path: '<legacy>',
      legacyLayout.appFontSettingsFile.parent.path: '<legacySupport>',
    };
    final keys = replacements.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (key.isNotEmpty) text = text.replaceAll(key, replacements[key]!);
    }
    return text;
  }

  void _emit(MigrationPhase phase, int completed, [int? total]) {
    _onProgress?.call(
      MigrationProgressEvent(phase: phase, completed: completed, total: total),
    );
  }

  static SqliteBooksCompanion _bookCompanion(Book book) {
    return SqliteBooksCompanion.insert(
      id: Value(book.id),
      title: book.title,
      createdAtMs: book.createdAt.millisecondsSinceEpoch,
      fileHash: Value(book.fileHash),
      contentFingerprint: Value(book.contentFingerprint),
      sourceFileName: Value(book.sourceFileName),
      importedAtMs: Value(book.importedAt?.millisecondsSinceEpoch),
      cardCount: Value(book.cardCount),
      textCharCount: Value(book.textCharCount),
      assetRootKey: Value(book.assetRootKey),
    );
  }

  static const _unsetIntSentinel = -9223372036854775808;

  static SqliteBookCardsCompanion _cardCompanion(BookCard card) {
    return SqliteBookCardsCompanion.insert(
      id: Value(card.id),
      bookId: card.bookId,
      bookTitle: card.bookTitle,
      cardIndex: card.cardIndex,
      // Cards imported before chapter metadata existed read back as Isar's
      // "unset" sentinel (int64 min); normalize them to chapter 0.
      chapterIndex: card.chapterIndex == _unsetIntSentinel
          ? 0
          : card.chapterIndex,
      chapterCardIndex: card.chapterCardIndex == _unsetIntSentinel
          ? 0
          : card.chapterCardIndex,
      chapterTitle: Value(card.chapterTitle),
      content: card.content,
      blocksJson: Value(card.blocksJson),
      isRead: card.isRead,
      // Normalize to the SQLite CHECK: timestamps only when flagged.
      readAtMs: Value(
        card.isRead ? card.readAt?.millisecondsSinceEpoch : null,
      ),
      isFavorite: card.isFavorite,
      favoritedAtMs: Value(
        card.isFavorite ? card.favoritedAt?.millisecondsSinceEpoch : null,
      ),
    );
  }

  static SqliteBookAssetsCompanion _assetCompanion(BookAsset asset) {
    return SqliteBookAssetsCompanion.insert(
      id: Value(asset.id),
      bookId: asset.bookId,
      assetKey: asset.assetKey,
      originalHref: Value(asset.originalHref),
      normalizedHref: Value(asset.normalizedHref),
      mimeType: Value(asset.mimeType),
      relativePath: asset.relativePath,
      byteLength: Value(asset.byteLength),
      createdAtMs: asset.createdAt.millisecondsSinceEpoch,
    );
  }

  static String _relativePosixPath(Directory root, File file) {
    final rootPath = root.path.replaceAll(r'\', '/');
    var filePath = file.path.replaceAll(r'\', '/');
    if (filePath.startsWith('$rootPath/')) {
      filePath = filePath.substring(rootPath.length + 1);
    }
    return filePath;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}

/// Collects the single digest emitted by a chunked hash conversion.
class _DigestCollector implements Sink<Digest> {
  Digest value = sha256.convert(const <int>[]);

  @override
  void add(Digest event) => value = event;

  @override
  void close() {}
}
