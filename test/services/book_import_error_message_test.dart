import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/book_import_service.dart';

void main() {
  group('describeBookImportError', () {
    test('keeps the friendly message of BookImportException', () {
      const error = BookImportException('没有从 EPUB 中解析出可导入的正文');
      expect(describeBookImportError(error), '没有从 EPUB 中解析出可导入的正文');
    });

    test('maps file system failures to a storage hint', () {
      final error = const FileSystemException('No space left', '/tmp/x');
      final message = describeBookImportError(error);
      expect(message, contains('存储空间'));
      expect(message, isNot(contains('No space left')));
    });

    test('falls back to a generic hint for unknown errors', () {
      final message = describeBookImportError(StateError('zip broken'));
      expect(message, contains('有效的 EPUB'));
      expect(message, isNot(contains('zip broken')));
    });
  });
}
