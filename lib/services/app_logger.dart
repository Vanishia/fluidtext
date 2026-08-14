import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File-backed application logger.
///
/// Log lines are appended to `<support dir>/logs/fluidtext.log`; once the
/// file exceeds the size cap it is rotated to `fluidtext.1.log` (any older
/// rotation is discarded), so on-disk usage stays bounded. Every line is
/// also forwarded to `developer.log` for dev tooling.
///
/// Logging is fire-and-forget: writes are queued, all IO failures are
/// swallowed, and logging before [initialize] simply skips the file output.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const defaultMaxLogFileBytes = 512 * 1024;
  static const logFileName = 'fluidtext.log';
  static const rotatedLogFileName = 'fluidtext.1.log';

  File? _logFile;
  int _maxLogFileBytes = defaultMaxLogFileBytes;
  int _currentLength = 0;
  Future<void> _pendingWrites = Future<void>.value();
  bool _globalHooksInstalled = false;

  /// The active log file, or null before [initialize] completes.
  File? get logFile => _logFile;

  Future<void> initialize({
    Future<Directory> Function()? supportDirectoryProvider,
    int? maxLogFileBytes,
  }) async {
    final supportDirectory = await (supportDirectoryProvider ??
        getApplicationSupportDirectory)();
    final logsDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}logs',
    );
    await logsDirectory.create(recursive: true);
    _logFile = File(
      '${logsDirectory.path}${Platform.pathSeparator}$logFileName',
    );
    _maxLogFileBytes = maxLogFileBytes ?? defaultMaxLogFileBytes;
    _currentLength = await _logFile!.exists() ? await _logFile!.length() : 0;
    info('AppLogger', 'Logger initialized at ${_logFile!.path}');
  }

  /// Routes uncaught framework and zone errors into the log.
  void installGlobalErrorHooks() {
    if (_globalHooksInstalled) return;
    _globalHooksInstalled = true;

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      error(
        'FlutterError',
        'Unhandled framework error',
        error: details.exception,
        stackTrace: details.stack,
      );
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      this.error(
        'PlatformDispatcher',
        'Uncaught asynchronous error',
        error: error,
        stackTrace: stackTrace,
      );
      // Keep the default error handling; we only observe.
      return false;
    };
  }

  void info(String tag, String message) {
    _write('INFO', tag, message);
  }

  void warning(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write('WARN', tag, message, error: error, stackTrace: stackTrace);
  }

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _write('ERROR', tag, message, error: error, stackTrace: stackTrace);
  }

  void _write(
    String level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: tag,
      level: switch (level) {
        'ERROR' => 1000,
        'WARN' => 900,
        _ => 0,
      },
      error: error,
      stackTrace: stackTrace,
    );

    final file = _logFile;
    if (file == null) return;

    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' [')
      ..write(level)
      ..write('] ')
      ..write(tag)
      ..write(': ')
      ..write(message);
    if (error != null) buffer.write('\n  error: $error');
    if (stackTrace != null) buffer.write('\n  stackTrace: $stackTrace');
    buffer.write('\n');

    _enqueue(file, utf8.encode(buffer.toString()));
  }

  void _enqueue(File file, List<int> bytes) {
    _pendingWrites = _pendingWrites.then((_) async {
      try {
        if (_currentLength > 0 &&
            _currentLength + bytes.length > _maxLogFileBytes) {
          final rotated = File(
            '${file.parent.path}${Platform.pathSeparator}$rotatedLogFileName',
          );
          if (await rotated.exists()) await rotated.delete();
          if (await file.exists()) await file.rename(rotated.path);
          _currentLength = 0;
        }
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        _currentLength += bytes.length;
      } catch (_) {
        // Logging must never take the app down.
      }
    });
  }

  /// Waits for all queued writes to hit disk. Only for tests.
  @visibleForTesting
  Future<void> flushForTesting() => _pendingWrites;

  /// Drops all state so tests start from a clean logger. Only for tests.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _pendingWrites;
    _logFile = null;
    _maxLogFileBytes = defaultMaxLogFileBytes;
    _currentLength = 0;
  }
}
