import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/app_logger.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('fluidtext-logs-');
    await AppLogger.instance.resetForTesting();
  });

  tearDown(() async {
    await AppLogger.instance.resetForTesting();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> initializeLogger({int? maxLogFileBytes}) {
    return AppLogger.instance.initialize(
      supportDirectoryProvider: () async => tempDirectory,
      maxLogFileBytes: maxLogFileBytes,
    );
  }

  test('writes leveled lines with error and stack trace to the log file', () async {
    await initializeLogger();

    AppLogger.instance.info('TestTag', 'hello world');
    AppLogger.instance.warning('TestTag', 'careful', error: StateError('bad'));
    AppLogger.instance.error(
      'TestTag',
      'boom',
      error: ArgumentError('wrong'),
      stackTrace: StackTrace.fromString('trace-line'),
    );
    await AppLogger.instance.flushForTesting();

    final content = await AppLogger.instance.logFile!.readAsString();
    expect(content, contains('[INFO] TestTag: hello world'));
    expect(content, contains('[WARN] TestTag: careful'));
    expect(content, contains('Bad state: bad'));
    expect(content, contains('[ERROR] TestTag: boom'));
    expect(content, contains('Invalid argument(s): wrong'));
    expect(content, contains('trace-line'));
  });

  test('rotates the log file once it exceeds the size cap', () async {
    await initializeLogger(maxLogFileBytes: 128);

    for (var index = 0; index < 12; index++) {
      AppLogger.instance.info('TestTag', 'line-$index-xxxxxxxxxxxxxxxx');
    }
    await AppLogger.instance.flushForTesting();

    final logFile = AppLogger.instance.logFile!;
    final rotated = File(
      '${logFile.parent.path}${Platform.pathSeparator}'
      '${AppLogger.rotatedLogFileName}',
    );
    expect(await rotated.exists(), isTrue);
    // Only one backup generation is kept, so the rotated file holds some
    // earlier slice while the newest line is in the active file.
    expect(await rotated.readAsString(), contains('[INFO] TestTag: line-'));
    expect(await rotated.readAsString(), isNot(contains('line-11')));
    expect(await logFile.length(), lessThanOrEqualTo(128 + 128));
    expect(await logFile.readAsString(), contains('line-11'));
  });

  test('logging before initialize skips the file and never throws', () {
    expect(
      () => AppLogger.instance.error(
        'TestTag',
        'no file yet',
        error: StateError('ignored'),
      ),
      returnsNormally,
    );
    expect(AppLogger.instance.logFile, isNull);
  });
}
