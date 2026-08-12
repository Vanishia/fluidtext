import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:isar/isar.dart';

Future<void> main(List<String> args) async {
  final options = _BaselineOptions.parse(args);
  await _initializeIsarCore();

  final output = <String, Object?>{
    'format': 'fluidtext.isar_baseline.v1',
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
  stdout.writeln('Isar baseline written to ${options.outputFile.path}');
}

Future<Map<String, Object?>> _runCase(int cardCount) async {
  final directory = await Directory.systemTemp.createTemp(
    'fluidtext-isar-baseline-',
  );
  final name = 'baseline_${DateTime.now().microsecondsSinceEpoch}_$cardCount';
  try {
    final isar = await Isar.open(
      [BookSchema, BookAssetSchema, BookCardSchema],
      directory: directory.path,
      name: name,
      inspector: false,
    );
    final seedWrite = await _measure(() => _seed(isar, cardCount));
    final books = await _loadBooks(isar);
    final orderedIds = await _loadOrderedCardIds(
      isar,
      books.map((book) => book.id).toList(growable: false),
    );
    final sampleIds = orderedIds.take(100).toList(growable: false);

    final metrics = <String, int>{
      'seedWriteMs': seedWrite,
      'loadBooksMs': await _measure(() => _loadBooks(isar)),
      'loadOrderedCardIdsMs': await _measure(
        () => _loadOrderedCardIds(
          isar,
          books.map((book) => book.id).toList(growable: false),
        ),
      ),
      'loadCardsByIds100Ms': await _measure(
        () => _loadCardsByIds(isar, sampleIds),
      ),
      'loadBookStatsMs': await _measure(
        () => _loadBookStats(
          isar,
          books.map((book) => book.id).toList(growable: false),
        ),
      ),
      'toggleReadMs': await _measure(() async {
        final cards = await _loadCardsByIds(isar, [sampleIds.first]);
        await _toggleRead(isar, cards.first);
      }),
      'toggleFavoriteMs': await _measure(() async {
        final cards = await _loadCardsByIds(isar, [sampleIds.last]);
        await _toggleFavorite(isar, cards.first);
      }),
    };

    await isar.close(deleteFromDisk: true);
    return <String, Object?>{
      'cards': cardCount,
      'books': books.length,
      'metrics': metrics,
    };
  } finally {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<List<Book>> _loadBooks(Isar isar) {
  return isar.books.where().sortByCreatedAtDesc().findAll();
}

Future<List<int>> _loadOrderedCardIds(Isar isar, List<int> bookIds) async {
  if (bookIds.isEmpty) return const <int>[];

  final idsByBook = await Future.wait(
    bookIds.map(
      (bookId) => isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .sortByCardIndex()
          .idProperty()
          .findAll(),
    ),
  );
  return idsByBook.expand((ids) => ids).toList(growable: false);
}

Future<List<BookCard>> _loadCardsByIds(Isar isar, List<int> ids) async {
  if (ids.isEmpty) return const <BookCard>[];

  final cards = await Future.wait(ids.map(isar.bookCards.get));
  return cards.whereType<BookCard>().toList(growable: false);
}

Future<Map<int, Map<String, int>>> _loadBookStats(
  Isar isar,
  List<int> bookIds,
) async {
  final entries = await Future.wait(
    bookIds.map((bookId) async {
      final total = await isar.bookCards.filter().bookIdEqualTo(bookId).count();
      final read = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .and()
          .isReadEqualTo(true)
          .count();
      final favorite = await isar.bookCards
          .filter()
          .bookIdEqualTo(bookId)
          .and()
          .isFavoriteEqualTo(true)
          .count();
      return MapEntry(bookId, <String, int>{
        'total': total,
        'read': read,
        'favorite': favorite,
      });
    }),
  );
  return Map<int, Map<String, int>>.fromEntries(entries);
}

Future<void> _toggleRead(Isar isar, BookCard card) async {
  await isar.writeTxn(() async {
    card.isRead = !card.isRead;
    card.readAt = card.isRead ? DateTime.now() : null;
    await isar.bookCards.put(card);
  });
}

Future<void> _toggleFavorite(Isar isar, BookCard card) async {
  await isar.writeTxn(() async {
    card.isFavorite = !card.isFavorite;
    card.favoritedAt = card.isFavorite ? DateTime.now() : null;
    await isar.bookCards.put(card);
  });
}

Future<void> _seed(Isar isar, int cardCount) async {
  final books = <Book>[];
  final cards = <BookCard>[];
  final assets = <BookAsset>[];
  const booksPerCase = 4;
  final cardsPerBook = (cardCount / booksPerCase).ceil();
  var cardId = 1;

  for (var bookIndex = 0; bookIndex < booksPerCase; bookIndex += 1) {
    final bookId = bookIndex + 1;
    final book = Book()
      ..id = bookId
      ..title = 'Baseline Book $bookId'
      ..createdAt = DateTime.utc(2026, 1, bookId)
      ..fileHash = 'baseline-file-hash-$bookId'
      ..contentFingerprint = 'baseline-content-fingerprint-$bookId'
      ..sourceFileName = 'baseline-$bookId.epub'
      ..importedAt = DateTime.utc(2026, 1, bookId, 1)
      ..cardCount = cardsPerBook
      ..textCharCount = cardsPerBook * 80
      ..assetRootKey = 'asset_baseline_$bookId';
    books.add(book);

    assets.add(
      BookAsset()
        ..id = 100000 + bookId
        ..bookId = bookId
        ..assetKey = 'cover_$bookId'
        ..relativePath = 'book_assets/asset_baseline_$bookId/images/cover.png'
        ..createdAt = DateTime.utc(2026, 1, bookId),
    );

    for (var index = 0; index < cardsPerBook; index += 1) {
      if (cards.length >= cardCount) break;
      cards.add(
        BookCard()
          ..id = cardId
          ..bookId = bookId
          ..bookTitle = book.title
          ..cardIndex = index
          ..chapterIndex = index ~/ 20
          ..chapterCardIndex = index % 20
          ..chapterTitle = 'Chapter ${index ~/ 20}'
          ..content = 'Baseline content $cardId ${''.padRight(60, 'x')}'
          ..isRead = cardId.isEven
          ..readAt = cardId.isEven
              ? DateTime.utc(2026, 1, 1).add(Duration(minutes: cardId))
              : null
          ..isFavorite = cardId % 7 == 0
          ..favoritedAt = cardId % 7 == 0
              ? DateTime.utc(2026, 1, 2).add(Duration(minutes: cardId))
              : null,
      );
      cardId += 1;
    }
  }

  await isar.writeTxn(() async {
    await isar.books.putAll(books);
    await isar.bookCards.putAll(cards);
    await isar.bookAssets.putAll(assets);
  });
}

Future<int> _measure<T>(Future<T> Function() body) async {
  final stopwatch = Stopwatch()..start();
  await body();
  stopwatch.stop();
  return stopwatch.elapsedMilliseconds;
}

Future<void> _initializeIsarCore() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString());
  final packages = config['packages'] as List<dynamic>;
  final package = packages.cast<Map<String, dynamic>>().singleWhere(
    (entry) => entry['name'] == 'isar_flutter_libs',
  );
  final packageRoot = configFile.uri.resolve(package['rootUri'] as String);
  final packageRootDirectory = Directory.fromUri(packageRoot);
  final relativeLibraryPath = switch (Platform.operatingSystem) {
    'windows' => 'windows/isar.dll',
    'linux' => 'linux/libisar.so',
    'macos' => 'macos/libisar.dylib',
    _ => throw UnsupportedError(
      'Isar baseline is not supported on ${Platform.operatingSystem}',
    ),
  };
  final library = File(
    _join([packageRootDirectory.path, ...relativeLibraryPath.split('/')]),
  );
  if (!await library.exists()) {
    throw StateError('Isar native library not found at ${library.path}');
  }
  await Isar.initializeIsarCore(libraries: {Abi.current(): library.path});
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

class _BaselineOptions {
  const _BaselineOptions({required this.outputFile, required this.cardCounts});

  final File outputFile;
  final List<int> cardCounts;

  static _BaselineOptions parse(List<String> args) {
    var outputFile = File(_join(['build', 'reports', 'isar_baseline.json']));
    var cardCounts = const [100, 1000, 10000];

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

    return _BaselineOptions(
      outputFile: outputFile.absolute,
      cardCounts: cardCounts,
    );
  }
}
