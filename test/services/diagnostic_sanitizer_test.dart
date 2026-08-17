import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/diagnostic_sanitizer.dart';

void main() {
  group('sanitizeDiagnosticText', () {
    test('strips the causing statement and bound parameters sections', () {
      const raw =
          'SqliteException(19): while executing statement, constraint failed '
          'UNIQUE constraint failed: book_cards.book_id, book_cards.card_index '
          '(code 19)\n'
          '  Causing statement: INSERT INTO book_cards (content) VALUES (?)\n'
          '  parameters: 第一章 这里是正文内容……';
      final sanitized = sanitizeDiagnosticText(raw);
      expect(sanitized, contains('UNIQUE constraint failed'));
      expect(sanitized, isNot(contains('Causing statement')));
      expect(sanitized, isNot(contains('正文内容')));
      expect(sanitized, isNot(contains('parameters:')));
    });

    test('strips a bare parameters section even without a statement', () {
      const raw = 'SqliteException: constraint failed, parameters: secret';
      expect(sanitizeDiagnosticText(raw), 'SqliteException: constraint failed,');
    });

    test('leaves ordinary messages untouched', () {
      const raw = 'FileSystemException: Cannot rename file';
      expect(sanitizeDiagnosticText(raw), raw);
    });

    test('replaces the longest matching path first', () {
      final sanitized = sanitizeDiagnosticText(
        r'failed to copy C:\legacy\root\books\a.isar to C:\legacy\root',
        pathReplacements: const {
          r'C:\legacy\root': '<legacy>',
          r'C:\legacy\root\books': '<legacyBooks>',
        },
      );
      expect(
        sanitized,
        'failed to copy <legacyBooks>\\a.isar to <legacy>',
      );
    });

    test('ignores empty replacement keys', () {
      final sanitized = sanitizeDiagnosticText(
        'some error',
        pathReplacements: const {'': '<empty>'},
      );
      expect(sanitized, 'some error');
    });
  });
}
