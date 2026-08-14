import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluidtext/services/backup/backup_restore_service.dart';
import 'package:fluidtext/storage/storage_layout.dart';

/// Measures restore time and peak RSS growth when importing large v2 JSON
/// backups (the worst case for memory: one giant JSON decoded at once).
///
/// Driven by `test/backup_restore_benchmark_test.dart` because the restore
/// path depends on Flutter; disabled unless FLUIDTEXT_RESTORE_BENCHMARK=1.
Future<Map<String, Object?>> runBackupRestoreBenchmark() async {
  final cases = <Map<String, Object?>>[];
  for (final cardCount in const [10000, 50000]) {
    cases.add(await _runCase(cardCount));
  }
  return <String, Object?>{
    'kind': 'backup_restore_benchmark',
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'cases': cases,
  };
}

Future<Map<String, Object?>> _runCase(int cardCount) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'fluidtext-restore-benchmark-',
  );
  try {
    // A single book with [cardCount] cards of ~300 CJK chars each, matching
    // the default 切分长度. Built as a v2 JSON payload (single-file worst
    // case: the whole library is decoded into memory at once).
    final content = '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。' * 10;
    final payload = <String, Object?>{
      'format': 'fluidtext.backup',
      'version': 2,
      'exportedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
      'books': [
        <String, Object?>{
          'id': 1,
          'title': '基准书',
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'fileHash': 'bench-hash-$cardCount',
          'contentFingerprint': 'bench-fp-$cardCount',
          'sourceFileName': 'bench.epub',
          'importedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          'cardCount': cardCount,
          'textCharCount': content.length * cardCount,
          'assetRootKey': null,
        },
      ],
      'bookAssets': <Object?>[],
      'bookCards': [
        for (var index = 0; index < cardCount; index++)
          <String, Object?>{
            'id': index + 1,
            'bookId': 1,
            'bookTitle': '基准书',
            'cardIndex': index,
            'chapterIndex': index ~/ 100,
            'chapterCardIndex': index % 100,
            'chapterTitle': null,
            'content': '$index$content',
            'blocksJson': null,
            'isRead': false,
            'readAt': null,
            'isFavorite': false,
            'favoritedAt': null,
          },
      ],
      'bookRemarks': <Object?>[],
      'readerSession': null,
    };
    final backupFile = File('${tempDir.path}/bench-backup.json');
    await backupFile.writeAsString(jsonEncode(payload), flush: true);
    final backupBytes = await backupFile.length();

    final layout = StorageLayout.modern(
      rootDirectory: Directory('${tempDir.path}/target'),
    );
    await layout.rootDirectory.create(recursive: true);

    // currentRss before/after alone misses the peak (GC may have run by the
    // time the restore returns), so sample periodically during the restore;
    // the event loop yields often enough on file/DB IO for the timer to fire.
    final rssBaseline = ProcessInfo.currentRss;
    var rssPeak = rssBaseline;
    final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final current = ProcessInfo.currentRss;
      if (current > rssPeak) rssPeak = current;
    });
    final stopwatch = Stopwatch()..start();
    final BackupRestoreResult result;
    try {
      result = await const BackupRestoreService().restore(
        backupFile: backupFile,
        targetLayout: layout,
        closeLiveDatabase: () async {},
      );
    } finally {
      sampler.cancel();
      final current = ProcessInfo.currentRss;
      if (current > rssPeak) rssPeak = current;
    }
    stopwatch.stop();

    return <String, Object?>{
      'cardCount': cardCount,
      'backupFileBytes': backupBytes,
      'restoreMillis': stopwatch.elapsedMilliseconds,
      'peakRssDeltaBytes': rssPeak - rssBaseline,
      'restoredCards': result.cardCount,
    };
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
