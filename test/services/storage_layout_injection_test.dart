import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/features/reader/reader_background_settings.dart';
import 'package:fluidtext/features/reader/reading_order.dart';
import 'package:fluidtext/services/app_behavior_settings_service.dart';
import 'package:fluidtext/services/book_asset_store.dart';
import 'package:fluidtext/services/reader_background_service.dart';
import 'package:fluidtext/services/reader_session_service.dart';
import 'package:fluidtext/storage/storage_layout.dart';

void main() {
  late Directory rootDirectory;
  late StorageLayout layout;
  late StorageLayoutProvider layoutProvider;

  setUp(() async {
    rootDirectory = await Directory.systemTemp.createTemp('fluidtext-layout-');
    layout = StorageLayout.modern(rootDirectory: rootDirectory);
    layoutProvider = () async => layout;
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  test(
    'behavior settings service writes through the injected layout',
    () async {
      final service = AppBehaviorSettingsService(storageLayout: layoutProvider);

      await service.save(
        const AppBehaviorSettings(readingOrder: ReadingOrder.sequential),
      );

      expect(await layout.appBehaviorSettingsFile.exists(), isTrue);
      final json =
          jsonDecode(await layout.appBehaviorSettingsFile.readAsString())
              as Map<String, dynamic>;
      expect(json['readingOrder'], ReadingOrder.sequential.name);
    },
  );

  test('reader session service writes through the injected layout', () async {
    final service = ReaderSessionService(storageLayout: layoutProvider);

    await service.saveLastOpenedBookIds(const [7, 11]);

    expect(await layout.readerSessionFile.exists(), isTrue);
    expect(await service.loadLastOpenedBookIds(), const [7, 11]);
  });

  test('behavior settings service round-trips page turn buttons flag', () async {
    final service = AppBehaviorSettingsService(storageLayout: layoutProvider);

    // 旧版本设置文件没有该键时默认开启。
    expect((await service.load()).showPageTurnButtons, isTrue);

    await service.save(
      const AppBehaviorSettings(showPageTurnButtons: false),
    );

    final restored = await service.load();
    expect(restored.showPageTurnButtons, isFalse);
  });

  test(
    'reader background service writes through the injected layout',
    () async {
      final service = ReaderBackgroundService(storageLayout: layoutProvider);

      await service.save(
        const ReaderBackgroundSettings(
          source: ReaderBackgroundSource.color,
          paletteKey: 'mist',
        ),
      );

      expect(await layout.readerBackgroundSettingsFile.exists(), isTrue);
    },
  );

  test(
    'book asset store resolves assets through the injected layout',
    () async {
      final store = BookAssetStore(storageLayout: layoutProvider);

      final relativePath = await store.writeAssetFile(
        assetRootKey: 'asset_root',
        assetKey: 'cover',
        extension: '.png',
        bytes: const [1, 2, 3],
      );
      final file = await store.resolveRelativeFile(relativePath);

      expect(relativePath, 'book_assets/asset_root/images/cover.png');
      expect(await file.readAsBytes(), const [1, 2, 3]);
      expect(file.path, contains(layout.bookAssetsDirectory.path));
    },
  );
}
