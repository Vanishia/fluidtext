import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/services/reader_background_service.dart';

void main() {
  late Directory documentsDirectory;
  late ReaderBackgroundService service;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-background-',
    );
    service = ReaderBackgroundService(
      documentsDirectory: () async => documentsDirectory,
    );
  });

  tearDown(() async {
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test('clears files inside the managed background directory', () async {
    final managedDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}reader_backgrounds',
    );
    await managedDirectory.create();
    final image = File(
      '${managedDirectory.path}${Platform.pathSeparator}background.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);

    await service.clearImportedImage(
      ReaderBackgroundSettings(
        source: ReaderBackgroundSource.image,
        imagePath: image.path,
      ),
    );

    expect(await image.exists(), isFalse);
  });

  test('does not delete files from a directory with a matching prefix', () async {
    final outsideDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}reader_backgrounds_external',
    );
    await outsideDirectory.create();
    final image = File(
      '${outsideDirectory.path}${Platform.pathSeparator}background.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);

    await service.clearImportedImage(
      ReaderBackgroundSettings(
        source: ReaderBackgroundSource.image,
        imagePath: image.path,
      ),
    );

    expect(await image.exists(), isTrue);
  });

  test('saves managed images as controlled relative paths and reloads them',
      () async {
    final managedDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}reader_backgrounds',
    );
    await managedDirectory.create();
    final image = File(
      '${managedDirectory.path}${Platform.pathSeparator}background.png',
    );
    await image.writeAsBytes(const [1, 2, 3]);

    await service.save(
      ReaderBackgroundSettings(
        source: ReaderBackgroundSource.image,
        paletteKey: 'mist',
        imagePath: image.path,
      ),
    );

    final stored =
        jsonDecode(
              await File(
                '${documentsDirectory.path}${Platform.pathSeparator}'
                'reader_background.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(stored['imagePath'], 'reader_backgrounds/background.png');

    final loaded = await service.load();
    expect(loaded.hasCustomImage, isTrue);
    // Consumers use imagePath directly, so load resolves it back.
    expect(loaded.imagePath, image.path);
  });

  test('falls back to color for unsafe relative image paths', () async {
    await File(
      '${documentsDirectory.path}${Platform.pathSeparator}'
      'reader_background.json',
    ).writeAsString(
      jsonEncode(const {
        'source': 'image',
        'paletteKey': 'mist',
        'texture': 'none',
        'imagePath': '../outside.png',
      }),
    );

    final loaded = await service.load();

    expect(loaded.source, ReaderBackgroundSource.color);
    expect(loaded.imagePath, isNull);
  });

  test('falls back to color for relative paths outside the managed directory',
      () async {
    await File(
      '${documentsDirectory.path}${Platform.pathSeparator}'
      'reader_background.json',
    ).writeAsString(
      jsonEncode(const {
        'source': 'image',
        'paletteKey': 'mist',
        'texture': 'none',
        'imagePath': 'other_dir/background.png',
      }),
    );

    final loaded = await service.load();

    expect(loaded.source, ReaderBackgroundSource.color);
    expect(loaded.imagePath, isNull);
  });
}
