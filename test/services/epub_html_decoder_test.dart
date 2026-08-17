import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/epub_html_decoder.dart';

void main() {
  group('decodeHtmlBytesLossy', () {
    const chapterText = '第一章 夜半钟声到客船';

    test('passes clean UTF-8 through unchanged', () {
      final bytes = utf8.encode('<p>$chapterText</p>');
      expect(decodeHtmlBytesLossy(bytes), '<p>$chapterText</p>');
    });

    test('decodes GBK bytes declared in the meta charset', () {
      final bytes = gbk.encode(
        '<html><head><meta charset="gb2312"></head>'
        '<body><p>$chapterText</p></body></html>',
      );
      expect(decodeHtmlBytesLossy(bytes), contains(chapterText));
    });

    test('decodes GBK bytes without any declaration by probing', () {
      final bytes = gbk.encode('<p>$chapterText</p>');
      expect(decodeHtmlBytesLossy(bytes), '<p>$chapterText</p>');
    });

    test('salvages malformed UTF-8 instead of misreading it as GBK', () {
      final longText = List.filled(50, chapterText).join();
      final bytes = utf8.encode('<p>$longText</p>')..[10] = 0x20;
      final decoded = decodeHtmlBytesLossy(bytes);
      expect(decoded, contains('夜半钟声到客船'));
      expect(_replacementCount(decoded), lessThan(10));
    });

    test('never throws on arbitrary bytes', () {
      final bytes = List<int>.generate(512, (index) => index % 256);
      expect(() => decodeHtmlBytesLossy(bytes), returnsNormally);
    });
  });
}

int _replacementCount(String text) {
  var count = 0;
  for (var index = 0; index < text.length; index++) {
    if (text.codeUnitAt(index) == 0xfffd) count++;
  }
  return count;
}
