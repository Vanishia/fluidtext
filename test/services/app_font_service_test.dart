import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/settings/app_font_settings.dart';
import 'package:fluidtext/services/app_font_service.dart';

void main() {
  late Directory supportDirectory;
  late File pickedFont;
  late List<String> registeredFamilies;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('fluidtext-font-');
    pickedFont = File(
      '${supportDirectory.path}${Platform.pathSeparator}picked-font.ttf',
    );
    await pickedFont.writeAsBytes(const <int>[
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
    ]);
    registeredFamilies = <String>[];
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  AppFontService createService({PlatformFile? picked}) {
    return AppFontService(
      supportDirectory: () async => supportDirectory,
      picker: () async => picked,
      registrar: (family, file) async {
        expect(await file.exists(), isTrue);
        registeredFamilies.add(family);
      },
    );
  }

  test('imports, persists and reloads a custom font', () async {
    final platformFile = PlatformFile(
      name: '我的字体.ttf',
      path: pickedFont.path,
      size: await pickedFont.length(),
    );
    final imported = await createService(
      picked: platformFile,
    ).importFont(const AppFontSettings.system());

    expect(imported, isNotNull);
    expect(imported!.usesCustomFont, isTrue);
    expect(imported.displayName, '我的字体');
    expect(await File(imported.fontPath!).exists(), isTrue);
    expect(registeredFamilies, contains(imported.fontFamily));

    registeredFamilies.clear();
    final restored = await createService().load();

    expect(restored.usesCustomFont, isTrue);
    expect(restored.fontFamily, imported.fontFamily);
    expect(registeredFamilies, <String>[imported.fontFamily!]);
  });

  test('switching to system font removes the managed font file', () async {
    final imported = await createService(
      picked: PlatformFile(
        name: 'reader.otf',
        path: pickedFont.path,
        size: await pickedFont.length(),
      ),
    ).importFont(const AppFontSettings.system());
    final managedFile = File(imported!.fontPath!);

    final system = await createService().useSystemFont(imported);

    expect(system.usesCustomFont, isFalse);
    expect(await managedFile.exists(), isFalse);
    expect((await createService().load()).usesCustomFont, isFalse);
  });

  test('rejects files that are not valid TTF or OTF data', () async {
    await pickedFont.writeAsBytes(const <int>[1, 2, 3, 4, 5]);
    final service = createService(
      picked: PlatformFile(
        name: 'broken.ttf',
        path: pickedFont.path,
        size: await pickedFont.length(),
      ),
    );

    expect(
      () => service.importFont(const AppFontSettings.system()),
      throwsA(
        isA<AppFontImportException>().having(
          (error) => error.message,
          'message',
          contains('格式无效'),
        ),
      ),
    );
  });
}
