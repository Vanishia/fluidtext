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
}
