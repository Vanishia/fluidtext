import 'package:flutter_test/flutter_test.dart';
import 'package:fluidtext/services/text_splitter.dart';

void main() {
  group('TextSplitter', () {
    test('splits on Chinese sentence boundaries once target is reached', () {
      final splitter = TextSplitter(targetChars: 5);

      final parts = splitter.split('第一句内容。第二句内容！第三句内容？').toList();

      expect(parts, ['第一句内容。', '第二句内容！', '第三句内容？']);
    });

    test('keeps trailing text when no later boundary exists', () {
      final splitter = TextSplitter(targetChars: 5);

      final parts = splitter.split('abcdefg').toList();

      expect(parts, ['abcdefg']);
    });
  });
}
