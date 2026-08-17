/// Shared card length policy: text is cut at a sentence boundary once the
/// buffer reaches [targetChars]; if no boundary shows up by [hardMaxChars]
/// the buffer is cut anyway, so a pathological no-punctuation paragraph
/// cannot produce a single huge card.
class CardLengthPolicy {
  const CardLengthPolicy({required this.targetChars})
    : hardMaxChars = targetChars * 3;

  final int targetChars;
  final int hardMaxChars;

  static const Set<String> sentenceBoundaries = {
    '。',
    '！',
    '？',
    '.',
    '!',
    '?',
    '\n',
  };

  bool shouldBreak(int bufferedChars, String character) {
    // Never cut between a surrogate pair; wait for the trail surrogate.
    if (_isHighSurrogate(character)) return false;
    if (bufferedChars >= hardMaxChars) return true;
    return bufferedChars >= targetChars &&
        sentenceBoundaries.contains(character);
  }

  static bool _isHighSurrogate(String character) {
    if (character.isEmpty) return false;
    final codeUnit = character.codeUnitAt(0);
    return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
  }
}

class TextSplitter {
  TextSplitter({
    this.targetChars = 300,
  });

  final int targetChars;

  Iterable<String> split(String text) sync* {
    if (text.isEmpty) return;

    final policy = CardLengthPolicy(targetChars: targetChars);
    final bucket = StringBuffer();

    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      bucket.write(character);

      if (policy.shouldBreak(bucket.length, character)) {
        yield bucket.toString();
        bucket.clear();
      }
    }

    if (bucket.isNotEmpty) {
      yield bucket.toString();
    }
  }
}
