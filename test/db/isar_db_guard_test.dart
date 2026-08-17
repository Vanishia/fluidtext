import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/db/isar_db.dart';
import 'package:fluidtext/storage/storage_layout.dart';

void main() {
  test('IsarDb refuses to open Isar inside the new (target) layout', () async {
    final root = await Directory.systemTemp.createTemp('fluidtext-isar-guard-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final layout = StorageLayout.modern(rootDirectory: root);
    final db = IsarDb(storageLayout: () async => layout);

    await expectLater(
      () async => db.isar,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('禁止在新数据目录打开 Isar'),
        ),
      ),
    );
    // The guard must fire before Isar.open, so no default.isar is created.
    expect(await File('${root.path}/default.isar').exists(), isFalse);
  });
}
