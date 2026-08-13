import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../migration/migration_promotion.dart';
import '../../storage/json_file_store.dart';
import '../../storage/sqlite/library_database.dart';
import '../../storage/sqlite/sqlite_sealer.dart';
import '../../storage/storage_layout.dart';
import 'backup_format.dart';
import 'zip_security.dart';

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.formatVersion,
    required this.bookCount,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.settingsIncluded,
    required this.warnings,
  });

  final int formatVersion;
  final int bookCount;
  final int cardCount;
  final int assetCount;
  final int remarkCount;
  final bool settingsIncluded;
  final List<String> warnings;
}

class _ValidatedLibrary {
  _ValidatedLibrary({
    required this.books,
    required this.cards,
    required this.assets,
    required this.remarks,
  });

  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> cards;
  final List<Map<String, dynamic>> assets;
  final List<Map<String, dynamic>> remarks;

  Set<int> get bookIds => books.map((book) => book['id'] as int).toSet();
}

/// Restores v2 (`.json` or `.zip`) and v3 (`.zip`) backups with atomic
/// whole-library replacement semantics (plan 7.4): stage everything under
/// `recovery/attempts/<id>/`, seal the staging database, then swap the live
/// entries with the staged payload via same-volume renames.
class BackupRestoreService {
  const BackupRestoreService();

  static const _managedEntryNames = <String>[
    StorageLayout.sqliteDatabaseFileName,
    'settings',
    StorageLayout.bookAssetsDirectoryName,
    StorageLayout.readerBackgroundsDirectoryName,
    StorageLayout.appFontsDirectoryName,
  ];

  Future<BackupRestoreResult> restore({
    required File backupFile,
    required StorageLayout targetLayout,
    required Future<void> Function() closeLiveDatabase,
  }) async {
    if (!await backupFile.exists()) {
      throw const FormatException('备份文件不存在');
    }
    final warnings = <String>[];

    // 1. Detect the payload kind by extension and magic bytes.
    final attemptId = 'restore-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final attemptDirectory = Directory(
      StorageLayout.joinPath([
        targetLayout.recoveryDirectory.path,
        'attempts',
        attemptId,
      ], separator: targetLayout.pathSeparator),
    );
    await attemptDirectory.create(recursive: true);

    var succeeded = false;
    try {
      final result = await _restoreInto(
        backupFile,
        targetLayout,
        attemptDirectory,
        closeLiveDatabase,
        warnings,
      );
      succeeded = true;
      return result;
    } finally {
      if (succeeded) {
        // previous/ is kept until this final cleanup so a crash mid-swap
        // still has the original data next to the root.
        if (await attemptDirectory.exists()) {
          await attemptDirectory.delete(recursive: true);
        }
      }
      // On failure the attempt directory is kept for diagnostics.
    }
  }

  Future<BackupRestoreResult> _restoreInto(
    File backupFile,
    StorageLayout targetLayout,
    Directory attemptDirectory,
    Future<void> Function() closeLiveDatabase,
    List<String> warnings,
  ) async {
    final extension = _extensionOf(backupFile.path);
    final extractedDirectory = Directory(
      StorageLayout.joinPath([
        attemptDirectory.path,
        'extracted',
      ], separator: targetLayout.pathSeparator),
    );

    BackupLibraryData data;
    int formatVersion;
    List<ExtractedEntry>? extractedEntries;

    if (extension == 'json') {
      data = parseV2Payload(_decodeJsonObject(await backupFile.readAsBytes()));
      formatVersion = 2;
    } else if (extension == 'zip') {
      await _assertZipMagic(backupFile);
      extractedEntries = await ZipSecurity.extractToDisk(
        backupFile,
        extractedDirectory,
      );
      final paths = extractedEntries.map((entry) => entry.relativePath).toSet();
      if (paths.contains('manifest.json')) {
        formatVersion = 3;
        final manifest = BackupManifest.fromJson(
          _decodeJsonObject(
            await _extractedFile(extractedDirectory, 'manifest.json')
                .readAsBytes(),
          ),
        );
        if (!paths.contains('data/library.json')) {
          throw const FormatException('v3 备份缺少 data/library.json');
        }
        data = parseLibraryJson(
          _decodeJsonObject(
            await _extractedFile(
              extractedDirectory,
              'data/library.json',
            ).readAsBytes(),
          ),
        );
        _verifyManifest(manifest, data, extractedEntries);
      } else if (paths.contains('backup.json')) {
        formatVersion = 2;
        data = parseV2Payload(
          _decodeJsonObject(
            await _extractedFile(
              extractedDirectory,
              'backup.json',
            ).readAsBytes(),
          ),
        );
      } else {
        throw const FormatException('压缩包中未找到 manifest.json 或 backup.json');
      }
    } else {
      throw const FormatException('不支持的备份文件类型，仅支持 .zip 或 .json');
    }

    // 2. Validate cross-record consistency.
    final library = _validateLibrary(data, warnings);

    // 3. Build and verify the staging database in a single transaction.
    final payloadDirectory = Directory(
      StorageLayout.joinPath([
        attemptDirectory.path,
        'payload',
      ], separator: targetLayout.pathSeparator),
    );
    await payloadDirectory.create(recursive: true);
    final stagingDatabaseFile = File(
      StorageLayout.joinPath([
        payloadDirectory.path,
        StorageLayout.sqliteDatabaseFileName,
      ], separator: targetLayout.pathSeparator),
    );
    await _writeStagingDatabase(stagingDatabaseFile, library);

    // 4. Copy managed files and sanitized settings into the payload.
    final settingsIncluded = await _stageFiles(
      data: data,
      library: library,
      formatVersion: formatVersion,
      extractedDirectory: extractedDirectory,
      payloadDirectory: payloadDirectory,
      validBookIds: library.bookIds,
      warnings: warnings,
      separator: targetLayout.pathSeparator,
    );

    // 5. Seal the staging database (checkpoint + no WAL sidecars).
    await SqliteSealer.seal(stagingDatabaseFile);

    // 6. Close the live database before swapping files underneath it.
    await closeLiveDatabase();

    // 7. Atomically swap live entries with the staged payload.
    await _swapAtomically(
      targetLayout: targetLayout,
      payloadDirectory: payloadDirectory,
      previousDirectory: Directory(
        StorageLayout.joinPath([
          attemptDirectory.path,
          'previous',
        ], separator: targetLayout.pathSeparator),
      ),
    );

    // 8. Keep the migration completion marker's counts current.
    await _refreshCompletionMarker(targetLayout, library);

    return BackupRestoreResult(
      formatVersion: formatVersion,
      bookCount: library.books.length,
      cardCount: library.cards.length,
      assetCount: library.assets.length,
      remarkCount: library.remarks.length,
      settingsIncluded: settingsIncluded,
      warnings: warnings,
    );
  }

  _ValidatedLibrary _validateLibrary(
    BackupLibraryData data,
    List<String> warnings,
  ) {
    final books = <Map<String, dynamic>>[];
    final bookIds = <int>{};
    for (final book in data.books) {
      final id = book['id'] as int;
      if (id <= 0) {
        throw FormatException('书籍记录包含非法 ID：$id');
      }
      if (!bookIds.add(id)) {
        throw FormatException('备份包含重复的书籍 ID：$id');
      }
      books.add(book);
    }

    final cards = <Map<String, dynamic>>[];
    final cardIds = <int>{};
    final cardKeys = <String>{};
    for (final card in data.bookCards) {
      final id = card['id'] as int;
      final bookId = card['bookId'] as int;
      if (id <= 0) {
        throw FormatException('卡片记录包含非法 ID：$id');
      }
      if (!bookIds.contains(bookId)) {
        throw FormatException('卡片（ID $id）引用了不存在的书籍（ID $bookId），备份数据不一致');
      }
      if (!cardIds.add(id)) {
        throw FormatException('备份包含重复的卡片 ID：$id');
      }
      if (!cardKeys.add('$bookId/${card['cardIndex']}')) {
        throw FormatException('备份包含重复的卡片位置（书籍 ID $bookId，序号 ${card['cardIndex']}）');
      }
      // The SQLite CHECK constraints require readAt/favoritedAt to be null
      // when the flag is unset; normalize instead of failing the restore.
      if (card['isRead'] == false && card['readAt'] != null) {
        card['readAt'] = null;
        warnings.add('卡片（ID $id）未读但带有阅读时间，已忽略该时间');
      }
      if (card['isFavorite'] == false && card['favoritedAt'] != null) {
        card['favoritedAt'] = null;
        warnings.add('卡片（ID $id）未收藏但带有收藏时间，已忽略该时间');
      }
      cards.add(card);
    }

    final assets = <Map<String, dynamic>>[];
    final assetIds = <int>{};
    for (final asset in data.bookAssets) {
      final id = asset['id'] as int;
      final bookId = asset['bookId'] as int;
      if (id <= 0) {
        throw FormatException('资源记录包含非法 ID：$id');
      }
      if (!assetIds.add(id)) {
        throw FormatException('备份包含重复的资源 ID：$id');
      }
      if (!bookIds.contains(bookId)) {
        warnings.add('资源记录（ID $id）引用了不存在的书籍（ID $bookId），已跳过');
        continue;
      }
      try {
        StoragePathSafety.parseRelativePath(
          asset['relativePath'] as String,
          label: '资源路径',
        );
      } on FormatException {
        warnings.add('资源记录（ID $id）的路径不安全，已跳过：${asset['relativePath']}');
        continue;
      }
      assets.add(asset);
    }

    final remarks = <Map<String, dynamic>>[];
    final remarkIds = <int>{};
    for (final remark in data.bookRemarks) {
      final id = remark['id'] as int;
      if (id <= 0) {
        throw FormatException('备注记录包含非法 ID：$id');
      }
      if (!remarkIds.add(id)) {
        throw FormatException('备份包含重复的备注 ID：$id');
      }
      if (!bookIds.contains(id)) {
        warnings.add('备注（书籍 ID $id）引用了不存在的书籍，已跳过');
        continue;
      }
      remarks.add(remark);
    }

    return _ValidatedLibrary(
      books: books,
      cards: cards,
      assets: assets,
      remarks: remarks,
    );
  }

  Future<void> _writeStagingDatabase(
    File databaseFile,
    _ValidatedLibrary library,
  ) async {
    final database = LibraryDatabase.file(databaseFile);
    try {
      await database.transaction(() async {
        await database.batch((batch) {
          batch.insertAll(database.sqliteBooks, [
            for (final book in library.books)
              SqliteBooksCompanion.insert(
                id: Value(book['id'] as int),
                title: book['title'] as String,
                createdAtMs: _timestampMs(book['createdAt']) ??
                    _timestampMs(book['importedAt']) ??
                    0,
                fileHash: Value(book['fileHash'] as String?),
                contentFingerprint: Value(
                  book['contentFingerprint'] as String?,
                ),
                sourceFileName: Value(book['sourceFileName'] as String?),
                importedAtMs: Value(_timestampMs(book['importedAt'])),
                cardCount: Value(book['cardCount'] as int?),
                textCharCount: Value(book['textCharCount'] as int?),
                assetRootKey: Value(book['assetRootKey'] as String?),
              ),
          ]);
          batch.insertAll(database.sqliteBookCards, [
            for (final card in library.cards)
              SqliteBookCardsCompanion.insert(
                id: Value(card['id'] as int),
                bookId: card['bookId'] as int,
                bookTitle: card['bookTitle'] as String,
                cardIndex: card['cardIndex'] as int,
                chapterIndex: card['chapterIndex'] as int,
                chapterCardIndex: card['chapterCardIndex'] as int,
                chapterTitle: Value(card['chapterTitle'] as String?),
                content: card['content'] as String,
                blocksJson: Value(card['blocksJson'] as String?),
                isRead: card['isRead'] as bool,
                readAtMs: Value(_timestampMs(card['readAt'])),
                isFavorite: card['isFavorite'] as bool,
                favoritedAtMs: Value(_timestampMs(card['favoritedAt'])),
              ),
          ]);
          batch.insertAll(database.sqliteBookAssets, [
            for (final asset in library.assets)
              SqliteBookAssetsCompanion.insert(
                id: Value(asset['id'] as int),
                bookId: asset['bookId'] as int,
                assetKey: asset['assetKey'] as String,
                originalHref: Value(asset['originalHref'] as String?),
                normalizedHref: Value(asset['normalizedHref'] as String?),
                mimeType: Value(asset['mimeType'] as String?),
                relativePath: (asset['relativePath'] as String).replaceAll(
                  r'\',
                  '/',
                ),
                byteLength: Value(asset['byteLength'] as int?),
                createdAtMs: _timestampMs(asset['createdAt']) ?? 0,
              ),
          ]);
          batch.insertAll(database.sqliteBookRemarks, [
            for (final remark in library.remarks)
              SqliteBookRemarksCompanion.insert(
                bookId: Value(remark['id'] as int),
                title: remark['title'] as String,
                updatedAtMs: _timestampMs(remark['updatedAt']) ??
                    DateTime.now().millisecondsSinceEpoch,
              ),
          ]);
        });
      });

      await _assertStagingDatabase(database, library);
    } finally {
      await database.close();
    }
  }

  Future<void> _assertStagingDatabase(
    LibraryDatabase database,
    _ValidatedLibrary library,
  ) async {
    Future<int> countOf(String table) async {
      final row = await database
          .customSelect('SELECT COUNT(*) AS count FROM $table')
          .getSingle();
      return row.read<int>('count');
    }

    final expectations = <String, int>{
      'books': library.books.length,
      'book_cards': library.cards.length,
      'book_assets': library.assets.length,
      'book_remarks': library.remarks.length,
    };
    for (final entry in expectations.entries) {
      final actual = await countOf(entry.key);
      if (actual != entry.value) {
        throw StateError('恢复数据校验失败：${entry.key} 数量 ${entry.value} != $actual');
      }
    }
    final integrity = await database.integrityCheck();
    if (integrity.length != 1 || integrity.single != 'ok') {
      throw StateError('恢复数据校验失败：integrity_check = ${integrity.join('; ')}');
    }
    final foreignKeys = await database.foreignKeyCheck();
    if (foreignKeys.isNotEmpty) {
      throw StateError('恢复数据校验失败：存在 ${foreignKeys.length} 条外键违规');
    }
  }

  /// Copies managed resource directories into the payload and writes
  /// sanitized settings. Returns whether any settings file was restored.
  Future<bool> _stageFiles({
    required BackupLibraryData data,
    required _ValidatedLibrary library,
    required int formatVersion,
    required Directory extractedDirectory,
    required Directory payloadDirectory,
    required Set<int> validBookIds,
    required List<String> warnings,
    required String separator,
  }) async {
    var settingsIncluded = false;

    if (formatVersion == 3) {
      // Resource directories are copied verbatim; every file inside already
      // passed the ZIP security and manifest checksum verification.
      for (final name in const [
        StorageLayout.bookAssetsDirectoryName,
        StorageLayout.readerBackgroundsDirectoryName,
        StorageLayout.appFontsDirectoryName,
      ]) {
        final source = Directory(
          StorageLayout.joinPath([
            extractedDirectory.path,
            name,
          ], separator: separator),
        );
        if (!await source.exists()) continue;
        final destination = Directory(
          StorageLayout.joinPath([
            payloadDirectory.path,
            name,
          ], separator: separator),
        );
        await _copyDirectoryRecursively(source, destination, separator);
      }

      final settingsSource = Directory(
        StorageLayout.joinPath([
          extractedDirectory.path,
          'settings',
        ], separator: separator),
      );
      for (final name in const [
        StorageLayout.appBehaviorSettingsFileName,
        StorageLayout.readerSessionFileName,
        StorageLayout.readerBackgroundSettingsFileName,
        StorageLayout.appFontSettingsFileName,
      ]) {
        final file = File(
          StorageLayout.joinPath([
            settingsSource.path,
            name,
          ], separator: separator),
        );
        if (!await file.exists()) continue;
        final Map<String, dynamic> json;
        try {
          json = _decodeJsonObject(await file.readAsBytes());
        } on FormatException {
          warnings.add('设置文件 $name 已损坏，已跳过');
          continue;
        }
        await _writeSanitizedSettings(
          name,
          json,
          payloadDirectory,
          validBookIds,
          warnings,
          separator,
        );
        settingsIncluded = true;
      }
    } else {
      // v2 archives store book asset files at their recorded relativePath.
      if (await extractedDirectory.exists()) {
        for (final asset in library.assets) {
          final relativePath = (asset['relativePath'] as String).replaceAll(
            r'\',
            '/',
          );
          final safePath = StoragePathSafety.parseRelativePath(
            relativePath,
            label: '资源路径',
          );
          final source = File(
            StorageLayout.joinPath([
              extractedDirectory.path,
              safePath.asPosixPath(),
            ], separator: separator),
          );
          if (!await source.exists()) {
            warnings.add('资源文件在备份中缺失：$relativePath');
            continue;
          }
          final destination = File(
            StorageLayout.joinPath([
              payloadDirectory.path,
              safePath.asPlatformPath(separator: separator),
            ], separator: separator),
          );
          await destination.parent.create(recursive: true);
          await source.copy(destination.path);
        }
      }

      warnings.add('旧版备份不含外观设置，已恢复核心书库数据');
      final session = data.readerSession;
      if (session != null) {
        await _writeSanitizedSettings(
          StorageLayout.readerSessionFileName,
          session,
          payloadDirectory,
          validBookIds,
          warnings,
          separator,
        );
        settingsIncluded = true;
      }
    }
    return settingsIncluded;
  }

  Future<void> _writeSanitizedSettings(
    String name,
    Map<String, dynamic> json,
    Directory payloadDirectory,
    Set<int> validBookIds,
    List<String> warnings,
    String separator,
  ) async {
    final sanitized = Map<String, dynamic>.of(json);
    switch (name) {
      case StorageLayout.readerBackgroundSettingsFileName:
        final imagePath = sanitized['imagePath'];
        if (imagePath is String &&
            imagePath.isNotEmpty &&
            StoragePathSafety.isAbsolutePath(imagePath)) {
          sanitized.remove('imagePath');
          warnings.add('阅读背景使用了绝对路径，已回退为默认背景');
        }
      case StorageLayout.appFontSettingsFileName:
        final fontPath = sanitized['fontPath'];
        if (fontPath is String &&
            fontPath.isNotEmpty &&
            StoragePathSafety.isAbsolutePath(fontPath)) {
          sanitized.remove('fontPath');
          warnings.add('自定义字体使用了绝对路径，已回退为系统字体');
        }
      case StorageLayout.readerSessionFileName:
        final ids = sanitized['lastOpenedBookIds'];
        if (ids is List) {
          final filtered = ids
              .whereType<num>()
              .map((value) => value.toInt())
              .where(validBookIds.contains)
              .toList(growable: false);
          if (filtered.length != ids.length) {
            warnings.add('阅读会话引用了不存在的书籍，已清除无效引用');
          }
          sanitized['lastOpenedBookIds'] = filtered;
        }
    }
    await JsonFileStore.writeAtomic(
      File(
        StorageLayout.joinPath([
          payloadDirectory.path,
          'settings',
          name,
        ], separator: separator),
      ),
      sanitized,
    );
  }

  Future<void> _copyDirectoryRecursively(
    Directory source,
    Directory destination,
    String separator,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.replaceAll(r'\', '/').split('/').last;
      final targetPath = StorageLayout.joinPath([
        destination.path,
        name,
      ], separator: separator);
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectoryRecursively(
          entity,
          Directory(targetPath),
          separator,
        );
      }
    }
  }

  /// Replaces the live entries with the staged payload via same-volume
  /// renames; rolls back from `previous/` when any step fails.
  Future<void> _swapAtomically({
    required StorageLayout targetLayout,
    required Directory payloadDirectory,
    required Directory previousDirectory,
  }) async {
    final root = targetLayout.rootDirectory;
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final separator = targetLayout.pathSeparator;

    String join(String base, String name) =>
        StorageLayout.joinPath([base, name], separator: separator);

    Future<void> renameEntry(String from, String to) async {
      final type = await FileSystemEntity.type(from);
      if (type == FileSystemEntityType.directory) {
        await Directory(from).rename(to);
      } else {
        await File(from).rename(to);
      }
    }

    final movedToPrevious = <String>[];
    final movedToRoot = <String>[];
    try {
      for (final name in _managedEntryNames) {
        final live = join(root.path, name);
        if (await FileSystemEntity.type(live) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        final previous = join(previousDirectory.path, name);
        await Directory(previous).parent.create(recursive: true);
        await renameEntry(live, previous);
        movedToPrevious.add(name);
      }
      for (final name in _managedEntryNames) {
        final staged = join(payloadDirectory.path, name);
        if (await FileSystemEntity.type(staged) ==
            FileSystemEntityType.notFound) {
          continue;
        }
        await renameEntry(staged, join(root.path, name));
        movedToRoot.add(name);
      }
    } catch (error) {
      // Roll back: drop staged copies already placed in the root, then move
      // the original entries back.
      for (final name in movedToRoot) {
        final placed = join(root.path, name);
        try {
          final type = await FileSystemEntity.type(placed);
          if (type == FileSystemEntityType.directory) {
            await Directory(placed).delete(recursive: true);
          } else if (type == FileSystemEntityType.file) {
            await File(placed).delete();
          }
        } catch (_) {
          // Best effort; the previous entries are still intact.
        }
      }
      for (final name in movedToPrevious.reversed) {
        try {
          await renameEntry(
            join(previousDirectory.path, name),
            join(root.path, name),
          );
        } catch (_) {
          // Best effort rollback.
        }
      }
      throw StateError('恢复失败，当前书库未受影响：$error');
    }
  }

  Future<void> _refreshCompletionMarker(
    StorageLayout targetLayout,
    _ValidatedLibrary library,
  ) async {
    final existing = await MigrationCompletion.load(targetLayout);
    if (existing == null) return;
    await MigrationCompletion.write(
      targetLayout,
      MigrationCompletionMarker(
        source: existing.source,
        sourceFingerprint: existing.sourceFingerprint,
        sqliteSchemaVersion: LibraryDatabase.currentSchemaVersion,
        bookCount: library.books.length,
        cardCount: library.cards.length,
        assetCount: library.assets.length,
        remarkCount: library.remarks.length,
        verifiedResourceCount: existing.verifiedResourceCount,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _verifyManifest(
    BackupManifest manifest,
    BackupLibraryData data,
    List<ExtractedEntry> extractedEntries,
  ) {
    final counts = manifest.counts;
    if (counts.books != data.books.length ||
        counts.bookCards != data.bookCards.length ||
        counts.bookAssets != data.bookAssets.length ||
        counts.bookRemarks != data.bookRemarks.length) {
      throw const FormatException('备份清单声明的数量与实际数据不一致');
    }

    final extractedByPath = {
      for (final entry in extractedEntries) entry.relativePath: entry,
    };
    final declaredPaths = <String>{};
    for (final file in manifest.files) {
      if (!declaredPaths.add(file.path)) {
        throw FormatException('备份清单包含重复的文件条目：${file.path}');
      }
      final extracted = extractedByPath[file.path];
      if (extracted == null) {
        throw FormatException('备份缺少清单中登记的文件：${file.path}');
      }
      if (extracted.bytes != file.bytes || extracted.sha256 != file.sha256) {
        throw FormatException('备份文件校验和不匹配：${file.path}');
      }
    }
    for (final entry in extractedEntries) {
      if (entry.relativePath == 'manifest.json') continue;
      if (!declaredPaths.contains(entry.relativePath)) {
        throw FormatException('备份包含未在清单中登记的文件：${entry.relativePath}');
      }
    }
  }

  Map<String, dynamic> _decodeJsonObject(List<int> bytes) {
    var text = utf8.decode(bytes);
    if (text.startsWith('﻿')) text = text.substring(1);
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份内容不是有效的 JSON 对象');
    }
    return decoded;
  }

  File _extractedFile(Directory extractedDirectory, String relativePath) {
    final safePath = StoragePathSafety.parseRelativePath(
      relativePath,
      label: '备份内部路径',
    );
    return File(
      StorageLayout.joinPath([
        extractedDirectory.path,
        safePath.asPosixPath(),
      ], separator: Platform.pathSeparator),
    );
  }

  Future<void> _assertZipMagic(File backupFile) async {
    final raf = await backupFile.open();
    try {
      final header = await raf.read(4);
      final isLocalHeader = header.length >= 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4B &&
          (header[2] == 0x03 && header[3] == 0x04 ||
              header[2] == 0x05 && header[3] == 0x06);
      if (!isLocalHeader) {
        throw const FormatException('备份文件不是有效的 ZIP（魔数不匹配）');
      }
    } finally {
      await raf.close();
    }
  }

  String _extensionOf(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final dot = normalized.lastIndexOf('.');
    if (dot == -1 || dot == normalized.length - 1) return '';
    return normalized.substring(dot + 1).toLowerCase();
  }

  int? _timestampMs(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.millisecondsSinceEpoch;
  }
}
