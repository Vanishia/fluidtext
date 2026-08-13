import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/sqlite/library_database.dart';
import '../storage/storage_layout.dart';
import 'library_migrator.dart';
import 'migration_progress.dart';
import 'migration_staging.dart';

/// Summary of a successful payload validation, later embedded into the
/// completion marker.
class MigrationValidationSummary {
  const MigrationValidationSummary({
    required this.bookCount,
    required this.cardCount,
    required this.assetCount,
    required this.remarkCount,
    required this.maxBookId,
    required this.maxCardId,
    required this.maxAssetId,
    required this.verifiedResourceCount,
    required this.validatedAt,
  });

  final int bookCount;
  final int cardCount;
  final int assetCount;
  final int remarkCount;
  final int? maxBookId;
  final int? maxCardId;
  final int? maxAssetId;

  /// Number of resource files whose SHA-256 matched the migration record.
  final int verifiedResourceCount;
  final DateTime validatedAt;
}

/// Validates a migrated staging payload against its [MigrationResult]
/// (plan step 10).
///
/// Re-opens the payload SQLite read-only in spirit: integrity check, foreign
/// key check, table counts, per-book card reconciliation, max-id
/// reconciliation and reader session references. Then re-hashes every copied
/// resource file. Any mismatch throws [MigrationException] with
/// [MigrationPhase.validating] and a sanitized diagnostic.
class MigrationValidator {
  const MigrationValidator({MigrationProgressCallback? onProgress})
    : _onProgress = onProgress;

  final MigrationProgressCallback? _onProgress;

  static const _databaseCheckSteps = 5;

  Future<MigrationValidationSummary> validate({
    required MigrationResult result,
    required StorageLayout legacyLayout,
  }) async {
    final staging = result.staging;
    final totalSteps = _databaseCheckSteps + result.copiedResourceHashes.length;
    var step = 0;
    _emit(step, totalSteps);

    final database = LibraryDatabase.file(staging.payloadDatabaseFile);
    try {
      final integrity = await database.integrityCheck();
      if (integrity.length != 1 || integrity.single != 'ok') {
        throw _failure(
          '迁移数据库完整性检查未通过',
          'integrity_check: ${integrity.join('; ')}',
          staging,
          legacyLayout,
        );
      }
      _emit(++step, totalSteps);

      final foreignKeys = await database.foreignKeyCheck();
      if (foreignKeys.isNotEmpty) {
        throw _failure(
          '迁移数据库存在外键违规',
          'foreign_key_check rows: ${foreignKeys.length}',
          staging,
          legacyLayout,
        );
      }
      _emit(++step, totalSteps);

      await _checkCount(
        database,
        'books',
        result.bookCount,
        staging,
        legacyLayout,
      );
      await _checkCount(
        database,
        'book_cards',
        result.cardCount,
        staging,
        legacyLayout,
      );
      await _checkCount(
        database,
        'book_assets',
        result.assetCount,
        staging,
        legacyLayout,
      );
      await _checkCount(
        database,
        'book_remarks',
        result.remarkCount,
        staging,
        legacyLayout,
      );
      _emit(++step, totalSteps);

      // Max-id reconciliation: future auto-assigned rowids must never
      // collide with preserved Isar ids.
      await _checkMaxId(
        database,
        'books',
        result.maxBookId,
        staging,
        legacyLayout,
      );
      await _checkMaxId(
        database,
        'book_cards',
        result.maxCardId,
        staging,
        legacyLayout,
      );
      await _checkMaxId(
        database,
        'book_assets',
        result.maxAssetId,
        staging,
        legacyLayout,
      );
      _emit(++step, totalSteps);

      // Per-book card reconciliation against the migration record.
      final groupRows = await database
          .customSelect(
            'SELECT book_id AS b, COUNT(*) AS c FROM book_cards '
            'GROUP BY book_id',
          )
          .get();
      final grouped = <int, int>{
        for (final row in groupRows) row.read<int>('b'): row.read<int>('c'),
      };
      if (grouped.length != result.cardCountByBook.length) {
        throw _failure(
          '迁移卡片按书分布与读取结果不一致',
          'grouped books=${grouped.length} '
              'expected=${result.cardCountByBook.length}',
          staging,
          legacyLayout,
        );
      }
      for (final entry in result.cardCountByBook.entries) {
        if (grouped[entry.key] != entry.value) {
          throw _failure(
            '迁移卡片按书分布与读取结果不一致',
            'bookId=${entry.key} grouped=${grouped[entry.key]} '
                'expected=${entry.value}',
            staging,
            legacyLayout,
          );
        }
      }

      // Reader session references must point at migrated books.
      final bookIdRows = await database
          .customSelect('SELECT id FROM books')
          .get();
      final bookIds = {for (final row in bookIdRows) row.read<int>('id')};
      await _checkSessionReferences(staging, bookIds, legacyLayout);
      _emit(++step, totalSteps);
    } on MigrationException {
      rethrow;
    } catch (error) {
      throw _failure('迁移校验失败', error, staging, legacyLayout);
    } finally {
      await database.close();
    }

    // Resource hash verification (no database needed).
    for (final entry in result.copiedResourceHashes.entries) {
      final file = File(
        StorageLayout.joinPath([
          staging.payloadDirectory.path,
          ...entry.key.split('/'),
        ], separator: Platform.pathSeparator),
      );
      if (!await file.exists()) {
        throw _failure(
          '迁移资源文件缺失',
          'missing resource ${entry.key}',
          staging,
          legacyLayout,
        );
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != entry.value) {
        throw _failure(
          '迁移资源文件校验不匹配',
          'hash mismatch ${entry.key}',
          staging,
          legacyLayout,
        );
      }
      _emit(++step, totalSteps);
    }

    return MigrationValidationSummary(
      bookCount: result.bookCount,
      cardCount: result.cardCount,
      assetCount: result.assetCount,
      remarkCount: result.remarkCount,
      maxBookId: result.maxBookId,
      maxCardId: result.maxCardId,
      maxAssetId: result.maxAssetId,
      verifiedResourceCount: result.copiedResourceHashes.length,
      validatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _checkCount(
    LibraryDatabase database,
    String table,
    int expected,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    final actual = row.read<int>('c');
    if (actual != expected) {
      throw _failure(
        '迁移数据计数不一致',
        '$table: actual=$actual expected=$expected',
        staging,
        legacyLayout,
      );
    }
  }

  Future<void> _checkMaxId(
    LibraryDatabase database,
    String table,
    int? expected,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) async {
    final row = await database
        .customSelect('SELECT MAX(id) AS m FROM $table')
        .getSingle();
    final actual = row.read<int?>('m');
    if (actual != expected) {
      throw _failure(
        '迁移 ID 分配校验不一致',
        '$table: max(id)=$actual expected=$expected',
        staging,
        legacyLayout,
      );
    }
  }

  Future<void> _checkSessionReferences(
    MigrationStaging staging,
    Set<int> bookIds,
    StorageLayout legacyLayout,
  ) async {
    final sessionFile = File(
      StorageLayout.joinPath([
        staging.payloadSettingsDirectory.path,
        StorageLayout.readerSessionFileName,
      ], separator: Platform.pathSeparator),
    );
    if (!await sessionFile.exists()) return;
    Object? decoded;
    try {
      decoded = jsonDecode(await sessionFile.readAsString());
    } catch (_) {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic>) return;
    final ids = decoded['lastOpenedBookIds'];
    if (ids is! List) return;
    for (final value in ids.whereType<num>()) {
      if (!bookIds.contains(value.toInt())) {
        throw _failure(
          '阅读记录引用了不存在的书籍',
          'reader_session references bookId=${value.toInt()}',
          staging,
          legacyLayout,
        );
      }
    }
  }

  MigrationException _failure(
    String message,
    Object diagnostic,
    MigrationStaging staging,
    StorageLayout legacyLayout,
  ) {
    var text = diagnostic.toString();
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
    return MigrationException(
      phase: MigrationPhase.validating,
      message: message,
      diagnostic: text,
    );
  }

  void _emit(int completed, int total) {
    _onProgress?.call(
      MigrationProgressEvent(
        phase: MigrationPhase.validating,
        completed: completed,
        total: total,
      ),
    );
  }
}
