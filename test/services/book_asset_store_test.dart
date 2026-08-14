import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/book_asset_store.dart';

void main() {
  late Directory documentsDirectory;
  late BookAssetStore store;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'fluidtext-assets-',
    );
    store = BookAssetStore(documentsDirectory: () async => documentsDirectory);
  });

  tearDown(() async {
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  test(
    'stages assets and prunes files not retained by the imported book',
    () async {
      const rootKey = 'asset_test';
      final keptPath = await store.writeAssetFile(
        assetRootKey: rootKey,
        assetKey: 'kept',
        extension: '.png',
        bytes: const [1, 2, 3],
      );
      final removedPath = await store.writeAssetFile(
        assetRootKey: rootKey,
        assetKey: 'removed',
        extension: '.png',
        bytes: const [4, 5, 6],
      );

      await store.pruneAssetRoot(
        assetRootKey: rootKey,
        retainedRelativePaths: {keptPath},
      );

      expect(await (await store.resolveRelativeFile(keptPath)).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(
        await (await store.resolveRelativeFile(removedPath)).exists(),
        isFalse,
      );
    },
  );

  test('rejects traversal and absolute resource paths', () async {
    await expectLater(
      store.resolveRelativeFile('../outside.png'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.resolveRelativeFile('/absolute.png'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.resolveRelativeFile(r'C:\absolute.png'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.resolveRelativeFile('reader_session.json'),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'refuses unsafe root keys without deleting the documents directory',
    () async {
      final sentinel = File(
        '${documentsDirectory.path}${Platform.pathSeparator}sentinel.txt',
      );
      await sentinel.writeAsString('keep');

      await store.deleteAssetRoot('..');

      expect(await sentinel.exists(), isTrue);
    },
  );

  test('deleteOrphanAssetRoots removes roots no book references', () async {
    await store.writeAssetFile(
      assetRootKey: 'asset_kept',
      assetKey: 'a',
      extension: '.png',
      bytes: const [1],
    );
    await store.writeAssetFile(
      assetRootKey: 'asset_orphan',
      assetKey: 'b',
      extension: '.png',
      bytes: const [2],
    );

    await store.deleteOrphanAssetRoots(activeRootKeys: {'asset_kept'});

    final assetsRoot = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}book_assets',
    );
    final remaining = await assetsRoot
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .map((entity) => entity.path)
        .toList();
    expect(remaining, hasLength(1));
    expect(remaining.single, contains('asset_kept'));
  });
}
