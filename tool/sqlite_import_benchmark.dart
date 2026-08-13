import 'dart:convert';
import 'dart:io';

import 'package:fluidtext/repositories/library_snapshot.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';
import 'package:fluidtext/storage/sqlite/sqlite_library_repository.dart';

Future<void> main(List<String> args) async {
  final options = _BenchmarkOptions.parse(args);

  final output = <String, Object?>{
    'format': 'fluidtext.sqlite_import_benchmark.v1',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'cardCounts': options.cardCounts,
    'cases': <Map<String, Object?>>[],
  };

  final cases = output['cases']! as List<Map<String, Object?>>;
  for (final cardCount in options.cardCounts) {
    cases.add(await _runCase(cardCount));
  }

  await options.outputFile.parent.create(recursive: true);
  await options.outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
    flush: true,
  );
  stdout.writeln(
    'SQLite import benchmark written to ${options.outputFile.path}',
  );
}

Future<Map<String, Object?>> _runCase(int cardCount) async {
  final directory = await Directory.systemTemp.createTemp(
    'fluidtext-sqlite-import-benchmark-',
  );
  try {
    final database = LibraryDatabase.file(
      File('${directory.path}${Platform.pathSeparator}benchmark.sqlite'),
    );
    final repository = SqliteLibraryRepository(database);

    final peakRssBefore = ProcessInfo.currentRss;
    final importMs = await _measure(() async {
      await repository.importBookDraft(_buildDraft(cardCount));
    });
    final peakRssAfter = ProcessInfo.currentRss;

    final books = await repository.loadBooks();
    final orderedIds = await repository.loadOrderedCardIds(
      books.map((book) => book.id).toList(growable: false),
    );
    final sampleIds = orderedIds.take(100).toList(growable: false);

    final metrics = <String, int>{
      'importMs': importMs,
      'loadBooksMs': await _measure(() => repository.loadBooks()),
      'loadOrderedCardIdsMs': await _measure(
        () => repository.loadOrderedCardIds(
          books.map((book) => book.id).toList(growable: false),
        ),
      ),
      'loadCardsByIds100Ms': await _measure(
        () => repository.loadCardsByIds(sampleIds),
      ),
      'loadBookStatsMs': await _measure(
        () => repository.loadBookStats(
          books.map((book) => book.id).toList(growable: false),
        ),
      ),
      'toggleReadMs': await _measure(() async {
        final cards = await repository.loadCardsByIds([sampleIds.first]);
        await repository.toggleRead(cards.first);
      }),
      'toggleFavoriteMs': await _measure(() async {
        final cards = await repository.loadCardsByIds([sampleIds.last]);
        await repository.toggleFavorite(cards.first);
      }),
      'rssBeforeBytes': peakRssBefore,
      'rssAfterBytes': peakRssAfter,
    };

    final integrity = await database.integrityCheck();
    await database.checkpoint();
    await database.close();

    return <String, Object?>{
      'cards': cardCount,
      'books': books.length,
      'integrityCheck': integrity,
      'metrics': metrics,
    };
  } finally {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

ImportBookDraft _buildDraft(int cardCount) {
  final createdAt = DateTime.utc(2026, 1, 1);
  final cards = <BookCardDraft>[
    for (var index = 0; index < cardCount; index += 1)
      BookCardDraft(
        bookTitle: 'Benchmark Book',
        cardIndex: index,
        chapterIndex: index ~/ 20,
        chapterCardIndex: index % 20,
        chapterTitle: 'Chapter ${index ~/ 20}',
        content: 'Benchmark content $index ${''.padRight(60, 'x')}',
        blocksJson: null,
      ),
  ];
  return ImportBookDraft(
    title: 'Benchmark Book',
    createdAt: createdAt,
    fileHash: 'benchmark-file-hash-$cardCount',
    contentFingerprint: LibraryContentIdentity.contentFingerprintForCardDrafts(
      cards,
    ),
    sourceFileName: 'benchmark-$cardCount.epub',
    importedAt: createdAt,
    cardCount: cardCount,
    textCharCount: cards.fold<int>(
      0,
      (sum, card) =>
          sum +
          LibraryContentIdentity.normalizeForFingerprint(card.content).length,
    ),
    assetRootKey: null,
    cards: cards,
    assets: const [],
  );
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
    var outputFile = File(
      _join(['build', 'reports', 'sqlite_import_benchmark.json']),
    );
    var cardCounts = const [100, 1000, 10000, 50000];

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
