import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/storage/sqlite/library_database.dart';

/// Smoke test: the bundled sqlite3 native library must ship FTS5 and the
/// trigram tokenizer — the entire full-text search plan depends on both.
void main() {
  late Directory directory;
  late LibraryDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fluidtext-fts-smoke-');
    database = LibraryDatabase.file(
      File('${directory.path}${Platform.pathSeparator}library.sqlite'),
    );
    await database.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await database.close();
    for (var attempt = 0; attempt < 5; attempt += 1) {
      if (!await directory.exists()) return;
      try {
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('fts5 trigram tokenizer is available and matches Chinese', () async {
    await database.customStatement(
      "CREATE VIRTUAL TABLE fts_probe USING fts5(content, tokenize='trigram')",
    );
    await database.customStatement(
      'INSERT INTO fts_probe(rowid, content) VALUES (1, ?)',
      ['长风破浪会有时，直挂云帆济沧海。Hello FluidText reader.'],
    );

    Future<List<String>> match(String query) async {
      final rows = await database
          .customSelect(
            'SELECT content FROM fts_probe WHERE fts_probe MATCH ?',
            variables: [Variable(query)],
          )
          .get();
      return rows.map((row) => row.data['content'] as String).toList();
    }

    expect(await match('"破浪会有时"'), isNotEmpty);
    expect(await match('"济沧海"'), isNotEmpty);
    expect(await match('fluidtext'), isNotEmpty);
    expect(await match('"不存在的关键词"'), isEmpty);
  });
}
