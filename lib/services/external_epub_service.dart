import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';
import 'book_import_service.dart';

/// A private, staged copy of a document opened by another application.
class ExternalEpubFile {
  const ExternalEpubFile({required this.name, this.path, this.error});

  final String name;
  final String? path;
  final String? error;

  Future<Uint8List> readBytes() {
    if (error != null || path == null) {
      AppLogger.instance.warning(
        'ExternalEpubService',
        'Native code could not stage $name',
        error: error,
      );
      throw const BookImportException('无法读取外部 EPUB 文件，请从文件管理器重新打开。');
    }
    return File(path!).readAsBytes();
  }
}

/// Native code retains incoming files until the normal app (including any
/// database migration) is ready. The shelf consumes this queue one at a time.
class ExternalEpubService extends ChangeNotifier {
  ExternalEpubService({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('fluidtext/external_epub'),
      _supported =
          supported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  static final instance = ExternalEpubService();

  final MethodChannel _channel;
  final bool _supported;
  final _pending = Queue<ExternalEpubFile>();
  Future<void>? _startFuture;
  int _bookshelfCount = 0;

  bool get hasPendingFiles => _pending.isNotEmpty;
  bool get hasActiveBookshelf => _bookshelfCount > 0;

  void attachBookshelf() => _bookshelfCount++;

  void detachBookshelf() {
    _bookshelfCount--;
    if (hasPendingFiles) notifyListeners();
  }

  ExternalEpubFile takeNext() => _pending.removeFirst();

  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'filesAvailable') await _collectPendingFiles();
    });
    await _collectPendingFiles();
  }

  Future<void> _collectPendingFiles() async {
    try {
      final files = await _channel.invokeListMethod<dynamic>(
        'takePendingFiles',
      );
      if (files == null || files.isEmpty) return;
      for (final file in files.cast<Map<dynamic, dynamic>>()) {
        _pending.add(
          ExternalEpubFile(
            name: file['name'] as String? ?? 'EPUB 文件',
            path: file['path'] as String?,
            error: file['error'] as String?,
          ),
        );
      }
      notifyListeners();
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'ExternalEpubService',
        'Failed to collect external EPUB files',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Only native code may remove its own staged files; never delete a
  /// caller-provided path or the original document in the file manager.
  Future<void> release(ExternalEpubFile file) async {
    if (!_supported || file.path == null) return;
    try {
      await _channel.invokeMethod<void>('releaseFile', {'path': file.path});
    } catch (error, stackTrace) {
      AppLogger.instance.warning(
        'ExternalEpubService',
        'Failed to release external EPUB copy',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
