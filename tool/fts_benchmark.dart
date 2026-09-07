import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  final options = _BenchmarkOptions.parse(args);
  final output = await runFtsBenchmark(cardCounts: options.cardCounts);

  await options.outputFile.parent.create(recursive: true);
  await options.outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln('FTS benchmark written to ${options.outputFile.path}');
}

/// Measures the cost of the FTS5 trigram index (rebuild time, query latency,
/// on-disk overhead) on synthetic Chinese-heavy libraries.
///
/// Exposed so the benchmark can also be driven from `flutter test` (plain
/// `dart run` cannot compile Flutter imports used by the repository layer).
Future<Map<String, Object?>> runFtsBenchmark({
  List<int> cardCounts = const [1000, 10000, 50000],
}) async {
  final output = <String, Object?>{
    'format': 'fluidtext.fts_benchmark.v1',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'cardCounts': cardCounts,
    'cases': <Map<String, Object?>>[],
  };

  final cases = output['cases']! as List<Map<String, Object?>>;
  for (final cardCount in cardCounts) {
    cases.add(await _runCase(cardCount));
  }
  return output;
}

Future<Map<String, Object?>> _runCase(int cardCount) async {
  final directory = await Directory.systemTemp.createTemp(
    'fluidtext-fts-benchmark-',
  );
  try {
    final databaseFile = File(
      '${directory.path}${Platform.pathSeparator}benchmark.sqlite',
    );
    final database = LibraryDatabase.file(databaseFile);
    final repository = SqliteLibraryRepository(database);

    // Baseline without the FTS sync triggers: drop them, import, wipe, then
    // recreate them for the real measurement.
    for (final trigger in const [
      'book_cards_fts_ai',
      'book_cards_fts_ad',
      'book_cards_fts_au',
    ]) {
      await database.customStatement('DROP TRIGGER $trigger');
    }
    final importWithoutFtsMs = await _measure(() async {
      await repository.importBookDraft(
        _buildDraft(cardCount, hashSuffix: 'baseline'),
      );
    });
    await database.customStatement('DELETE FROM book_cards');
    await database.customStatement('DELETE FROM books');
    for (final statement in sqliteSchemaV2FtsStatements) {
      if (statement.trimLeft().startsWith('CREATE TRIGGER')) {
        await database.customStatement(statement);
      }
    }

    final importMs = await _measure(() async {
      await repository.importBookDraft(_buildDraft(cardCount));
    });

    // Measure the post-upgrade backfill cost: the chunked rebuild is what
    // `ensureSearchIndexBuilt` runs when the search feature is first used
    // after an upgrade (that trigger path is covered by the upgrade test in
    // library_database_test.dart).
    final rebuildMs = await _measure(() => database.rebuildSearchIndex());

    final searchChineseMs = await _measure(() async {
      final hits = await repository.searchCards('黄河之水');
      if (hits.isEmpty) throw StateError('expected Chinese hits');
    });
    final searchEnglishMs = await _measure(() async {
      final hits = await repository.searchCards('FluidText');
      if (hits.isEmpty) throw StateError('expected English hits');
    });
    final searchNoHitMs = await _measure(() async {
      final hits = await repository.searchCards('不存在于任何卡片的词');
      if (hits.isNotEmpty) throw StateError('expected no hits');
    });

    await database.checkpoint();
    final dbFileBytes = await databaseFile.length();
    await database.close();

    // Wait for the closing background connection to release the file lock
    // (same pattern as SqliteSealer) before opening the raw connection.
    for (var attempt = 0;; attempt++) {
      try {
        final handle = await databaseFile.open(mode: FileMode.append);
        await handle.close();
        break;
      } on FileSystemException {
        if (attempt >= 40) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    // On-disk overhead: drop the FTS objects and VACUUM into a second file.
    final noFtsFile = File(
      '${directory.path}${Platform.pathSeparator}benchmark_nofts.sqlite',
    );
    final raw = sqlite3.open(databaseFile.path);
    raw.execute('DROP TRIGGER book_cards_fts_ai');
    raw.execute('DROP TRIGGER book_cards_fts_ad');
    raw.execute('DROP TRIGGER book_cards_fts_au');
    raw.execute('DROP TABLE book_cards_fts');
    raw.execute("VACUUM INTO '${noFtsFile.path.replaceAll("'", "''")}'");
    raw.dispose();
    final noFtsBytes = await noFtsFile.length();

    return <String, Object?>{
      'cards': cardCount,
      'metrics': <String, int>{
        'importMs': importMs,
        'importWithoutFtsMs': importWithoutFtsMs,
        'ftsRebuildMs': rebuildMs,
        'searchChineseMs': searchChineseMs,
        'searchEnglishMs': searchEnglishMs,
        'searchNoHitMs': searchNoHitMs,
        'dbFileBytes': dbFileBytes,
        'dbFileWithoutFtsBytes': noFtsBytes,
        'ftsOverheadBytes': dbFileBytes - noFtsBytes,
      },
    };
  } finally {
    await _deleteDirectoryWithRetry(directory);
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

/// ~300 字/卡的中文正文，部分卡片埋入固定检索词。
ImportBookDraft _buildDraft(int cardCount, {String hashSuffix = ''}) {
  final createdAt = DateTime.utc(2026, 1, 1);
  final cards = <BookCardDraft>[
    for (var index = 0; index < cardCount; index += 1)
      BookCardDraft(
        bookTitle: 'FTS Benchmark Book',
        cardIndex: index,
        chapterIndex: index ~/ 20,
        chapterCardIndex: index % 20,
        chapterTitle: 'Chapter ${index ~/ 20}',
        content: _cardContent(index) + (index == 0 ? hashSuffix : ''),
        blocksJson: null,
      ),
  ];
  return ImportBookDraft(
    title: 'FTS Benchmark Book',
    createdAt: createdAt,
    fileHash: 'fts-benchmark-file-hash-$cardCount$hashSuffix',
    contentFingerprint: LibraryContentIdentity.contentFingerprintForCardDrafts(
      cards,
    ),
    sourceFileName: 'fts-benchmark-$cardCount.epub',
    importedAt: createdAt,
    cardCount: cardCount,
    textCharCount: cards.fold<int>(0, (sum, card) => sum + card.content.length),
    assetRootKey: null,
    cards: cards,
    assets: const [],
  );
}

const _chinesePool =
    '天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳'
    '云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜';

String _cardContent(int index) {
  final random = Random(index);
  final buffer = StringBuffer();
  while (buffer.length < 280) {
    buffer.write(_chinesePool[random.nextInt(_chinesePool.length)]);
    if (buffer.length % 17 == 0) buffer.write('。');
  }
  if (index % 97 == 0) buffer.write('黄河之水天上来，奔流到海不复回。');
  if (index % 89 == 0) buffer.write('FluidText benchmark marker.');
  return buffer.toString();
}

Future<int> _measure<T>(Future<T> Function() body) async {
  final stopwatch = Stopwatch()..start();
  await body();
  stopwatch.stop();
  return stopwatch.elapsedMilliseconds;
}

class _BenchmarkOptions {
  const _BenchmarkOptions({required this.outputFile, required this.cardCounts});

  final File outputFile;
  final List<int> cardCounts;

  static _BenchmarkOptions parse(List<String> args) {
    var outputFile = File(_join(['build', 'reports', 'fts_benchmark.json']));
    var cardCounts = const [1000, 10000, 50000];

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--output':
          index += 1;
          if (index >= args.length) {
            throw const FormatException('Missing value for --output');
          }
          outputFile = File(args[index]);
        case '--cards':
          index += 1;
          if (index >= args.length) {
            throw const FormatException('Missing value for --cards');
          }
          cardCounts = args[index]
              .split(',')
              .map((value) => int.parse(value.trim()))
              .where((value) => value > 0)
              .toList(growable: false);
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }

    if (cardCounts.isEmpty) {
      throw const FormatException('--cards must contain at least one count');
    }

    return _BenchmarkOptions(
      outputFile: outputFile.absolute,
      cardCounts: cardCounts,
    );
  }
}

String _join(List<String> segments) {
  final separator = Platform.pathSeparator;
  final iterator = segments.iterator;
  if (!iterator.moveNext()) return '';
  var result = iterator.current;
  while (iterator.moveNext()) {
    final segment = iterator.current;
    result = result.endsWith(separator)
        ? '$result$segment'
        : '$result$separator$segment';
  }
  return result;
}
