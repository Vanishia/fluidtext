import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/backup_restore_benchmark.dart';

/// Drives the backup restore benchmark from the Flutter test runner, because
/// plain `dart run` cannot compile the Flutter imports used by the restore
/// path. Disabled unless FLUIDTEXT_RESTORE_BENCHMARK=1 is set:
///
/// ```powershell
/// $env:FLUIDTEXT_RESTORE_BENCHMARK = '1'
/// flutter test test/backup_restore_benchmark_test.dart
/// ```
void main() {
  final enabled = Platform.environment['FLUIDTEXT_RESTORE_BENCHMARK'] == '1';

  test(
    'records backup restore benchmark report',
    () async {
      final output = await runBackupRestoreBenchmark();
      final outputFile = File(
        'build${Platform.pathSeparator}reports${Platform.pathSeparator}'
        'backup_restore_benchmark.json',
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
