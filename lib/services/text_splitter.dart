class TextSplitter {
  TextSplitter({
    this.targetChars = 300,
  });

  final int targetChars;

  static const Set<String> _sentenceBoundaries = {
    '。',
    '！',
    '？',
    '.',
    '!',
    '?',
    '\n',
  };

  Iterable<String> split(String text) sync* {
    if (text.isEmpty) return;

    final bucket = StringBuffer();

    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      bucket.write(character);

      if (bucket.length >= targetChars && _isBoundary(character)) {
        yield bucket.toString();
        bucket.clear();
      }
    }

    if (bucket.isNotEmpty) {
      yield bucket.toString();
    }
  }

  bool _isBoundary(String character) {
    return _sentenceBoundaries.contains(character);
  }
}
