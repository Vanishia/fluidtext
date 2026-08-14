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

    test('hard-cuts text that never reaches a sentence boundary', () {
      final splitter = TextSplitter(targetChars: 10);

      final parts = splitter.split('字' * 1000).toList();

      expect(parts.length, greaterThan(1));
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(30));
      }
      expect(parts.join(), '字' * 1000);
    });

    test('hard cut never splits a surrogate pair', () {
      final splitter = TextSplitter(targetChars: 5);
      final text = '${'字' * 14}😀${'字' * 20}';

      final parts = splitter.split(text).toList();

      expect(parts.join(), text);
      for (final part in parts) {
        final units = part.codeUnits;
        for (var index = 0; index < units.length; index++) {
          final unit = units[index];
          final isHigh = unit >= 0xd800 && unit <= 0xdbff;
          final isLow = unit >= 0xdc00 && unit <= 0xdfff;
          if (isHigh) {
            expect(index + 1, lessThan(units.length));
            expect(units[index + 1], inExclusiveRange(0xdbff, 0xe000));
          }
          expect(isLow && (index == 0 || units[index - 1] < 0xd800), isFalse);
        }
      }
    });
  });

  group('CardLengthPolicy', () {
    const policy = CardLengthPolicy(targetChars: 10);

    test('does not break at a boundary before the target', () {
      expect(policy.shouldBreak(9, '。'), isFalse);
    });

    test('breaks at a boundary once the target is reached', () {
      expect(policy.shouldBreak(10, '。'), isTrue);
      expect(policy.shouldBreak(15, '!'), isTrue);
    });

    test('does not break past the target without a boundary', () {
      expect(policy.shouldBreak(20, 'x'), isFalse);
    });

    test('breaks without a boundary at the hard max', () {
      expect(policy.shouldBreak(30, 'x'), isTrue);
    });

    test('waits for the trail surrogate even at the hard max', () {
      expect(policy.shouldBreak(30, '😀'[0]), isFalse);
      expect(policy.shouldBreak(31, '😀'[1]), isTrue);
    });
  });
}
