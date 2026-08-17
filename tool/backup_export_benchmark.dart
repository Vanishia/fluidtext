import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:fluidtext/services/backup/backup_export_service.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';
import 'package:fluidtext/storage/storage_layout.dart';

/// Measures export time and peak RSS growth when building a v3 ZIP backup
/// (the exporter currently assembles the whole archive in memory, plan
/// §11.7). Driven by `test/backup_export_benchmark_test.dart` because the
/// repository layer depends on Flutter; disabled unless
/// FLUIDTEXT_EXPORT_BENCHMARK=1.
Future<Map<String, Object?>> runBackupExportBenchmark() async {
  final cases = <Map<String, Object?>>[];
  for (final cardCount in const [10000, 50000]) {
    cases.add(await _runCase(cardCount));
  }
  return <String, Object?>{
    'kind': 'backup_export_benchmark',
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'cases': cases,
  };
}

Future<Map<String, Object?>> _runCase(int cardCount) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'fluidtext-export-benchmark-',
  );
  try {
    final layout = StorageLayout.modern(
      rootDirectory: Directory('${tempDir.path}/target'),
    );
    await layout.rootDirectory.create(recursive: true);
    final database = LibraryDatabase.file(layout.sqliteDatabaseFile);
    final repository = SqliteLibraryRepository(database);

    // One book with [cardCount] cards of ~300 CJK chars (matching the
    // default 切分长度) plus 20 image assets of 256KB each, so the export
    // covers both the library JSON and managed resource files.
    const assetCount = 20;
    const assetBytes = 256 * 1024;
    final assetDirectory = Directory(
      '${layout.rootDirectory.path}${Platform.pathSeparator}book_assets'
      '${Platform.pathSeparator}asset_bench${Platform.pathSeparator}images',
    );
    await assetDirectory.create(recursive: true);
    final pixel = List<int>.generate(assetBytes, (i) => (i * 31 + 7) & 0xff);
    final assetPaths = <String>[];
    for (var index = 0; index < assetCount; index += 1) {
      final relative =
          'book_assets/asset_bench/images/img_$index.jpg';
      await File(
        '${layout.rootDirectory.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}',
      ).writeAsBytes(pixel, flush: true);
      assetPaths.add(relative);
    }

    final content = '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。' * 10;
    final nowMs = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    await database.transaction(() async {
      await database.into(database.sqliteBooks).insert(
            SqliteBooksCompanion.insert(
              id: const Value(1),
              title: '导出基准书',
              createdAtMs: nowMs,
              fileHash: const Value('export-bench-hash'),
              contentFingerprint: const Value('export-bench-fp'),
              cardCount: Value(cardCount),
              assetRootKey: const Value('asset_bench'),
            ),
          );
      await database.batch((batch) {
        batch.insertAll(database.sqliteBookAssets, [
          for (var index = 0; index < assetCount; index += 1)
            SqliteBookAssetsCompanion.insert(
              id: Value(1000 + index),
              bookId: 1,
              assetKey: 'img_$index',
              relativePath: assetPaths[index],
              byteLength: const Value(assetBytes),
              createdAtMs: nowMs,
            ),
        ]);
        batch.insertAll(database.sqliteBookCards, [
          for (var index = 0; index < cardCount; index += 1)
            SqliteBookCardsCompanion.insert(
              id: Value(index + 1),
              bookId: 1,
              bookTitle: '导出基准书',
              cardIndex: index,
              chapterIndex: index ~/ 100,
              chapterCardIndex: index % 100,
              content: '$index$content',
              isRead: false,
              isFavorite: false,
            ),
        ]);
      });
    });

    final rssBaseline = ProcessInfo.currentRss;
    var rssPeak = rssBaseline;
    final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final current = ProcessInfo.currentRss;
      if (current > rssPeak) rssPeak = current;
    });
    final stopwatch = Stopwatch()..start();
    int zipBytes;
    try {
      final backup = await const BackupExportService().exportV3(
        repository: repository,
        layout: layout,
        appVersion: 'benchmark',
      );
      zipBytes = backup.bytes.length;
    } finally {
      sampler.cancel();
      final current = ProcessInfo.currentRss;
      if (current > rssPeak) rssPeak = current;
    }
    stopwatch.stop();

    await database.close();

    return <String, Object?>{
      'cardCount': cardCount,
      'assetCount': assetCount,
      'zipBytes': zipBytes,
      'exportMillis': stopwatch.elapsedMilliseconds,
      'peakRssDeltaBytes': rssPeak - rssBaseline,
    };
  } finally {
    if (await tempDir.exists()) {
      await _deleteDirectoryWithRetry(tempDir);
    }
  }
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (!await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 9) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

/// Allows `dart run tool/backup_export_benchmark.dart` for a quick local
/// report; the Flutter-gated path is `test/backup_export_benchmark_test.dart`.
Future<void> main() async {
  final output = await runBackupExportBenchmark();
  final outputFile = File(
    'build${Platform.pathSeparator}reports${Platform.pathSeparator}'
    'backup_export_benchmark.json',
  ).absolute;
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln(
    'Backup export benchmark written to ${outputFile.path}',
  );
}
