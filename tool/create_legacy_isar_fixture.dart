import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:fluidtext/models/book.dart';
import 'package:fluidtext/models/book_asset.dart';
import 'package:fluidtext/models/book_card.dart';
import 'package:fluidtext/models/book_remark.dart';
import 'package:isar/isar.dart';

Future<void> main(List<String> args) async {
  final options = _FixtureOptions.parse(args);
  await _prepareOutputDirectory(options.outputDirectory, force: options.force);
  await _initializeIsarCore();

  final documentsDirectory = Directory(
    _join([options.outputDirectory.path, 'documents']),
  );
  final supportDirectory = Directory(
    _join([options.outputDirectory.path, 'support']),
  );
  await documentsDirectory.create(recursive: true);
  await supportDirectory.create(recursive: true);

  final now = DateTime.utc(2026, 8, 12, 1, 0);
  final books = <Book>[
    Book()
      ..id = 1
      ..title = 'Legacy Fixture One'
      ..createdAt = DateTime.utc(2026, 1, 1)
      ..fileHash = 'fixture-file-hash-1'
      ..contentFingerprint = 'fixture-content-fingerprint-1'
      ..sourceFileName = 'fixture-one.epub'
      ..importedAt = DateTime.utc(2026, 1, 2)
      ..cardCount = 2
      ..textCharCount = 33
      ..assetRootKey = 'asset_fixture_one',
    Book()
      ..id = 2
      ..title = 'Legacy Fixture Two'
      ..createdAt = DateTime.utc(2026, 2, 1)
      ..fileHash = 'fixture-file-hash-2'
      ..contentFingerprint = 'fixture-content-fingerprint-2'
      ..sourceFileName = 'fixture-two.epub'
      ..importedAt = DateTime.utc(2026, 2, 2)
      ..cardCount = 1
      ..textCharCount = 20,
  ];
  final cards = <BookCard>[
    BookCard()
      ..id = 10
      ..bookId = 1
      ..bookTitle = books.first.title
      ..cardIndex = 0
      ..chapterIndex = 0
      ..chapterCardIndex = 0
      ..chapterTitle = 'Opening'
      ..content = 'First legacy fixture card.'
      ..blocksJson = '[{"type":"paragraph"}]',
    BookCard()
      ..id = 11
      ..bookId = 1
      ..bookTitle = books.first.title
      ..cardIndex = 1
      ..chapterIndex = 0
      ..chapterCardIndex = 1
      ..chapterTitle = 'Opening'
      ..content = 'Second legacy fixture card.'
      ..isRead = true
      ..readAt = DateTime.utc(2026, 1, 3, 12)
      ..isFavorite = true
      ..favoritedAt = DateTime.utc(2026, 1, 4, 12),
    BookCard()
      ..id = 12
      ..bookId = 2
      ..bookTitle = books[1].title
      ..cardIndex = 0
      ..chapterIndex = 0
      ..chapterCardIndex = 0
      ..content = 'Third legacy fixture card.',
  ];
  final assets = <BookAsset>[
    BookAsset()
      ..id = 20
      ..bookId = 1
      ..assetKey = 'cover'
      ..originalHref = 'Images/cover.png'
      ..normalizedHref = 'images/cover.png'
      ..mimeType = 'image/png'
      ..relativePath = 'book_assets/asset_fixture_one/images/cover.png'
      ..byteLength = 8
      ..createdAt = DateTime.utc(2026, 1, 2),
  ];

  final mainIsar = await Isar.open(
    [BookSchema, BookAssetSchema, BookCardSchema],
    directory: documentsDirectory.path,
    inspector: false,
  );
  await mainIsar.writeTxn(() async {
    await mainIsar.books.putAll(books);
    await mainIsar.bookCards.putAll(cards);
    await mainIsar.bookAssets.putAll(assets);
  });
  await mainIsar.close();

  final remarkIsar = await Isar.open(
    [BookRemarkSchema],
    directory: documentsDirectory.path,
    name: 'book_remarks',
    inspector: false,
  );
  await remarkIsar.writeTxn(() async {
    await remarkIsar.bookRemarks.putAll([
      BookRemark()
        ..id = 1
        ..title = 'Pinned legacy title'
        ..updatedAt = DateTime.utc(2026, 1, 5),
      BookRemark()
        ..id = 2
        ..title = 'Second title note'
        ..updatedAt = DateTime.utc(2026, 2, 5),
    ]);
  });
  await remarkIsar.close();
  await _deleteIfExists(
    File(_join([documentsDirectory.path, 'default.isar-lck'])),
  );
  await _deleteIfExists(
    File(_join([documentsDirectory.path, 'book_remarks.isar-lck'])),
  );

  await _writeJson(
    File(_join([documentsDirectory.path, 'app_behavior_settings.json'])),
    <String, Object?>{
      'themeMode': 'system',
      'readingOrder': 'sequential',
      'showUnreadOnly': false,
      'contextBefore': 2,
      'contextAfter': 2,
      'analysisModuleOrder': ['overview', 'daily', 'books'],
      'savedAt': now.toIso8601String(),
    },
  );
  await _writeJson(
    File(_join([documentsDirectory.path, 'reader_session.json'])),
    <String, Object?>{
      'lastOpenedBookIds': [1, 2],
      'savedAt': now.toIso8601String(),
    },
  );
  final backgroundPath = _join([
    documentsDirectory.path,
    'reader_backgrounds',
    'legacy_background.png',
  ]);
  await File(backgroundPath).parent.create(recursive: true);
  await File(backgroundPath).writeAsBytes(const [137, 80, 78, 71], flush: true);
  await _writeJson(
    File(_join([documentsDirectory.path, 'reader_background.json'])),
    <String, Object?>{
      'source': 'image',
      'paletteKey': 'mist',
      'texture': 'none',
      'imagePath': backgroundPath,
      'savedAt': now.toIso8601String(),
    },
  );
  final fontPath = _join([supportDirectory.path, 'app_fonts', 'legacy.ttf']);
  await File(fontPath).parent.create(recursive: true);
  await File(fontPath).writeAsBytes(const [
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
  ], flush: true);
  await _writeJson(
    File(_join([supportDirectory.path, 'app_font_settings.json'])),
    <String, Object?>{
      'source': 'custom',
      'fontFamily': 'FluidTextLegacyFixture',
      'displayName': 'Legacy Fixture',
      'fontPath': fontPath,
      'savedAt': now.toIso8601String(),
    },
  );

  final assetFile = File(
    _join([
      documentsDirectory.path,
      'book_assets',
      'asset_fixture_one',
      'images',
      'cover.png',
    ]),
  );
  await assetFile.parent.create(recursive: true);
  await assetFile.writeAsBytes(const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], flush: true);

  await _writeJson(File(_join([options.outputDirectory.path, 'manifest.json'])), {
    'format': 'fluidtext.legacy_fixture',
    'sourceVersion': options.sourceVersion,
    'generatedAt': now.toIso8601String(),
    'expected': {
      'books': books.length,
      'bookCards': cards.length,
      'bookAssets': assets.length,
      'bookRemarks': 2,
      'lastOpenedBookIds': [1, 2],
    },
    'notes': [
      'Generate this fixture from a git worktree checked out at the source tag.',
      'Do not replace it with data generated from the current schema unless the source tag matches.',
    ],
  });

  stdout.writeln(
    'Legacy Isar fixture written to ${options.outputDirectory.path}',
  );
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
      'Fixture generation is not supported on ${Platform.operatingSystem}',
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

Future<void> _prepareOutputDirectory(
  Directory directory, {
  required bool force,
}) async {
  if (await directory.exists()) {
    final hasContents = !(await directory.list().isEmpty);
    if (hasContents && !force) {
      throw StateError(
        'Output directory already exists. Pass --force to replace it.',
      );
    }
    if (force) {
      await directory.delete(recursive: true);
    }
  }
  await directory.create(recursive: true);
}

Future<void> _writeJson(File file, Map<String, Object?> payload) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

String _join(List<String> segments) {
  final separator = Platform.pathSeparator;
  final iterator = segments.iterator;
  if (!iterator.moveNext()) return '';
  var result = iterator.current;
  while (iterator.moveNext()) {
    final segment = iterator.current;
    if (result.endsWith(separator)) {
      result = '$result$segment';
    } else {
      result = '$result$separator$segment';
    }
  }
  return result;
}

class _FixtureOptions {
  const _FixtureOptions({
    required this.outputDirectory,
    required this.sourceVersion,
    required this.force,
  });

  final Directory outputDirectory;
  final String sourceVersion;
  final bool force;

  static _FixtureOptions parse(List<String> args) {
    Directory? outputDirectory;
    var sourceVersion = '1.0.0';
    var force = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--output':
          index += 1;
          if (index >= args.length) {
            throw const FormatException('Missing value for --output');
          }
          outputDirectory = Directory(args[index]);
        case '--source-version':
          index += 1;
          if (index >= args.length) {
            throw const FormatException('Missing value for --source-version');
          }
          sourceVersion = args[index];
        case '--force':
          force = true;
        default:
          throw FormatException('Unknown argument: $arg');
      }
    }

    if (outputDirectory == null) {
      throw const FormatException(
        'Usage: dart run tool/create_legacy_isar_fixture.dart '
        '--output <directory> [--source-version 1.0.0] [--force]',
      );
    }

    return _FixtureOptions(
      outputDirectory: outputDirectory.absolute,
      sourceVersion: sourceVersion,
      force: force,
    );
  }
}
