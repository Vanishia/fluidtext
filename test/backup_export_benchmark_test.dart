import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/backup_export_benchmark.dart';

/// Drives the backup export benchmark from the Flutter test runner, because
/// plain `dart run` cannot compile the Flutter imports used by the
/// repository layer. Disabled unless FLUIDTEXT_EXPORT_BENCHMARK=1 is set:
///
/// ```powershell
/// $env:FLUIDTEXT_EXPORT_BENCHMARK = '1'
/// flutter test test/backup_export_benchmark_test.dart
/// ```
void main() {
  final enabled = Platform.environment['FLUIDTEXT_EXPORT_BENCHMARK'] == '1';

  test(
    'records backup export benchmark report',
    () async {
      final output = await runBackupExportBenchmark();
      final outputFile = File(
        'build${Platform.pathSeparator}reports${Platform.pathSeparator}'
        'backup_export_benchmark.json',
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
