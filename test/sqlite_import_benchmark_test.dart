import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/sqlite_import_benchmark.dart';

/// Drives the SQLite import benchmark from the Flutter test runner, because
/// plain `dart run` cannot compile the Flutter imports used by the
/// repository layer. Disabled unless FLUIDTEXT_SQLITE_BENCHMARK=1 is set:
///
/// ```powershell
/// $env:FLUIDTEXT_SQLITE_BENCHMARK = '1'
/// flutter test test/sqlite_import_benchmark_test.dart
/// ```
void main() {
  final enabled = Platform.environment['FLUIDTEXT_SQLITE_BENCHMARK'] == '1';

  test(
    'records SQLite import benchmark report',
    () async {
      final output = await runSqliteImportBenchmark();
      final outputFile = File(
        'build${Platform.pathSeparator}reports${Platform.pathSeparator}'
        'sqlite_import_benchmark.json',
      ).absolute;
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
        flush: true,
      );
      expect(output['cases'], isNotEmpty);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
